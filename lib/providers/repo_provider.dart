import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../models/path_commit_info.dart';
import '../models/repo.dart';
import '../models/repo_listing.dart';
import '../models/repo_tree.dart';
import '../services/github_service.dart';
import '../services/storage_service.dart';
import '../utils/path_validation.dart';

class RepoProvider extends ChangeNotifier {
  RepoProvider({GitHubService? gitHubService, StorageService? storageService})
      : _gitHubService = gitHubService ?? GitHubService(),
        _storageService = storageService ?? StorageService();

  final GitHubService _gitHubService;
  final StorageService _storageService;

  List<GitHubRepo> _repositories = [];
  List<GitHubRepo> get repositories => _repositories;

  List<GitHubBranch> _branches = [];
  List<GitHubBranch> get branches => _branches;

  GitHubRepo? _selectedRepo;
  GitHubRepo? get selectedRepo => _selectedRepo;

  String? _selectedBranch;
  String? get selectedBranch => _selectedBranch;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // --- Repo ağacı durumu ---
  List<Map<String, dynamic>> _currentTree = [];
  List<Map<String, dynamic>> get currentTree => _currentTree;

  /// Ağaç başarıyla alındıysa dolu; yükleniyor/hata durumunda null.
  RepoTreeIndex? _treeIndex;
  RepoTreeIndex? get treeIndex => _treeIndex;

  bool _isTreeLoading = false;
  bool get isTreeLoading => _isTreeLoading;

  String? _treeError;
  String? get treeError => _treeError;

  bool _treeTruncated = false;
  bool get treeTruncated => _treeTruncated;

  /// Ağaç her değiştiğinde (yüklendi/temizlendi/hata) artar; ekranlar bunu
  /// izleyerek yeniden sınıflandırma yapar.
  int _treeRevision = 0;
  int get treeRevision => _treeRevision;

  // Yarış durumu koruması: yalnızca en son istek geçerlidir.
  int _treeRequestId = 0;
  int _selectionEpoch = 0;

  void _clearTree() {
    _treeRequestId++; // uçuştaki eski isteklerin sonucu yok sayılsın
    _currentTree = [];
    _treeIndex = null;
    _treeError = null;
    _treeTruncated = false;
    _isTreeLoading = false;
    _treeRevision++;
  }

  // Tüm depoları çek
  Future<void> loadRepositories(String token) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _repositories = await _gitHubService.getRepositories(token);

      // Daha önce kaydedilmiş repo var mı kontrol et
      final lastSaved = await _storageService.getLastRepoAndBranch();
      GitHubRepo? found;
      final savedName = lastSaved['repo'];
      if (savedName != null) {
        for (final r in _repositories) {
          if (r.fullName == savedName) {
            found = r;
            break;
          }
        }
      }

      if (found != null) {
        _selectedRepo = found;
        _selectedBranch = lastSaved['branch'] ?? found.defaultBranch;
      } else if (_repositories.isNotEmpty) {
        _selectedRepo = _repositories.first;
        _selectedBranch = _selectedRepo!.defaultBranch;
      } else {
        _selectedRepo = null;
        _selectedBranch = null;
      }

