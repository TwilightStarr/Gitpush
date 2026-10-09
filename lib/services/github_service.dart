import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/action_run.dart';
import '../models/path_commit_info.dart';
import '../models/git_file.dart';
import '../models/push_result.dart';
import '../models/repo.dart';
import '../models/repo_tree.dart';
import '../utils/path_validation.dart';
import '../utils/secret_guard.dart';

class GitHubApiException implements Exception {
  /// Dal, siz işlem yaparken ilerledi / oluşturuldu (yenileyip tekrar deneyin).
  static const String kindBranchMoved = 'branch_moved';

  /// Güvenlik ağı: beklenmeyen dosya kaybı tespit edildi, ref'e dokunulmadı.
  static const String kindSafetyNet = 'safety_net';

  final int statusCode;
  final String message;
  final String? kind;

  GitHubApiException(this.statusCode, this.message, {this.kind});

  @override
  String toString() => message;
}

class _PlannedFile {
  final GitFileItem item;
  final String path;
  final Uint8List bytes;
  String mode = '100644';
  bool existed = false;

  _PlannedFile(this.item, this.path, this.bytes);
}

class GitHubService {
  static const String baseUrl = 'https://api.github.com';
  static const String apiVersion = '2022-11-28';
  static const String userAgent = 'Gitpush';

  static const Duration _defaultTimeout = Duration(seconds: 30);
  static const Duration _blobTimeout = Duration(seconds: 90);
  static const int _maxAttempts = 3;
  static const int _blobConcurrency = 2;
  static const int _maxBlobBytes = 50 * 1024 * 1024;

  final http.Client _client;
  final Future<void> Function(Duration) _sleep;

  GitHubService({http.Client? client, Future<void> Function(Duration)? sleep})
      : _client = client ?? http.Client(),
        _sleep = sleep ?? _defaultSleep;

  static Future<void> _defaultSleep(Duration d) => Future<void>.delayed(d);

