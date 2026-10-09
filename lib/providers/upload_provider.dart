import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/git_file.dart';
import '../models/history_item.dart';
import '../models/push_result.dart';
import '../models/repo_tree.dart';
import '../services/github_service.dart';
import '../services/repo_diff.dart';
import '../services/storage_service.dart';
import '../services/zip_service.dart';
import '../utils/path_validation.dart';

enum PreviewSource { zip, multi }

class UploadProvider extends ChangeNotifier {
  UploadProvider({GitHubService? gitHubService, StorageService? storageService})
      : _gitHubService = gitHubService ?? GitHubService(),
        _storageService = storageService ?? StorageService();

  final GitHubService _gitHubService;
  final StorageService _storageService;

  // Son yüklenen repo ağacı (sınıflandırmanın tek kaynağı)
  RepoTreeIndex? _index;
  bool _treeTruncated = false;

  // ---------------------------------------------------------------------------
  // Mod A: ZIP Durumu
  // ---------------------------------------------------------------------------
  String? _zipFileName;
  String? get zipFileName => _zipFileName;
  int _zipFileSize = 0;
  int get zipFileSize => _zipFileSize;
  Uint8List? _zipBytes;

  /// ZIP'ten ayıklanan ham dosyalar (yollar öneksiz; seçim durumu burada).
  List<GitFileItem> _zipRaw = [];

  /// Öneklenmiş + sınıflandırılmış kopyalar (ekranlar ve önizleme bunu okur).
  List<GitFileItem> _zipPreview = [];
  List<GitFileItem> get zipFiles => _zipPreview;

  List<GitFileItem> _zipDeletes = [];
  List<GitFileItem> get zipDeleteItems => _zipDeletes;

  List<String> _zipInvalid = [];
  List<String> get zipInvalidEntries => _zipInvalid;

  bool _zipStripRootDir = true;
  bool get zipStripRootDir => _zipStripRootDir;
  String _zipPrefix = '';
  String get zipPrefix => _zipPrefix;
  bool _zipOverwriteExisting = true;
  bool get zipOverwriteExisting => _zipOverwriteExisting;
  bool _zipDeleteUnlisted = false;
  bool get zipDeleteUnlisted => _zipDeleteUnlisted;

  /// ZIP yollarını repodaki gerçek konuma otomatik hizala (varsayılan açık).
  bool _zipAutoAlign = true;
  bool get zipAutoAlign => _zipAutoAlign;
  ZipAlignment? _zipAlignment;
  ZipAlignment? get zipAlignment => _zipAlignment;

  /// Yalnızca harf büyüklüğü farkı nedeniyle düzeltilen yol sayısı.
  int _zipCaseFixes = 0;

  /// Kullanıcıya gösterilecek otomatik eşleştirme özeti (yoksa null).
  String? get zipAlignNotice {
    final parts = <String>[];
    if (_zipAlignment != null) parts.add(_zipAlignment!.describe());
    if (_zipCaseFixes > 0) {
      parts.add('$_zipCaseFixes dosyanın harf büyüklüğü repodaki yola uyduruldu.');
    }
    return parts.isEmpty ? null : parts.join(' ');
  }

  /// "Sil" seçeneği açıkken hesaplanamadıysa nedenini açıklar.
  String? _zipDeleteNotice;
  String? get zipDeleteNotice => _zipDeleteNotice;

  // ---------------------------------------------------------------------------
  // Mod B: Çoklu Dosya Durumu
  // ---------------------------------------------------------------------------
  final List<GitFileItem> _multiFiles = [];
  List<GitFileItem> get multiFiles => _multiFiles;

  // ---------------------------------------------------------------------------
  // Gönderim İlerleme Durumu
  // ---------------------------------------------------------------------------
  bool _isUploading = false;
  bool get isUploading => _isUploading;
  String _uploadStep = '';
  String get uploadStep => _uploadStep;
  int _uploadProgressCurrent = 0;
  int get uploadProgressCurrent => _uploadProgressCurrent;
  int _uploadProgressTotal = 0;
  int get uploadProgressTotal => _uploadProgressTotal;
  String? _uploadError;
  String? get uploadError => _uploadError;
  String? _uploadErrorKind;
  String? get uploadErrorKind => _uploadErrorKind;