      if (_selectedRepo != null) {
        await loadBranches(token, _selectedRepo!);
      }
    } on GitHubApiException catch (e) {
      _errorMessage = e.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Daları çek
  Future<void> loadBranches(String token, GitHubRepo repo) async {
    final epoch = _selectionEpoch;
    try {
      final list = await _gitHubService.getBranches(token, repo.owner, repo.name);
      if (epoch != _selectionEpoch) return; // arada repo değişti
      _branches = list;
      if (_selectedBranch == null || !_branches.any((b) => b.name == _selectedBranch)) {
        _selectedBranch = repo.defaultBranch;
      }
    } on GitHubApiException catch (e) {
      if (epoch != _selectionEpoch) return;
      _errorMessage = e.message;
      notifyListeners();
      return;
    }
    await refreshTree(token);
    notifyListeners();
  }

  // Repo Seç
  Future<void> selectRepository(String token, GitHubRepo repo) async {
    _selectionEpoch++;
    _selectedRepo = repo;
    _selectedBranch = repo.defaultBranch;
    _branches = [];
    _errorMessage = null;
    _clearTree();
    notifyListeners();

    await _storageService.saveLastRepoAndBranch(repo.fullName, _selectedBranch!);
    await loadBranches(token, repo);
    notifyListeners();
  }

  // Branch Seç
  Future<void> selectBranch(String token, String branch) async {
    _selectionEpoch++;
    _selectedBranch = branch;
    _clearTree();
    notifyListeners();
    if (_selectedRepo != null) {
      await _storageService.saveLastRepoAndBranch(_selectedRepo!.fullName, branch);
      await refreshTree(token);
    }
    notifyListeners();
  }

  /// Repo ağacını GitHub'dan taze çeker.
  /// Başarılıysa true; hata/yarış durumunda false ([treeError] dolar).
  Future<bool> refreshTree(String token) async {
    final repo = _selectedRepo;
    final branch = _selectedBranch;
    if (repo == null || branch == null) return false;

    final requestId = ++_treeRequestId;
    _isTreeLoading = true;
    _treeError = null;
    notifyListeners();

    var success = false;
    try {
      final result = await _gitHubService.getRecursiveTree(
        token,
        repo.owner,
        repo.name,
        branch,
      );
      if (requestId != _treeRequestId) return false; // eski istek
      _currentTree = result.entries;
      _treeIndex = RepoTreeIndex.fromEntries(result.entries);
      _treeTruncated = result.truncated;
      success = true;
    } on GitHubApiException catch (e) {
      if (requestId != _treeRequestId) return false;
      _currentTree = [];
      _treeIndex = null;
      _treeTruncated = false;
      _treeError = e.message;
    } catch (e) {
      if (requestId != _treeRequestId) return false;
      _currentTree = [];
      _treeIndex = null;
      _treeTruncated = false;
      _treeError = 'Repo dosya listesi alınamadı: $e';
    } finally {
      if (requestId == _treeRequestId) {
        _isTreeLoading = false;
        _treeRevision++;
        notifyListeners();
      }
    }
    return success;
  }

  // Yeni Depo Oluştur
  Future<GitHubRepo?> createNewRepo(String token, String name, bool isPrivate) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newRepo = await _gitHubService.createRepository(token, name, isPrivate);
      _selectionEpoch++;
      _repositories.insert(0, newRepo);
      _selectedRepo = newRepo;
      _selectedBranch = newRepo.defaultBranch;
      _branches = [];
      _clearTree(); // önceki reponun ağacı kalmasın
      await _storageService.saveLastRepoAndBranch(newRepo.fullName, _selectedBranch!);
      await loadBranches(token, newRepo);
      return newRepo;
    } on GitHubApiException catch (e) {
      _errorMessage = e.message;
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Yeni Branch Oluştur
  Future<bool> createNewBranch(String token, String newBranchName) async {
    if (_selectedRepo == null || _selectedBranch == null) return false;
    _isLoading = true;
    notifyListeners();

    try {
      final idx = _branches.indexWhere((b) => b.name == _selectedBranch);
      if (idx == -1) {
        _errorMessage = 'Kaynak dal bulunamadı; dal listesini yenileyin.';
        return false;
      }
      await _gitHubService.createBranch(
        token,
        _selectedRepo!.owner,
        _selectedRepo!.name,
        newBranchName,
        _branches[idx].commitSha,
      );

      _selectedBranch = newBranchName;
      await _storageService.saveLastRepoAndBranch(_selectedRepo!.fullName, newBranchName);
      await loadBranches(token, _selectedRepo!);
      return true;
    } on GitHubApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Dosya gezgini işlemleri (okuma, silme, taşıma / yeniden adlandırma)
  // ---------------------------------------------------------------------------

  GitHubRepo _requireRepo() {
    final repo = _selectedRepo;
    if (repo == null || _selectedBranch == null) {
      throw GitHubApiException(0, 'Önce bir depo ve dal seçin.');
    }
    return repo;
  }

  /// Dosya içeriğini indirir ([maxBytes] aşılırsa indirmez).
  Future<Uint8List> readFileBytes(String token, RepoEntry file, {int maxBytes = 512 * 1024}) {
    final repo = _requireRepo();
    final sha = file.sha;
    if (sha == null) {
      throw GitHubApiException(0, 'Bu dosyanın SHA bilgisi yok; ağacı yenileyin.');
    }
    if (file.size > maxBytes) {
      throw GitHubApiException(0, 'Dosya önizleme sınırından büyük.');
    }
    return _gitHubService.getBlobBytes(token, repo.owner, repo.name, sha, maxBytes: maxBytes);
  }

  Future<PathCommitInfo?> lastCommitFor(String token, String path) {
    final repo = _requireRepo();
    return _gitHubService.getLastCommitForPath(token, repo.owner, repo.name, _selectedBranch!, path);
  }

  /// Seçili yolları (dosya ve klasörler) TEK commit'te siler. Klasörler altındaki
  /// tüm dosyalarıyla birlikte silinir. Silinen dosya sayısı ve commit SHA döner.
  Future<({String commitSha, int fileCount})> deleteEntries({
    required String token,
    required List<RepoEntry> entries,
    required String message,
    String? authorName,
    String? authorEmail,
  }) async {
    final repo = _requireRepo();
    final paths = <String>{};
    for (final e in entries) {
      if (e.isDir) {
        for (final b in blobsUnder(_currentTree, e.path)) {
          paths.add(b['path'] as String);
        }
      } else {
        paths.add(e.path);
      }
    }
    if (paths.isEmpty) {
      throw GitHubApiException(0, 'Silinecek dosya bulunamadı (klasör boş olabilir).');
    }
    final sha = await _gitHubService.deletePathsInOneCommit(
      token: token,
      owner: repo.owner,
      repo: repo.name,
      branch: _selectedBranch!,
      message: message,
      paths: paths.toList()..sort(),
      authorName: authorName,
      authorEmail: authorEmail,
    );
    await refreshTree(token);
    return (commitSha: sha, fileCount: paths.length);
  }

  /// Taşıma / yeniden adlandırma planı. Hedef doluysa veya geçersizse
  /// [GitHubApiException] fırlatır; hiçbir ağ isteği yapılmaz.
  List<RepoMove> planMove(RepoEntry entry, String newPath) {
    final index = _treeIndex;
    if (index == null) {
      throw GitHubApiException(0, 'Depo ağacı yüklenmedi; yenileyip tekrar deneyin.');
    }
    if (_treeTruncated) {
      throw GitHubApiException(0, 'Depo çok büyük olduğu için ağaç eksik; taşıma güvenli değil.');
    }
    final v = normalizeAndValidateGitPath(newPath);
    if (!v.isValid) {
      throw GitHubApiException(0, v.error ?? 'Geçersiz yol.');
    }
    final target = v.normalizedPath;
    if (target == entry.path) {
      throw GitHubApiException(0, 'Yeni yol eskisiyle aynı.');
    }
    if (entry.isDir && target.startsWith('${entry.path}/')) {
      throw GitHubApiException(0, 'Klasör kendi içine taşınamaz.');
    }

    // Taşınacak kaynak blob'lar
    final sources = <Map<String, dynamic>>[];
    if (entry.isDir) {
      final prefix = '${entry.path}/';
      for (final e in _currentTree) {
        final path = e['path'];
        if (path is String && path.startsWith(prefix)) {
          if (e['type'] == 'commit') {
            throw GitHubApiException(0, 'Alt modül içeren klasör taşınamaz.');
          }
          if (e['type'] == 'blob') sources.add(e);
        }
      }
      if (sources.isEmpty) {
        throw GitHubApiException(0, 'Klasör boş; taşınacak dosya yok.');
      }
    } else {
      final node = index.nodes[entry.path];
      if (node == null || !node.isBlob || node.sha == null) {
        throw GitHubApiException(0, 'Dosya bulunamadı; ağacı yenileyin.');
      }
      sources.add({'path': node.path, 'sha': node.sha, 'mode': node.mode});
    }

    // Çakışma: hedef (büyük/küçük harf duyarsız) zaten var mı? Taşınan
    // kaynakların kendisi çakışma sayılmaz (yalnızca harf değişimi serbest).
    final moving = sources.map((e) => (e['path'] as String).toLowerCase()).toSet();
    final existing = <String>{
      for (final n in index.nodes.values)
        if (!moving.contains(n.path.toLowerCase())) n.path.toLowerCase(),
    };

    final moves = <RepoMove>[];
    for (final src in sources) {
      final from = src['path'] as String;
      final to = entry.isDir ? target + from.substring(entry.path.length) : target;
      final lower = to.toLowerCase();
      if (existing.contains(lower)) {
        throw GitHubApiException(0, 'Hedefte zaten bir öğe var: $to');
      }
      // Hedefin üst yolları bir DOSYA ise klasör açılamaz
      var idx = lower.lastIndexOf('/');
      while (idx > 0) {
        if (existing.contains(lower.substring(0, idx))) {
          final parent = to.substring(0, idx);
          final node = index.nodes[parent];
          if (node == null) {
            throw GitHubApiException(0, 'Harf büyüklüğü farkıyla çakışan bir yol var: $parent');
          }
          if (!node.isTree) {
            throw GitHubApiException(0, '"$parent" bir dosya; altında klasör oluşturulamaz.');
          }
        }
        idx = lower.lastIndexOf('/', idx - 1);
      }
      // Hedef bir klasörse (altında dosya varsa) üzerine yazılamaz
      final asDir = '$lower/';
      if (existing.any((p) => p.startsWith(asDir))) {
        throw GitHubApiException(0, 'Hedef bir klasör: $to');
      }
      moves.add(RepoMove(
        from: from,
        to: to,
        sha: src['sha'] as String,
        mode: (src['mode'] as String?) ?? '100644',
      ));
    }
    return moves;
  }

  Future<String> applyMoves({
    required String token,
    required List<RepoMove> moves,
    required String message,
    String? authorName,
    String? authorEmail,
  }) async {
    final repo = _requireRepo();
    final sha = await _gitHubService.movePathsInOneCommit(
      token: token,
      owner: repo.owner,
      repo: repo.name,
      branch: _selectedBranch!,
      message: message,
      moves: moves,
      authorName: authorName,
      authorEmail: authorEmail,
    );
    await refreshTree(token);
    return sha;
  }

  /// Dosya oluşturur / günceller (tek commit) ve ağacı yeniler.
  Future<String> saveFile({
    required String token,
    required String path,
    required Uint8List bytes,
    required String message,
    String? mode,
    String? authorName,
    String? authorEmail,
  }) async {
    final repo = _requireRepo();
    final sha = await _gitHubService.commitFileContent(
      token: token,
      owner: repo.owner,
      repo: repo.name,
      branch: _selectedBranch!,
      path: path,
      bytes: bytes,
      message: message,
      mode: mode,
      authorName: authorName,
      authorEmail: authorEmail,
    );
    await refreshTree(token);
    return sha;
  }

  /// Yeni dosya yolu için çakışma denetimi (büyük/küçük harf duyarsız).
  /// Sorun varsa açıklama, yoksa null döner.
  String? newFilePathProblem(String rawPath) {
    final v = normalizeAndValidateGitPath(rawPath);
    if (!v.isValid) return v.error ?? 'Geçersiz yol.';
    final index = _treeIndex;
    if (index == null) return 'Depo ağacı yüklenmedi; yenileyin.';
    final lower = v.normalizedPath.toLowerCase();
    for (final n in index.nodes.values) {
      final p = n.path.toLowerCase();
      if (p == lower) return 'Bu yolda zaten bir öğe var.';
      if (p.startsWith('$lower/')) return 'Bu yol bir klasör.';
    }
    final fileParent = index.findFileAncestor(v.normalizedPath);
    if (fileParent != null) return '"$fileParent" bir dosya; altında oluşturulamaz.';
    return null;
  }

  Future<List<PathCommitInfo>> loadCommits(String token, {String? path, int page = 1}) {
    final repo = _requireRepo();
    return _gitHubService.getCommits(token, repo.owner, repo.name, _selectedBranch!, path: path, page: page);
  }

  /// Dalı siler. Varsayılan dal silinemez; silinen dal seçiliyse varsayılana geçilir.
  Future<void> deleteBranch(String token, String branch) async {
    final repo = _requireRepo();
    if (branch == repo.defaultBranch) {
      throw GitHubApiException(0, 'Varsayılan dal silinemez.');
    }
    await _gitHubService.deleteBranch(token, repo.owner, repo.name, branch);
    if (_selectedBranch == branch) {
      await selectBranch(token, repo.defaultBranch);
    } else {
      await loadBranches(token, repo);
    }
  }

  /// Oturum kapatılınca tüm repo durumunu temizler.
  void reset() {
    _selectionEpoch++;
    _repositories = [];
    _branches = [];
    _selectedRepo = null;
    _selectedBranch = null;
    _errorMessage = null;
    _isLoading = false;
    _clearTree();
    notifyListeners();
  }
}