  Map<String, String> _headers(String token) {
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': apiVersion,
      'User-Agent': userAgent,
    };
  }

  // ---------------------------------------------------------------------------
  // Ortak HTTP katmanı: timeout, ağ hatası çevirisi, hız sınırı için yeniden deneme
  // ---------------------------------------------------------------------------

  Future<http.Response> _dispatch(
    String method,
    Uri uri,
    String token,
    Object? body,
    Duration timeout,
  ) {
    final headers = _headers(token);
    final String? encoded = body == null ? null : jsonEncode(body);
    if (encoded != null) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }

    final Future<http.Response> future = switch (method) {
      'GET' => _client.get(uri, headers: headers),
      'POST' => _client.post(uri, headers: headers, body: encoded),
      'PATCH' => _client.patch(uri, headers: headers, body: encoded),
      'DELETE' => _client.delete(uri, headers: headers, body: encoded),
      _ => throw ArgumentError('Desteklenmeyen HTTP yöntemi: $method'),
    };
    return future.timeout(timeout);
  }

  bool _isRateLimited(http.Response res) {
    if (res.statusCode == 429) return true;
    if (res.statusCode != 403) return false;
    if (res.headers.containsKey('retry-after')) return true;
    if (res.headers['x-ratelimit-remaining'] == '0') return true;
    final body = res.body.toLowerCase();
    return body.contains('rate limit') ||
        body.contains('abuse') ||
        body.contains('secondary');
  }

  /// Beklenecek süre; çok uzunsa null (yeniden denemeyi bırak).
  Duration? _retryDelay(http.Response res, int attempt) {
    final retryAfter = int.tryParse(res.headers['retry-after'] ?? '');
    if (retryAfter != null) {
      if (retryAfter > 60) return null;
      return Duration(seconds: retryAfter < 1 ? 1 : retryAfter);
    }
    if (res.headers['x-ratelimit-remaining'] == '0') {
      final reset = int.tryParse(res.headers['x-ratelimit-reset'] ?? '');
      if (reset != null) {
        final secs = reset - DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (secs > 60) return null;
        return Duration(seconds: secs < 1 ? 1 : secs + 1);
      }
    }
    return Duration(seconds: 2 * (1 << (attempt - 1))); // 2, 4 sn
  }

  Future<http.Response> _send(
    String method,
    String path,
    String token, {
    Object? body,
    Duration timeout = _defaultTimeout,
  }) async {
    _checkToken(token);
    final uri = Uri.parse('$baseUrl$path');
    // Token yalnızca api.github.com'a (https) gönderilir.
    if (uri.scheme != 'https' || uri.host != 'api.github.com') {
      throw GitHubApiException(0, 'Güvenlik: yalnızca api.github.com adresine istek gönderilebilir.');
    }
    for (var attempt = 1;; attempt++) {
      http.Response res;
      try {
        res = await _dispatch(method, uri, token, body, timeout);
      } on TimeoutException {
        throw GitHubApiException(
          0,
          'İstek zaman aşımına uğradı. Bağlantınızı kontrol edip tekrar deneyin.',
        );
      } on SocketException {
        throw GitHubApiException(
          0,
          'İnternet bağlantısı yok veya kesildi. Lütfen ağınızı kontrol edin.',
        );
      } on HandshakeException {
        throw GitHubApiException(
          0,
          'Güvenli bağlantı (SSL) kurulamadı. Ağ ayarlarınızı kontrol edin.',
        );
      } on http.ClientException {
        throw GitHubApiException(
          0,
          'Sunucuyla bağlantı kurulamadı. Lütfen tekrar deneyin.',
        );
      }

      if (attempt < _maxAttempts && _isRateLimited(res)) {
        final wait = _retryDelay(res, attempt);
        if (wait == null) return res;
        await _sleep(wait);
        continue;
      }
      return res;
    }
  }

  // ---------------------------------------------------------------------------
  // Hata biçimlendirme
  // ---------------------------------------------------------------------------

  String _messageFrom(String rawBody) {
    try {
      final json = jsonDecode(rawBody);
      if (json is Map && json['message'] is String) {
        return json['message'] as String;
      }
    } catch (_) {}
    return '';
  }

  String _formatError(int statusCode, String rawBody, {bool workflowHint = false}) {
    final msg = _messageFrom(rawBody);
    final lower = msg.toLowerCase();

    if (lower.contains('workflow') &&
        (lower.contains('scope') || lower.contains('permission'))) {
      return 'Token\'ınızda `workflow` yetkisi yok; ayarlardan güncelleyin '
          '(.github/workflows/ altına dosya göndermek için gerekli).';
    }

    switch (statusCode) {
      case 401:
        return 'Token geçersiz veya süresi dolmuş. Lütfen ayarları kontrol edin.';
      case 403:
        if (lower.contains('rate limit') || lower.contains('abuse')) {
          return 'GitHub API istek limiti aşıldı; birkaç dakika bekleyip tekrar deneyin.';
        }
        return 'Yetki yetersiz ($msg).';
      case 404:
        if (workflowHint) {
          return 'Depo, dal veya dosya yolu bulunamadı. .github/workflows/ dosyası '
              "gönderiyorsanız token'ınızda `workflow` yetkisi olmayabilir.";
        }
        return 'Depo, dal veya dosya yolu bulunamadı.';
      case 409:
        return 'Boş depo veya dal çakışması tespit edildi. Depo başlatılmamış olabilir.';
      case 422:
        return 'Doğrulama hatası ($msg). Lütfen girdi verilerini kontrol edin.';
      default:
        if (msg.isEmpty) {
          return 'Sunucuyla iletişim kurulurken beklenmeyen hata oluştu (Kod: $statusCode).';
        }
        return 'GitHub API hatası (Kod: $statusCode): $msg';
    }
  }

  GitHubApiException _apiError(http.Response res, {bool workflowHint = false}) {
    return GitHubApiException(
      res.statusCode,
      _formatError(res.statusCode, res.body, workflowHint: workflowHint),
    );
  }

  Map<String, dynamic> _json(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw GitHubApiException(res.statusCode, 'GitHub yanıtı okunamadı.');
  }

  String _encodePath(String path) {
    return path.split('/').map(Uri.encodeComponent).join('/');
  }

  static final RegExp _nameRe = RegExp(r'^[A-Za-z0-9_.-]{1,100}$');
  static final RegExp _tokenRe = RegExp(r'^[\x21-\x7E]{1,255}$');

  /// `/repos/{owner}/{repo}` yolunu doğrulayıp URL-encode ederek üretir
  /// (yol enjeksiyonu / `..` gezinmesine karşı).
  String _repo(String owner, String repo) {
    bool bad(String v) => !_nameRe.hasMatch(v) || v == '.' || v == '..';
    if (bad(owner)) throw GitHubApiException(0, 'Geçersiz depo sahibi adı.');
    if (bad(repo)) throw GitHubApiException(0, 'Geçersiz depo adı.');
    return '/repos/${Uri.encodeComponent(owner)}/${Uri.encodeComponent(repo)}';
  }

  /// Token'ın HTTP başlığına güvenle konabildiğini doğrular
  /// (satır sonu / boşluk / ASCII dışı karakter → başlık enjeksiyonu).
  void _checkToken(String token) {
    if (!_tokenRe.hasMatch(token)) {
      throw GitHubApiException(
        401,
        'Token geçersiz karakterler içeriyor. Lütfen yeniden kopyalayıp yapıştırın.',
      );
    }
  }

  bool _isEmptyRepo(http.Response res) {
    return res.statusCode == 409 && res.body.toLowerCase().contains('empty');
  }

  // ---------------------------------------------------------------------------
  // Kullanıcı / depo / dal
  // ---------------------------------------------------------------------------

  // 1. Kullanıcı doğrula
  Future<Map<String, dynamic>> verifyUser(String token) async {
    final response = await _send('GET', '/user', token);
    if (response.statusCode == 200) {
      return _json(response);
    }
    throw _apiError(response);
  }

  // 2. Depo listesi al (Tüm sayfalar)
  Future<List<GitHubRepo>> getRepositories(String token) async {
    final List<GitHubRepo> allRepos = [];
    int page = 1;
    const int perPage = 100;

    while (true) {
      final response = await _send(
        'GET',
        '/user/repos?per_page=$perPage&page=$page&sort=updated',
        token,
      );

      if (response.statusCode != 200) {
        throw _apiError(response);
      }

      final List list = jsonDecode(response.body) as List;
      if (list.isEmpty) break;

      allRepos.addAll(list.map((r) => GitHubRepo.fromJson(r as Map<String, dynamic>)));
      if (list.length < perPage) break;
      page++;
    }
    return allRepos;
  }

  // 3. Dallar (Branches) al
  Future<List<GitHubBranch>> getBranches(String token, String owner, String repo) async {
    final response = await _send('GET', '${_repo(owner, repo)}/branches?per_page=100', token);

    if (response.statusCode == 200) {
      final List list = jsonDecode(response.body) as List;
      return list.map((b) => GitHubBranch.fromJson(b as Map<String, dynamic>)).toList();
    }
    throw _apiError(response);
  }

  // 4. Yeni Depo Oluştur
  Future<GitHubRepo> createRepository(String token, String name, bool isPrivate) async {
    final response = await _send(
      'POST',
      '/user/repos',
      token,
      body: {
        'name': name,
        'private': isPrivate,
        'auto_init': true, // İlk commit otomatik atılsın
      },
    );

    if (response.statusCode == 201) {
      return GitHubRepo.fromJson(_json(response));
    }
    throw _apiError(response);
  }

  // 5. Yeni Dal Oluştur
  Future<void> createBranch(String token, String owner, String repo, String newBranch, String sourceSha) async {
    final response = await _send(
      'POST',
      '${_repo(owner, repo)}/git/refs',
      token,
      body: {
        'ref': 'refs/heads/$newBranch',
        'sha': sourceSha,
      },
    );

    if (response.statusCode != 201) {
      throw _apiError(response);
    }
  }

  // ---------------------------------------------------------------------------
  // Ağaç / ref okuma (hataları ASLA yutmaz)
  // ---------------------------------------------------------------------------

  /// Dalın son commit SHA'sı. 404 (dal yok) veya boş repo -> null.
  /// Diğer tüm hata kodları (403, 429, 5xx ...) istisna fırlatır.
  Future<String?> _getBranchHeadSha(String token, String owner, String repo, String branch) async {
    final res = await _send(
      'GET',
      '${_repo(owner, repo)}/git/ref/heads/${_encodePath(branch)}',
      token,
    );
    if (res.statusCode == 200) {
      final object = _json(res)['object'];
      final sha = object is Map ? object['sha'] : null;
      if (sha is! String) {
        throw GitHubApiException(200, 'Dal bilgisi okunamadı.');
      }
      return sha;
    }
    if (res.statusCode == 404 || _isEmptyRepo(res)) return null;
    throw _apiError(res);
  }

  Future<String> _getCommitTreeSha(String token, String owner, String repo, String commitSha) async {
    final res = await _send('GET', '${_repo(owner, repo)}/git/commits/$commitSha', token);
    if (res.statusCode != 200) throw _apiError(res);
    final tree = _json(res)['tree'];
    final sha = tree is Map ? tree['sha'] : null;
    if (sha is! String) {
      throw GitHubApiException(200, 'Commit ağaç bilgisi okunamadı.');
    }
    return sha;
  }

  Future<RepoTreeResult> _getTreeRecursive(String token, String owner, String repo, String treeSha) async {
    final res = await _send(
      'GET',
      '${_repo(owner, repo)}/git/trees/$treeSha?recursive=1',
      token,
    );
    if (res.statusCode == 200) {
      final data = _json(res);
      final list = (data['tree'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return RepoTreeResult(entries: list, truncated: data['truncated'] == true);
    }
    if (_isEmptyRepo(res)) return const RepoTreeResult.empty();
    throw _apiError(res);
  }

  // 6. Repo dosya ağacını (recursive) al.
  // Yalnızca gerçekten boş repo/dal (ref 404, tree 409) boş liste döner;
  // başarısızlıkta GitHubApiException fırlatır.
  Future<RepoTreeResult> getRecursiveTree(String token, String owner, String repo, String branch) async {
    final commitSha = await _getBranchHeadSha(token, owner, repo, branch);
    if (commitSha == null) return const RepoTreeResult.empty();
    final treeSha = await _getCommitTreeSha(token, owner, repo, commitSha);
    return _getTreeRecursive(token, owner, repo, treeSha);
  }

  // 7. Yerel Git Blob SHA-1 Hesaplama: sha1("blob <size>\0" + bytes)
  static String calculateGitBlobSha(Uint8List bytes) {
    final header = utf8.encode('blob ${bytes.length}\u0000');
    final combined = Uint8List(header.length + bytes.length)
      ..setAll(0, header)
      ..setAll(header.length, bytes);
    return sha1.convert(combined).toString();
  }

  // 8. Tekil Blob Yükle
  Future<String> createBlob(String token, String owner, String repo, Uint8List bytes, {bool workflowHint = false}) async {
    final response = await _send(
      'POST',
      '${_repo(owner, repo)}/git/blobs',
      token,
      body: {
        'content': base64Encode(bytes),
        'encoding': 'base64',
      },
      timeout: _blobTimeout,
    );

    if (response.statusCode == 201) {
      final sha = _json(response)['sha'];
      if (sha is String) return sha;
      throw GitHubApiException(201, 'Blob yanıtı okunamadı.');
    }
    throw _apiError(response, workflowHint: workflowHint);
  }

  static String _defaultMode(String path) {
    final name = path.split('/').last;
    final executable = name.endsWith('.sh') || name == 'gradlew';
    return executable ? '100755' : '100644';
  }

  // 9. ATOMİK COMMIT VE PUSH
  //
  // Güvenlik ilkeleri:
  //  * Ref varsa ama base_tree alınamazsa push İPTAL edilir (tree base_tree'siz
  //    oluşturulmaz).
  //  * Yeni tree oluşturulduktan sonra base ağaçla karşılaştırılır; onaylı silme
  //    listesinde olmayan bir dosya kaybolacaksa ref'e DOKUNULMADAN iptal edilir.
  //  * Silme yalnızca `approvedDeletePaths` içinde açıkça onaylanmışsa yapılır.
  Future<PushResult> executeAtomicPush({
    required String token,
    required String owner,
    required String repo,
    required String branch,
    required String commitMessage,
    required List<GitFileItem> filesToPush,
    Set<String> approvedDeletePaths = const <String>{},
    String? authorName,
    String? authorEmail,
    required Function(String step, int current, int total) onProgress,
  }) async {
    // Adım 0: Yerel doğrulama (son savunma hattı)
    final planned = <_PlannedFile>[];
    final requestedDeletes = <String>[];
    final seen = <String>{};
    var skipped = 0;

    for (final item in filesToPush) {
      if (item.status == GitFileStatus.unchanged) {
        skipped++;
        continue;
      }
      if (item.status == GitFileStatus.conflict) {
        throw GitHubApiException(
          0,
          'Çakışan dosya var (${item.targetPath}): ${item.conflictMessage ?? 'çakışma'}',
        );
      }

      final v = normalizeAndValidateGitPath(item.targetPath);
      if (!v.isValid) {
        throw GitHubApiException(0, 'Geçersiz dosya yolu (${item.targetPath}): ${v.error}');
      }
      if (!seen.add(v.normalizedPath.toLowerCase())) {
        throw GitHubApiException(0, 'Aynı yola giden birden fazla dosya var: ${v.normalizedPath}');
      }

      if (item.status == GitFileStatus.delete) {
        if (!approvedDeletePaths.contains(v.normalizedPath)) {
          throw GitHubApiException(
            0,
            'Onaylanmamış silme işlemi engellendi: ${v.normalizedPath}',
          );
        }
        requestedDeletes.add(v.normalizedPath);
        continue;
      }

      final bytes = item.bytes;
      if (bytes == null) {
        throw GitHubApiException(0, 'Dosya içeriği okunamadı: ${v.normalizedPath}');
      }
      if (bytes.length > _maxBlobBytes) {
        throw GitHubApiException(0, '50 MB üstü dosya gönderilemez: ${v.normalizedPath}');
      }
      planned.add(_PlannedFile(item, v.normalizedPath, bytes));
    }

    for (final key in seen) {
      var idx = key.lastIndexOf('/');
      while (idx > 0) {
        final parent = key.substring(0, idx);
        if (seen.contains(parent)) {
          throw GitHubApiException(
            0,
            'Aynı gönderimde "$parent" hem dosya hem klasör olarak kullanılıyor.',
          );
        }
        idx = parent.lastIndexOf('/');
      }
    }

    // Gizli bilgi (token, .env, özel anahtar vb.) sızıntısına karşı son savunma hattı
    final secretFindings = SecretGuard.scan(
      planned.map((p) => SecretCandidate(p.path, p.bytes)).toList(),
    );
    if (secretFindings.isNotEmpty) {
      throw GitHubApiException(0, SecretGuard.formatError(secretFindings));
    }

    final progressTotal = filesToPush.length;
    final touchesWorkflows = planned.any((p) => p.path.startsWith('.github/workflows/')) ||
        requestedDeletes.any((p) => p.startsWith('.github/workflows/'));

    // Adım 1: Dal referansı + base tree (alınamazsa İPTAL)
    onProgress('Branch bilgisi alınıyor...', 0, progressTotal);
    final parentSha = await _getBranchHeadSha(token, owner, repo, branch);

    String? baseTreeSha;
    RepoTreeIndex? baseIndex;
    var baseTruncated = false;
    final warnings = <String>[];

    if (parentSha != null) {
      baseTreeSha = await _getCommitTreeSha(token, owner, repo, parentSha);
      final baseTree = await _getTreeRecursive(token, owner, repo, baseTreeSha);
      baseTruncated = baseTree.truncated;
      baseIndex = RepoTreeIndex.fromEntries(baseTree.entries);
      if (baseTruncated) {
        warnings.add(
          'Repo ağacı çok büyük olduğu için kesildi; çakışma ve dosya kaybı '
          'denetimleri sınırlı yapıldı.',
        );
      }
    }

    // Adım 1b: Taze ağaca karşı çakışma denetimi
    if (baseIndex != null && !baseTruncated) {
      for (final p in planned) {
        final node = baseIndex.nodes[p.path];
        if (node != null && node.isTree) {
          throw GitHubApiException(
            0,
            'Bu yol bir klasör; dosya adı ekleyin: ${p.path}. Klasörün içeriği silinmemesi için işlem iptal edildi.',
          );
        }
        final ancestor = baseIndex.findFileAncestor(p.path);
        if (ancestor != null) {
          throw GitHubApiException(
            0,
            'Üst yol "$ancestor" repoda bir dosya; "${p.path}" oluşturulamaz.',
          );
        }
      }
    }

    // Silmeler: yalnızca repoda gerçekten var olan BLOB'lar
    final deletePaths = <String>[];
    for (final path in requestedDeletes) {
      if (baseIndex == null) {
        skipped++; // yeni dal / boş repo: silinecek bir şey yok
        continue;
      }
      if (baseTruncated) {
        throw GitHubApiException(
          0,
          'Repo ağacı kesildiği için silme işlemi doğrulanamıyor; işlem iptal edildi.',
        );
      }
      final node = baseIndex.nodes[path];
      if (node == null) {
        skipped++; // zaten yok
        continue;
      }
      if (!node.isBlob) {
        throw GitHubApiException(
          0,
          'Silinmek istenen yol bir dosya değil ($path); klasör silinmez.',
        );
      }
      deletePaths.add(path);
    }

    // Adım 1c: Değişmeyenleri ele, modları belirle
    final toUpload = <_PlannedFile>[];
    for (final p in planned) {
      final node = baseIndex?.nodes[p.path];
      final RepoNode? blobNode = (node != null && node.isBlob) ? node : null;
      String? knownSha = blobNode?.sha;
      if (baseTruncated && knownSha == null) knownSha = p.item.remoteSha;

      final localSha = p.item.computedSha ?? calculateGitBlobSha(p.bytes);
      if (knownSha != null && knownSha == localSha) {
        skipped++;
        continue;
      }

      p.existed = blobNode != null || (baseTruncated && p.item.remoteSha != null);
      p.mode = blobNode?.mode ?? p.item.remoteMode ?? _defaultMode(p.path);
      toUpload.add(p);
    }

    if (toUpload.isEmpty && deletePaths.isEmpty) {
      onProgress('Değişiklik yok', progressTotal, progressTotal);
      return PushResult(noChanges: true, skipped: skipped, warnings: warnings);
    }

    // Adım 2: Blob'ları yükle (en fazla 2 eşzamanlı istek)
    final workTotal = toUpload.length;
    final blobShas = List<String?>.filled(workTotal, null);
    var processed = 0;
    onProgress('Dosyalar yükleniyor (0/$workTotal)', 0, workTotal);

    for (var i = 0; i < workTotal; i += _blobConcurrency) {
      final end = i + _blobConcurrency > workTotal ? workTotal : i + _blobConcurrency;
      await Future.wait(<Future<void>>[
        for (var j = i; j < end; j++)
          () async {
            blobShas[j] = await createBlob(
              token,
              owner,
              repo,
              toUpload[j].bytes,
              workflowHint: touchesWorkflows,
            );
            processed++;
            onProgress('Dosyalar yükleniyor ($processed/$workTotal)', processed, workTotal);
          }(),
      ]);
    }

    final treeEntries = <Map<String, dynamic>>[];
    for (var j = 0; j < workTotal; j++) {
      treeEntries.add({
        'path': toUpload[j].path,
        'mode': toUpload[j].mode,
        'type': 'blob',
        'sha': blobShas[j],
      });
    }
    for (final path in deletePaths) {
      treeEntries.add({
        'path': path,
        'mode': '100644',
        'type': 'blob',
        'sha': null,
      });
    }

    // Adım 3: Git Tree oluştur (parent varsa base_tree ZORUNLU)
    if (parentSha != null && baseTreeSha == null) {
      throw GitHubApiException(
        0,
        'Base tree alınamadı; repo dosyalarının silinmemesi için işlem iptal edildi.',
      );
    }
    onProgress('Git ağacı oluşturuluyor...', workTotal, workTotal);
    final treeBody = <String, dynamic>{'tree': treeEntries};
    if (baseTreeSha != null) {
      treeBody['base_tree'] = baseTreeSha;
    }

    final treeRes = await _send(
      'POST',
      '${_repo(owner, repo)}/git/trees',
      token,
      body: treeBody,
    );
    if (treeRes.statusCode != 201) {
      throw _apiError(treeRes, workflowHint: touchesWorkflows);
    }
    final newTreeSha = _json(treeRes)['sha'] as String;

    // Adım 3b: GÜVENLİK AĞI — ref güncellenmeden önce yeni ağacı base ile kıyasla
    if (baseIndex != null && !baseTruncated) {
      onProgress('Güvenlik denetimi yapılıyor...', workTotal, workTotal);
      final newTree = await _getTreeRecursive(token, owner, repo, newTreeSha);
      if (newTree.truncated) {
        warnings.add(
          'Yeni ağaç çok büyük olduğu için kesildi; dosya kaybı denetimi atlandı.',
        );
      } else {
        final newIndex = RepoTreeIndex.fromEntries(newTree.entries);
        final approved = deletePaths.toSet();
        final unexpected = <String>[];
        for (final path in baseIndex.nonTreePaths) {
          final node = newIndex.nodes[path];
          final lost = node == null || node.isTree;
          if (lost && !approved.contains(path)) unexpected.add(path);
        }
        if (unexpected.isNotEmpty) {
          throw GitHubApiException(
            0,
            '${unexpected.length} dosya beklenmedik şekilde silinecekti, işlem iptal edildi. '
            'Repoda hiçbir değişiklik yapılmadı.',
            kind: GitHubApiException.kindSafetyNet,
          );
        }
      }
    }

    // Adım 4: Commit oluştur
    onProgress('Commit atılıyor...', workTotal, workTotal);
    final commitBody = <String, dynamic>{
      'message': commitMessage,
      'tree': newTreeSha,
      'parents': parentSha != null ? <String>[parentSha] : <String>[],
    };
    final name = authorName?.trim() ?? '';
    final email = authorEmail?.trim() ?? '';
    if (name.isNotEmpty && email.isNotEmpty) {
      final who = {'name': name, 'email': email};
      commitBody['author'] = who;
      commitBody['committer'] = who;
    }

    final commitRes = await _send(
      'POST',
      '${_repo(owner, repo)}/git/commits',
      token,
      body: commitBody,
    );
    if (commitRes.statusCode != 201) {
      throw _apiError(commitRes);
    }
    final newCommitSha = _json(commitRes)['sha'] as String;

    // Adım 5: Branch referansını güncelle (force: false)
    onProgress('Branch güncelleniyor...', workTotal, workTotal);
    if (parentSha != null) {
      final refUpdateRes = await _send(
        'PATCH',
        '${_repo(owner, repo)}/git/refs/heads/${_encodePath(branch)}',
        token,
        body: {'sha': newCommitSha, 'force': false},
      );
      if (refUpdateRes.statusCode != 200) {
        if (refUpdateRes.statusCode == 422) {
          throw GitHubApiException(
            422,
            'Dal siz işlem yaparken değişti; yenileyip tekrar deneyin.',
            kind: GitHubApiException.kindBranchMoved,
          );
        }
        throw _apiError(refUpdateRes);
      }
    } else {
      // Dal yok (404) / boş repo: yalnızca burada POST refs çalışır
      final refCreateRes = await _send(
        'POST',
        '${_repo(owner, repo)}/git/refs',
        token,
        body: {'ref': 'refs/heads/$branch', 'sha': newCommitSha},
      );
      if (refCreateRes.statusCode != 201) {
        if (refCreateRes.statusCode == 422) {
          throw GitHubApiException(
            422,
            'Dal siz işlem yaparken oluşturuldu; yenileyip tekrar deneyin.',
            kind: GitHubApiException.kindBranchMoved,
          );
        }
        throw _apiError(refCreateRes);
      }
    }

    onProgress('Tamamlandı!', workTotal, workTotal);
    return PushResult(
      commitSha: newCommitSha,
      added: toUpload.where((p) => !p.existed).length,
      updated: toUpload.where((p) => p.existed).length,
      deleted: deletePaths.length,
      skipped: skipped,
      warnings: warnings,
    );
  }

  // 10. Actions Workflow Çalışmaları (Runs). Hataları yutmaz.
  Future<List<ActionRun>> getActionRuns(String token, String owner, String repo) async {
    final response = await _send('GET', '${_repo(owner, repo)}/actions/runs?per_page=20', token);

    if (response.statusCode == 200) {
      final data = _json(response);
      final runs = data['workflow_runs'] as List? ?? [];
      return runs.map((r) => ActionRun.fromJson(r as Map<String, dynamic>)).toList();
    }
    throw _apiError(response);
  }

  // 11. Workflow Dispatch Tetikle
  Future<void> triggerWorkflow(String token, String owner, String repo, String workflowIdOrFileName, String ref) async {
    final response = await _send(
      'POST',
      '${_repo(owner, repo)}/actions/workflows/${Uri.encodeComponent(workflowIdOrFileName)}/dispatches',
      token,
      body: {'ref': ref},
    );

    if (response.statusCode != 204) {
      throw _apiError(response);
    }
  }

  // 12. Dosya Sil (Tekil Contents API ile commit)
  Future<void> deleteSingleFile(String token, String owner, String repo, String path, String branch, String sha, String message) async {
    final response = await _send(
      'DELETE',
      '${_repo(owner, repo)}/contents/${_encodePath(path)}',
      token,
      body: {
        'message': message,
        'sha': sha,
        'branch': branch,
      },
    );

    if (response.statusCode != 200) {
      throw _apiError(response);
    }
  }

  // ---------------------------------------------------------------------------
  // Dosya gezgini: içerik okuma, son commit, toplu silme / taşıma, kota
  // ---------------------------------------------------------------------------

  static final RegExp _shaRe = RegExp(r'^[0-9a-f]{40}$');

  /// Bir blob'un ham baytlarını indirir (Git Blobs API, base64).
  /// [maxBytes] aşılırsa içerik işlenmeden reddedilir.
  Future<Uint8List> getBlobBytes(
    String token,
    String owner,
    String repo,
    String sha, {
    int maxBytes = 2 * 1024 * 1024,
  }) async {
    if (!_shaRe.hasMatch(sha)) {
      throw GitHubApiException(0, 'Geçersiz dosya SHA değeri.');
    }
    final res = await _send(
      'GET',
      '${_repo(owner, repo)}/git/blobs/$sha',
      token,
      timeout: _blobTimeout,
    );
    if (res.statusCode != 200) throw _apiError(res);
    final data = _json(res);
    final size = data['size'];
    if (size is num && size > maxBytes) {
      throw GitHubApiException(0, 'Dosya önizleme sınırından büyük.');
    }
    final content = data['content'];
    if (data['encoding'] != 'base64' || content is! String) {
      throw GitHubApiException(200, 'Dosya içeriği okunamadı.');
    }
    try {
      return base64Decode(content.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      throw GitHubApiException(200, 'Dosya içeriği çözülemedi.');
    }
  }

  /// [path]'i dalda en son değiştiren commit. Bulunamazsa null.
  Future<PathCommitInfo?> getLastCommitForPath(
    String token,
    String owner,
    String repo,
    String branch,
    String path,
  ) async {
    final res = await _send(
      'GET',
      '${_repo(owner, repo)}/commits'
      '?sha=${Uri.encodeQueryComponent(branch)}'
      '&path=${Uri.encodeQueryComponent(path)}&per_page=1',
      token,
    );
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        return PathCommitInfo.fromJson(Map<String, dynamic>.from(decoded.first as Map));
      }
      return null;
    }
    if (res.statusCode == 404 || _isEmptyRepo(res)) return null;
    throw _apiError(res);
  }

  /// GitHub API (core) kalan istek kotası.
  Future<RateLimitInfo> getRateLimit(String token) async {
    final res = await _send('GET', '/rate_limit', token);
    if (res.statusCode == 200) return RateLimitInfo.fromJson(_json(res));
    throw _apiError(res);
  }

  /// Repoda var olan bir yolun silinmesi için asgari güvenlik denetimi.
  static bool _isSafeExistingPath(String path) {
    if (path.isEmpty || path.length > 4096) return false;
    if (path.startsWith('/') || path.endsWith('/') || path.contains('\\') || path.contains('\u0000')) return false;
    final segs = path.split('/');
    for (final seg in segs) {
      if (seg.isEmpty || seg == '.' || seg == '..') return false;
    }
    if (segs.first.toLowerCase() == '.git') return false;
    return true;
  }

  /// Verilen ağaç girdilerini TEK commit'te uygular (silme / yeniden adlandırma).
  /// Girdi: `{path, mode, type: 'blob', sha: <sha | null>}`; `sha: null` silmedir.
  ///
  /// Güvenlik: dal arada ilerlediyse (422) ref'e `force: false` ile yazıldığı
  /// için işlem iptal olur; hiçbir şey ezilmez. Yolların hepsi doğrulanır.
  Future<String> commitTreeChanges({
    required String token,
    required String owner,
    required String repo,
    required String branch,
    required String message,
    required List<Map<String, dynamic>> entries,
    String? authorName,
    String? authorEmail,
  }) async {
    if (entries.isEmpty) {
      throw GitHubApiException(0, 'Yapılacak bir değişiklik yok.');
    }
    if (entries.length > 1000) {
      throw GitHubApiException(0, 'Tek seferde en fazla 1000 dosya işlenebilir.');
    }
    if (message.trim().isEmpty) {
      throw GitHubApiException(0, 'Commit mesajı boş olamaz.');
    }

    final seen = <String>{};
    var touchesWorkflows = false;
    for (final e in entries) {
      final raw = e['path'];
      if (raw is! String) throw GitHubApiException(0, 'Geçersiz dosya yolu.');
      if (e['sha'] == null) {
        // Silinecek yol repoda ZATEN var: tuhaf ama geçerli adlar (ör. `a:b`)
        // silinebilsin diye yalnızca tehlikeli kalıplar reddedilir.
        if (!_isSafeExistingPath(raw)) {
          throw GitHubApiException(0, 'Geçersiz dosya yolu: $raw');
        }
      } else {
        final v = normalizeAndValidateGitPath(raw);
        if (!v.isValid || v.normalizedPath != raw) {
          throw GitHubApiException(0, 'Geçersiz dosya yolu ($raw): ${v.error ?? 'normalleştirilemedi'}');
        }
      }
      if (!seen.add(raw)) {
        throw GitHubApiException(0, 'Aynı yol birden fazla kez geçiyor: $raw');
      }
      if (raw.startsWith('.github/workflows/')) touchesWorkflows = true;
      final sha = e['sha'];
      if (sha != null && (sha is! String || !_shaRe.hasMatch(sha))) {
        throw GitHubApiException(0, 'Geçersiz SHA değeri: $raw');
      }
    }

    final parentSha = await _getBranchHeadSha(token, owner, repo, branch);
    if (parentSha == null) {
      throw GitHubApiException(404, 'Dal bulunamadı: $branch');
    }
    final baseTreeSha = await _getCommitTreeSha(token, owner, repo, parentSha);

    final treeRes = await _send(
      'POST',
      '${_repo(owner, repo)}/git/trees',
      token,
      body: {'base_tree': baseTreeSha, 'tree': entries},
    );
    if (treeRes.statusCode != 201) {
      throw _apiError(treeRes, workflowHint: touchesWorkflows);
    }
    final newTreeSha = _json(treeRes)['sha'] as String;

    final commitBody = <String, dynamic>{
      'message': message,
      'tree': newTreeSha,
      'parents': <String>[parentSha],
    };
    final name = authorName?.trim() ?? '';
    final email = authorEmail?.trim() ?? '';
    if (name.isNotEmpty && email.isNotEmpty) {
      final who = {'name': name, 'email': email};
      commitBody['author'] = who;
      commitBody['committer'] = who;
    }
    final commitRes = await _send(
      'POST',
      '${_repo(owner, repo)}/git/commits',
      token,
      body: commitBody,
    );
    if (commitRes.statusCode != 201) throw _apiError(commitRes);
    final newCommitSha = _json(commitRes)['sha'] as String;

    final refRes = await _send(
      'PATCH',
      '${_repo(owner, repo)}/git/refs/heads/${_encodePath(branch)}',
      token,
      body: {'sha': newCommitSha, 'force': false},
    );
    if (refRes.statusCode != 200) {
      if (refRes.statusCode == 422) {
        throw GitHubApiException(
          422,
          'Dal siz işlem yaparken değişti; yenileyip tekrar deneyin. Hiçbir değişiklik yapılmadı.',
          kind: GitHubApiException.kindBranchMoved,
        );
      }
      throw _apiError(refRes);
    }
    return newCommitSha;
  }

  /// Birden çok dosyayı tek commit'te siler (klasör silme dahil).
  Future<String> deletePathsInOneCommit({
    required String token,
    required String owner,
    required String repo,
    required String branch,
    required String message,
    required List<String> paths,
    String? authorName,
    String? authorEmail,
  }) {
    return commitTreeChanges(
      token: token,
      owner: owner,
      repo: repo,
      branch: branch,
      message: message,
      authorName: authorName,
      authorEmail: authorEmail,
      entries: [
        for (final p in paths) {'path': p, 'mode': '100644', 'type': 'blob', 'sha': null},
      ],
    );
  }

  /// Dosya/klasör taşıma ve yeniden adlandırma: içerik yeniden yüklenmez; eski
  /// yol silinir, aynı blob SHA'sı yeni yola bağlanır (tek commit).
  Future<String> movePathsInOneCommit({
    required String token,
    required String owner,
    required String repo,
    required String branch,
    required String message,
    required List<RepoMove> moves,
    String? authorName,
    String? authorEmail,
  }) {
    final entries = <Map<String, dynamic>>[];
    for (final m in moves) {
      entries.add({'path': m.from, 'mode': m.mode, 'type': 'blob', 'sha': null});
      entries.add({'path': m.to, 'mode': m.mode, 'type': 'blob', 'sha': m.sha});
    }
    return commitTreeChanges(
      token: token,
      owner: owner,
      repo: repo,
      branch: branch,
      message: message,
      authorName: authorName,
      authorEmail: authorEmail,
      entries: entries,
    );
  }

  // ---------------------------------------------------------------------------
  // Dosya düzenleme / oluşturma, commit geçmişi, dal silme
  // ---------------------------------------------------------------------------

  /// Tek bir dosyayı oluşturur veya içeriğini değiştirir (tek commit).
  /// Gizli bilgi taramasından geçer; bulunursa hiçbir şey yazılmaz.
  Future<String> commitFileContent({
    required String token,
    required String owner,
    required String repo,
    required String branch,
    required String path,
    required Uint8List bytes,
    required String message,
    String? mode,
    String? authorName,
    String? authorEmail,
  }) async {
    if (bytes.length > _maxBlobBytes) {
      throw GitHubApiException(0, '50 MB üstü dosya gönderilemez.');
    }
    final v = normalizeAndValidateGitPath(path);
    if (!v.isValid) throw GitHubApiException(0, v.error ?? 'Geçersiz dosya yolu.');
    final findings = SecretGuard.scan([SecretCandidate(v.normalizedPath, bytes)]);
    if (findings.isNotEmpty) {
      throw GitHubApiException(0, SecretGuard.formatError(findings));
    }
    final blobSha = await createBlob(
      token,
      owner,
      repo,
      bytes,
      workflowHint: v.normalizedPath.startsWith('.github/workflows/'),
    );
    return commitTreeChanges(
      token: token,
      owner: owner,
      repo: repo,
      branch: branch,
      message: message,
      authorName: authorName,
      authorEmail: authorEmail,
      entries: [
        {'path': v.normalizedPath, 'mode': mode ?? _defaultMode(v.normalizedPath), 'type': 'blob', 'sha': blobSha},
      ],
    );
  }

  /// Dalın (isteğe bağlı olarak tek bir yolun) commit geçmişi, yeniden eskiye.
  Future<List<PathCommitInfo>> getCommits(
    String token,
    String owner,
    String repo,
    String branch, {
    String? path,
    int page = 1,
    int perPage = 30,
  }) async {
    final q = StringBuffer('?sha=${Uri.encodeQueryComponent(branch)}&per_page=$perPage&page=$page');
    if (path != null && path.isNotEmpty) q.write('&path=${Uri.encodeQueryComponent(path)}');
    final res = await _send('GET', '${_repo(owner, repo)}/commits$q', token);
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is! List) return const <PathCommitInfo>[];
      return decoded
          .whereType<Map>()
          .map((m) => PathCommitInfo.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }
    if (_isEmptyRepo(res)) return const <PathCommitInfo>[];
    throw _apiError(res);
  }

  /// Dalı siler (varsayılan dal çağıran tarafta engellenir).
  Future<void> deleteBranch(String token, String owner, String repo, String branch) async {
    final res = await _send(
      'DELETE',
      '${_repo(owner, repo)}/git/refs/heads/${_encodePath(branch)}',
      token,
    );
    if (res.statusCode != 204) throw _apiError(res);
  }
}