  // Son Başarılı Gönderim Sonucu
  PushResult? _lastResult;
  PushResult? get lastResult => _lastResult;
  String? _lastCommitUrl;
  String? get lastCommitUrl => _lastCommitUrl;

  // Geçmiş Kayıtları
  List<HistoryItem> _historyItems = [];
  List<HistoryItem> get historyItems => _historyItems;

  Future<void> loadHistory() async {
    _historyItems = await _storageService.getHistory();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await _storageService.clearHistory();
    _historyItems = [];
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Merkezi sınıflandırma
  // ---------------------------------------------------------------------------

  /// Repo ağacı (veya null = bilinmiyor) değiştiğinde ZIP ve Mod B'yi yeniden
  /// sınıflandırır. Ekranlar yalnızca bunu çağırır.
  void reclassifyAll(RepoTreeIndex? index, {bool truncated = false}) {
    _index = index;
    _treeTruncated = truncated;
    _rebuildZipPreview();
    for (final f in _multiFiles) {
      _autoMatchMulti(f);
    }
    RepoDiff.classify(_multiFiles, _index);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // MOD A İŞLEMLERİ
  // ---------------------------------------------------------------------------

  /// ZIP'i açar. Bozuk/şifreli ZIP için [ZipServiceException] fırlatır.
  void setZipArchive({
    required String fileName,
    required Uint8List bytes,
  }) {
    final result = ZipService.extractZipBytes(
      zipBytes: bytes,
      stripSingleRootDir: _zipStripRootDir,
    );
    _zipFileName = fileName;
    _zipFileSize = bytes.length;
    _zipBytes = bytes;
    _zipRaw = result.items;
    _zipInvalid = result.invalidEntries;
    _rebuildZipPreview();
    notifyListeners();
  }

  /// "Tek üst klasörü kaldır" anahtarı: ZIP bellekte tutulur, yeniden ayıklanır.
  void setZipStripRootDir(bool value) {
    _zipStripRootDir = value;
    final bytes = _zipBytes;
    if (bytes != null) {
      final previousSelection = <String, bool>{
        for (final f in _zipRaw) f.localPath: f.isSelected,
      };
      try {
        final result = ZipService.extractZipBytes(
          zipBytes: bytes,
          stripSingleRootDir: value,
        );
        for (final f in result.items) {
          f.isSelected = previousSelection[f.localPath] ?? true;
        }
        _zipRaw = result.items;
        _zipInvalid = result.invalidEntries;
      } on ZipServiceException {
        // Aynı bayt dizisi daha önce açıldığı için beklenmez; mevcut liste korunur.
      }
    }
    _rebuildZipPreview();
    notifyListeners();
  }

  void setZipPrefix(String value) {
    _zipPrefix = value;
    _rebuildZipPreview();
    notifyListeners();
  }

  void setZipAutoAlign(bool value) {
    _zipAutoAlign = value;
    _rebuildZipPreview();
    notifyListeners();
  }

  void setZipOverwriteExisting(bool value) {
    _zipOverwriteExisting = value;
    notifyListeners();
  }

  void setZipDeleteUnlisted(bool value) {
    _zipDeleteUnlisted = value;
    _rebuildZipPreview();
    notifyListeners();
  }

  void toggleZipFileSelection(int index, bool selected) {
    if (index >= 0 && index < _zipRaw.length) {
      _zipRaw[index].isSelected = selected;
      _rebuildZipPreview();
      notifyListeners();
    }
  }

  void selectAllZipFiles(bool selected) {
    for (final f in _zipRaw) {
      f.isSelected = selected;
    }
    _rebuildZipPreview();
    notifyListeners();
  }

  /// ZIP durumunu (dosyalar + seçenekler) tamamen sıfırlar.
  void resetZip({bool notify = true}) {
    _zipFileName = null;
    _zipFileSize = 0;
    _zipBytes = null;
    _zipRaw = [];
    _zipPreview = [];
    _zipDeletes = [];
    _zipInvalid = [];
    _zipStripRootDir = true;
    _zipPrefix = '';
    _zipOverwriteExisting = true;
    _zipDeleteUnlisted = false;
    _zipDeleteNotice = null;
    _zipAutoAlign = true;
    _zipAlignment = null;
    _zipCaseFixes = 0;
    if (notify) notifyListeners();
  }

  void _rebuildZipPreview() {
    final prefix = normalizeFolderPrefix(_zipPrefix);

    final index = _index;

    // 1) Temel yollar: tek kök klasör kaldırma sonrası yollar.
    var basePaths = <String>[for (final f in _zipRaw) f.repoPath];

    // 2) Otomatik hizalama: kullanıcı hedef klasör yazmadıysa, ZIP yollarını
    //    repodaki gerçek konuma (fazla/eksik klasör) uydurmayı dene.
    _zipAlignment = null;
    if (_zipAutoAlign &&
        prefix.isEmpty &&
        index != null &&
        index.nodes.isNotEmpty &&
        _zipRaw.isNotEmpty) {
      final originals = <String>[
        for (final f in _zipRaw)
          normalizeAndValidateGitPath(f.localPath).normalizedPath,
      ];
      final alignment = RepoDiff.detectAlignment(
        originalPaths: originals,
        currentPaths: basePaths,
        index: index,
      );
      if (alignment != null) {
        _zipAlignment = alignment;
        basePaths = [for (final o in originals) alignment.apply(o)];
      }
    }

    // 3) Harf büyüklüğü farkı: repoda yalnızca büyük/küçük harf farkıyla TEK
    //    eşleşen dosya varsa repodaki yolu kullan (yeni kopya oluşmasın).
    _zipCaseFixes = 0;
    final fullPaths = <String>[];
    for (final base in basePaths) {
      var full = '$prefix$base';
      if (index != null && !index.nodes.containsKey(full)) {
        final real = index.uniqueBlobIgnoreCase(full);
        if (real != null && real != full) {
          full = real;
          _zipCaseFixes++;
        }
      }
      fullPaths.add(full);
    }

    // Ham nesneleri mutasyona uğratmadan, hizalanmış kopyalar üret.
    _zipPreview = [
      for (var i = 0; i < _zipRaw.length; i++)
        _zipRaw[i].copyWith(repoPath: fullPaths[i]),
    ];
    RepoDiff.classify(_zipPreview, _index);

    // Hesaplanan SHA'ları ham nesnelere geri yaz (yeniden hash'lememek için).
    for (var i = 0; i < _zipRaw.length; i++) {
      _zipRaw[i].computedSha ??= _zipPreview[i].computedSha;
    }

    _zipDeletes = [];
    _zipDeleteNotice = null;
    if (_zipDeleteUnlisted) {
      if (index == null) {
        _zipDeleteNotice = 'Repo dosya listesi bilinmediği için silinecek dosyalar hesaplanamadı.';
      } else if (_treeTruncated) {
        _zipDeleteNotice = 'Repo ağacı kesildiği için silinecek dosyalar güvenle hesaplanamıyor; silme yapılmayacak.';
      } else {
        _zipDeletes = RepoDiff.computeUnlistedDeletes(
          index: index,
          zipEffectivePaths: _zipPreview.map((f) => f.repoPath),
          normalizedPrefix: prefix,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // MOD B İŞLEMLERİ
  // ---------------------------------------------------------------------------

  void addMultiFiles(List<GitFileItem> items) {
    for (final item in items) {
      _autoMatchMulti(item);
      _multiFiles.add(item);
    }
    RepoDiff.classify(_multiFiles, _index);
    notifyListeners();
  }

  /// Akıllı öneri: yalnızca blob eşleşmesi (tam ad; yoksa harf/kopya eki farkı
  /// yok sayılır). Kullanıcı yolu elle belirlediyse yola dokunulmaz, yalnızca
  /// öneri çipleri yenilenir. Ağaç sonradan yüklenirse de yeniden çalışır.
  void _autoMatchMulti(GitFileItem item) {
    final index = _index;
    if (index == null) return;

    // Yol daha önce otomatik atanmış mıydı? (ağaç değişince geri almak için)
    final wasAuto = item.needsChoice ||
        (item.suggestions.length == 1 && item.repoPath == item.suggestions.first);

    final matches = index.findBlobsByName(item.sourceName);
    item.suggestions = matches;
    if (item.pathManual) return;

    if (matches.length == 1) {
      item.repoPath = matches.first;
      item.needsChoice = false;
    } else if (matches.length > 1) {
      item.repoPath = item.sourceName;
      item.needsChoice = true; // kullanıcı seçmeli
    } else {
      if (wasAuto) item.repoPath = item.sourceName;
      item.needsChoice = false;
    }
  }

  /// Geri Al için: dosyaları yol/durumlarını bozmadan geri ekler.
  void restoreMultiFiles(List<GitFileItem> items, {int? atIndex}) {
    final existingIds = _multiFiles.map((f) => f.id).toSet();
    final toAdd = items.where((f) => !existingIds.contains(f.id)).toList();
    if (atIndex != null && atIndex >= 0 && atIndex <= _multiFiles.length) {
      _multiFiles.insertAll(atIndex, toAdd);
    } else {
      _multiFiles.addAll(toAdd);
    }
    RepoDiff.classify(_multiFiles, _index);
    notifyListeners();
  }

  int _multiIndexOfId(int id) => _multiFiles.indexWhere((f) => f.id == id);

  /// Kart alanına yazılan yolu OLDUĞU GİBİ saklar (normalleştirme sınıflandırma
  /// ve push sırasında yapılır; böylece yazarken imleç/metin bozulmaz).
  void updateMultiFilePathById(int id, String newPath) {
    final idx = _multiIndexOfId(id);
    if (idx == -1) return;
    _multiFiles[idx].repoPath = newPath;
    _multiFiles[idx].needsChoice = false;
    _multiFiles[idx].pathManual = true;
    RepoDiff.classify(_multiFiles, _index);
    notifyListeners();
  }

  void updateMultiFilePath(int index, String newPath) {
    if (index >= 0 && index < _multiFiles.length) {
      updateMultiFilePathById(_multiFiles[index].id, newPath);
    }
  }

  void removeMultiFile(int index) {
    if (index >= 0 && index < _multiFiles.length) {
      _multiFiles.removeAt(index);
      RepoDiff.classify(_multiFiles, _index);
      notifyListeners();
    }
  }

  void removeMultiFilesByIds(Set<int> ids) {
    _multiFiles.removeWhere((f) => ids.contains(f.id));
    RepoDiff.classify(_multiFiles, _index);
    notifyListeners();
  }

  /// Tüm listeyi temizler ve "Geri Al" için kaldırılan öğeleri döndürür.
  List<GitFileItem> clearMultiFiles() {
    final removed = List<GitFileItem>.from(_multiFiles);
    _multiFiles.clear();
    notifyListeners();
    return removed;
  }

  // Hazır Kısayol Uygulama (seçili kimlikler boşsa tüm dosyalara)
  void applyShortcutToMultiFiles(String prefix, Set<int> selectedIds) {
    final targets = selectedIds.isEmpty
        ? _multiFiles
        : _multiFiles.where((f) => selectedIds.contains(f.id)).toList();

    for (final item in targets) {
      if (prefix == 'Repo kökü' || prefix == '/') {
        item.repoPath = item.sourceName;
      } else {
        final clean = normalizeFolderPrefix(prefix);
        item.repoPath = '$clean${item.sourceName}';
      }
      item.needsChoice = false;
      item.pathManual = true;
    }
    RepoDiff.classify(_multiFiles, _index);
    notifyListeners();
  }

  // Gelişmiş Metin Komutu Ayrıştırma (Parse Command)
  // Örnek: "a.dart=lib/a.dart" veya "lib/models/: c.dart d.dart"
  void parseAndApplyTextCommands(String rawCommands) {
    final lines = rawCommands.split('\n');
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final eq = line.indexOf('=');
      final colon = line.indexOf(':');

      if (eq > 0) {
        // Format: file=path (yol `/` ile bitiyorsa dosya adı eklenir)
        final targetFile = line.substring(0, eq).trim();
        final targetPath = line.substring(eq + 1).trim();
        if (targetPath.isEmpty) continue;

        for (final item in _multiFiles) {
          if (item.sourceName == targetFile) {
            item.repoPath = appendFileNameIfFolder(targetPath, item.sourceName);
            item.needsChoice = false;
            item.pathManual = true;
          }
        }
      } else if (colon > 0) {
        // Format: folder/: file1 file2
        final folder = line.substring(0, colon).trim();
        final files = line
            .substring(colon + 1)
            .trim()
            .split(RegExp(r'\s+'))
            .where((f) => f.isNotEmpty);
        final cleanFolder = normalizeFolderPrefix(folder);

        for (final f in files) {
          for (final item in _multiFiles) {
            if (item.sourceName == f) {
              item.repoPath = '$cleanFolder${item.sourceName}';
              item.needsChoice = false;
              item.pathManual = true;
            }
          }
        }
      }
    }
    RepoDiff.classify(_multiFiles, _index);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Plan (önizleme + push girdisi)
  // ---------------------------------------------------------------------------

  PushPlan planFor(PreviewSource source) {
    switch (source) {
      case PreviewSource.zip:
        return PushPlan.build(
          _zipPreview.where((f) => f.isSelected).toList(),
          deletes: _zipDeleteUnlisted ? _zipDeletes : const <GitFileItem>[],
          skipExisting: !_zipOverwriteExisting,
        );
      case PreviewSource.multi:
        return PushPlan.build(List<GitFileItem>.from(_multiFiles));
    }
  }

  /// Başarılı push sonrası tüm yükleme durumunu temizler.
  void resetAfterPush() {
    resetZip(notify: false);
    _multiFiles.clear();
    notifyListeners();
  }

  /// Oturum kapatılınca veya repo tamamen değişince.
  void resetAll() {
    _index = null;
    _treeTruncated = false;
    _lastResult = null;
    _lastCommitUrl = null;
    _uploadError = null;
    _uploadErrorKind = null;
    resetZip(notify: false);
    _multiFiles.clear();
    notifyListeners();
  }

  /// Repo tarayıcıdan yapılan silme / taşıma commit'lerini de geçmişe yazar.
  Future<void> recordExternalCommit({
    required String owner,
    required String repo,
    required String branch,
    required String commitMessage,
    required String commitSha,
    required int filesCount,
  }) async {
    final item = HistoryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      repoFullName: '$owner/$repo',
      branch: branch,
      commitMessage: commitMessage,
      commitSha: commitSha,
      filesCount: filesCount,
      timestamp: DateTime.now(),
      commitUrl: 'https://github.com/$owner/$repo/commit/$commitSha',
    );
    await _storageService.addHistoryItem(item);
    await loadHistory();
  }

  // ---------------------------------------------------------------------------
  // ATOMİK PUSH ÇALIŞTIRMA
  // ---------------------------------------------------------------------------
  Future<bool> executePush({
    required String token,
    required String owner,
    required String repo,
    required String branch,
    required String commitMessage,
    required PushPlan plan,
    String? authorName,
    String? authorEmail,
  }) async {
    if (_isUploading) return false; // çift çağrı koruması

    final items = plan.pushItems;
    _isUploading = true;
    _uploadError = null;
    _uploadErrorKind = null;
    _uploadStep = 'Başlatılıyor...';
    _uploadProgressCurrent = 0;
    _uploadProgressTotal = items.length;
    notifyListeners();

    try {
      final result = await _gitHubService.executeAtomicPush(
        token: token,
        owner: owner,
        repo: repo,
        branch: branch,
        commitMessage: commitMessage,
        filesToPush: items,
        approvedDeletePaths: plan.approvedDeletePaths,
        authorName: authorName,
        authorEmail: authorEmail,
        onProgress: (step, current, total) {
          _uploadStep = step;
          _uploadProgressCurrent = current;
          _uploadProgressTotal = total;
          notifyListeners();
        },
      );

      _lastResult = result;
      final sha = result.commitSha;
      if (!result.noChanges && sha != null) {
        _lastCommitUrl = 'https://github.com/$owner/$repo/commit/$sha';

        final historyItem = HistoryItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          repoFullName: '$owner/$repo',
          branch: branch,
          commitMessage: commitMessage,
          commitSha: sha,
          filesCount: result.changedCount,
          timestamp: DateTime.now(),
          commitUrl: _lastCommitUrl!,
        );
        await _storageService.addHistoryItem(historyItem);
        await loadHistory();
      }

      _isUploading = false;
      notifyListeners();
      return true;
    } on GitHubApiException catch (e) {
      _uploadError = e.message;
      _uploadErrorKind = e.kind;
      _isUploading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _uploadError = 'Beklenmeyen hata: $e';
      _isUploading = false;
      notifyListeners();
      return false;
    }
  }
}
