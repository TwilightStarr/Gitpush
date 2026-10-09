// =============================================================================
// GITPUSH - TEK DOSYA BİRLEŞİK FLUTTER UYGULAMASI (main.dart)
// =============================================================================
// BU DOSYA OTOMATİK ÜRETİLİR: `node tool/generate_unified_dart.mjs`
// Kaynak gerçek lib/ klasörüdür; burada yapılan elle değişiklikler kaybolur.
// Tüm modeller, servisler, sağlayıcılar, bileşenler ve ekranlar tek kütüphanede
// birleştirilmiştir (66 dosya).
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, SocketException, HandshakeException;
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show FlutterView;
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// =============================================================================
// 1. MODELLER (MODELS)
// =============================================================================

// --- lib/models/action_run.dart ---
class ActionRun {
  final int id;
  final String name;
  final String headBranch;
  final String headSha;
  final String status;      // queued, in_progress, waiting, pending, completed
  final String? conclusion; // success, failure, cancelled, timed_out, startup_failure
  final String event;
  final String htmlUrl;
  final DateTime createdAt;
  final String commitMessage;

  ActionRun({
    required this.id,
    required this.name,
    required this.headBranch,
    required this.headSha,
    required this.status,
    this.conclusion,
    required this.event,
    required this.htmlUrl,
    required this.createdAt,
    required this.commitMessage,
  });

  factory ActionRun.fromJson(Map<String, dynamic> json) {
    final commit = json['head_commit'] as Map<String, dynamic>?;
    return ActionRun(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Workflow',
      headBranch: json['head_branch'] as String? ?? 'main',
      headSha: json['head_sha'] as String? ?? '',
      status: json['status'] as String? ?? 'queued',
      conclusion: json['conclusion'] as String?,
      event: json['event'] as String? ?? 'push',
      htmlUrl: json['html_url'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      commitMessage: commit?['message'] as String? ?? 'No commit message',
    );
  }

  bool get isCompleted => status == 'completed';
  bool get isSuccess => conclusion == 'success';
  bool get isFailed => conclusion == 'failure';
  bool get isCancelled => conclusion == 'cancelled';
  bool get isTimedOut => conclusion == 'timed_out';
  bool get isStartupFailure => conclusion == 'startup_failure';

  /// Tamamlanmamış her durum (in_progress, queued, waiting, pending...) "sürüyor".
  bool get isRunning => !isCompleted;
  bool get isQueued =>
      status == 'queued' || status == 'waiting' || status == 'pending' || status == 'requested';

  /// Türkçe durum etiketi.
  String get statusLabel {
    if (!isCompleted) return isQueued ? 'Sırada' : 'Çalışıyor';
    if (isSuccess) return 'Başarılı';
    if (isFailed) return 'Başarısız';
    if (isCancelled) return 'İptal edildi';
    if (isTimedOut) return 'Zaman aşımı';
    if (isStartupFailure) return 'Başlatılamadı';
    if (conclusion == 'skipped') return 'Atlandı';
    return conclusion ?? 'Tamamlandı';
  }
}

// --- lib/models/app_settings.dart ---
/// Repo tarayıcıdaki sıralama ölçütü. Klasörler HER ZAMAN dosyalardan önce
/// gelir; bu ayar yalnızca her grubun kendi içindeki sırayı belirler.
enum RepoSortMode { nameAsc, nameDesc, sizeDesc, extension }

extension RepoSortModeLabel on RepoSortMode {
  String get label {
    switch (this) {
      case RepoSortMode.nameAsc:
        return 'Ad (A → Z)';
      case RepoSortMode.nameDesc:
        return 'Ad (Z → A)';
      case RepoSortMode.sizeDesc:
        return 'Boyut (büyükten küçüğe)';
      case RepoSortMode.extension:
        return 'Dosya türü';
    }
  }
}

/// Depo listesindeki (Repo & Dal Seçimi) sıralama.
enum RepoListSort { recent, name, privateFirst }

extension RepoListSortLabel on RepoListSort {
  String get label {
    switch (this) {
      case RepoListSort.recent:
        return 'Son güncellenen';
      case RepoListSort.name:
        return 'Ada göre';
      case RepoListSort.privateFirst:
        return 'Özel depolar önce';
    }
  }
}

/// Uygulama tercihleri. Tek bir JSON olarak SharedPreferences'a yazılır;
/// bilinmeyen / bozuk alanlar güvenli varsayılana döner (sürümler arası uyum).
///
/// Gizli veriler (token, PIN karması) BURADA tutulmaz; onlar
/// `flutter_secure_storage` içindedir.
class AppSettings {
  /// Vurgu rengi paletindeki sıra ([AppSettings.accentPalette]).
  final int accentIndex;

  /// Koyu temada saf siyah zemin (AMOLED ekranlarda pil tasarrufu).
  final bool amoledDark;

  /// Gönderimlerde varsayılan commit mesajı. Boşsa ekranların kendi metni.
  final String defaultCommitMessage;

  /// Dokunma / başarı geri bildirimi (titreşim).
  final bool haptics;

  final RepoSortMode repoSort;
  final bool showHiddenFiles;

  /// Depo seçici sıralaması.
  final RepoListSort repoListSort;

  /// Son seçilen repo/dalı hatırla.
  final bool rememberLastRepo;

  /// Dosya önizlemesi için azami boyut (KB). Bunun üstündeki dosyalar
  /// indirilmez.
  final int previewMaxKb;
  final bool previewWrapLines;
  final double previewFontSize;

  /// Yerel gönderim geçmişinde tutulacak azami kayıt.
  final int historyLimit;

  /// Uygulama kilidi (PIN) kapalıyken de saklanır; PIN karması ayrı yerde.
  final bool appLockEnabled;

  /// Arka plandan dönüşte kilidin devreye girmesi için gereken süre (sn).
  /// 0 = her seferinde.
  final int lockTimeoutSeconds;

  /// Bu kadar gün hiç açılmazsa oturum (token) kendiliğinden kapatılır.
  /// 0 = kapalı.
  final int autoLogoutDays;

  const AppSettings({
    this.accentIndex = 0,
    this.amoledDark = false,
    this.defaultCommitMessage = '',
    this.haptics = true,
    this.repoSort = RepoSortMode.nameAsc,
    this.showHiddenFiles = true,
    this.repoListSort = RepoListSort.recent,
    this.rememberLastRepo = true,
    this.previewMaxKb = 512,
    this.previewWrapLines = false,
    this.previewFontSize = 12,
    this.historyLimit = 50,
    this.appLockEnabled = false,
    this.lockTimeoutSeconds = 30,
    this.autoLogoutDays = 0,
  });

  /// Seçilebilir azami değerler (ayar ekranı bu listelerden seçtirir).
  static const List<int> previewMaxKbOptions = [128, 512, 1024, 2048];
  static const List<int> historyLimitOptions = [25, 50, 100, 200];
  static const List<int> lockTimeoutOptions = [0, 30, 60, 300];
  static const List<int> autoLogoutOptions = [0, 7, 30, 90];

  /// Vurgu renkleri (ARGB). İlk renk marka rengidir.
  static const List<int> accentPalette = [
    0xFF5B6CFF, // İndigo (marka)
    0xFF00B8A9, // Turkuaz
    0xFF2EA043, // Yeşil
    0xFFE8A200, // Kehribar
    0xFFE5484D, // Mercan
    0xFFB455F0, // Mor
  ];

  static const List<String> accentNames = [
    'İndigo',
    'Turkuaz',
    'Yeşil',
    'Kehribar',
    'Mercan',
    'Mor',
  ];

  int get accentColorValue => accentPalette[_clampIndex(accentIndex)];

  static int _clampIndex(int i) => i < 0 || i >= accentPalette.length ? 0 : i;

  AppSettings copyWith({
    int? accentIndex,
    bool? amoledDark,
    String? defaultCommitMessage,
    bool? haptics,
    RepoSortMode? repoSort,
    bool? showHiddenFiles,
    RepoListSort? repoListSort,
    bool? rememberLastRepo,
    int? previewMaxKb,
    bool? previewWrapLines,
    double? previewFontSize,
    int? historyLimit,
    bool? appLockEnabled,
    int? lockTimeoutSeconds,
    int? autoLogoutDays,
  }) {
    return AppSettings(
      accentIndex: accentIndex ?? this.accentIndex,
      amoledDark: amoledDark ?? this.amoledDark,
      defaultCommitMessage: defaultCommitMessage ?? this.defaultCommitMessage,
      haptics: haptics ?? this.haptics,
      repoSort: repoSort ?? this.repoSort,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      repoListSort: repoListSort ?? this.repoListSort,
      rememberLastRepo: rememberLastRepo ?? this.rememberLastRepo,
      previewMaxKb: previewMaxKb ?? this.previewMaxKb,
      previewWrapLines: previewWrapLines ?? this.previewWrapLines,
      previewFontSize: previewFontSize ?? this.previewFontSize,
      historyLimit: historyLimit ?? this.historyLimit,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      lockTimeoutSeconds: lockTimeoutSeconds ?? this.lockTimeoutSeconds,
      autoLogoutDays: autoLogoutDays ?? this.autoLogoutDays,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'accentIndex': accentIndex,
        'amoledDark': amoledDark,
        'defaultCommitMessage': defaultCommitMessage,
        'haptics': haptics,
        'repoSort': repoSort.name,
        'showHiddenFiles': showHiddenFiles,
        'repoListSort': repoListSort.name,
        'rememberLastRepo': rememberLastRepo,
        'previewMaxKb': previewMaxKb,
        'previewWrapLines': previewWrapLines,
        'previewFontSize': previewFontSize,
        'historyLimit': historyLimit,
        'appLockEnabled': appLockEnabled,
        'lockTimeoutSeconds': lockTimeoutSeconds,
        'autoLogoutDays': autoLogoutDays,
      };

  String toJson() => jsonEncode(toMap());

  /// Bozuk / eksik / beklenmeyen tipte veriye karşı dayanıklıdır.
  factory AppSettings.fromJson(String? source) {
    if (source == null || source.isEmpty) return const AppSettings();
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return const AppSettings();
      return AppSettings.fromMap(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const AppSettings();
    }
  }

  factory AppSettings.fromMap(Map<String, dynamic> m) {
    const d = AppSettings();

    bool b(String k, bool def) => m[k] is bool ? m[k] as bool : def;
    int i(String k, int def) => m[k] is num ? (m[k] as num).toInt() : def;
    int pick(String k, List<int> allowed, int def) {
      final v = i(k, def);
      return allowed.contains(v) ? v : def;
    }

    T enumOf<T extends Enum>(String k, List<T> values, T def) {
      final raw = m[k];
      if (raw is! String) return def;
      for (final v in values) {
        if (v.name == raw) return v;
      }
      return def;
    }

    final fs = m['previewFontSize'] is num ? (m['previewFontSize'] as num).toDouble() : d.previewFontSize;
    final commit = m['defaultCommitMessage'];

    return AppSettings(
      accentIndex: _clampIndex(i('accentIndex', d.accentIndex)),
      amoledDark: b('amoledDark', d.amoledDark),
      defaultCommitMessage: commit is String ? commit.trim() : d.defaultCommitMessage,
      haptics: b('haptics', d.haptics),
      repoSort: enumOf('repoSort', RepoSortMode.values, d.repoSort),
      showHiddenFiles: b('showHiddenFiles', d.showHiddenFiles),
      repoListSort: enumOf('repoListSort', RepoListSort.values, d.repoListSort),
      rememberLastRepo: b('rememberLastRepo', d.rememberLastRepo),
      previewMaxKb: pick('previewMaxKb', previewMaxKbOptions, d.previewMaxKb),
      previewWrapLines: b('previewWrapLines', d.previewWrapLines),
      previewFontSize: fs.clamp(10.0, 18.0).toDouble(),
      historyLimit: pick('historyLimit', historyLimitOptions, d.historyLimit),
      appLockEnabled: b('appLockEnabled', d.appLockEnabled),
      lockTimeoutSeconds: pick('lockTimeoutSeconds', lockTimeoutOptions, d.lockTimeoutSeconds),
      autoLogoutDays: pick('autoLogoutDays', autoLogoutOptions, d.autoLogoutDays),
    );
  }
}

// --- lib/models/git_file.dart ---
enum GitFileStatus {
  isNew,       // Repoda yok (Yeni)
  update,      // Repoda var, içerik farklı (Güncelleme)
  delete,      // Silinecek (yalnızca açıkça onaylanırsa)
  newFolder,   // Yeni klasör oluşturulacak
  unchanged,   // Değişmedi (yerel sha == uzak sha)
  conflict,    // Çakışma / geçersiz yol: push engellenir
}

class GitFileItem {
  static int _nextId = 1;

  /// Kart/anahtar kimliği; kopyalarda aynı kalır.
  final int id;
  final String localPath;

  /// Seçilen dosyanın özgün adı (hedef yol değişse de sabit).
  final String sourceName;

  /// Kullanıcının yazdığı / atanan hedef yol (ham; normalleştirme ayrıdır).
  String repoPath;
  final int size;
  final Uint8List? bytes;
  bool isSelected;
  GitFileStatus status;

  /// Durum, repo ağacıyla karşılaştırılarak hesaplandı mı?
  bool statusKnown;
  String? computedSha;
  String? remoteSha;
  String? remoteMode;
  String? conflictMessage;

  /// Repoda birden fazla eşleşme var; kullanıcı seçim yapmalı.
  bool needsChoice;

  /// Yol kullanıcı tarafından elle belirlendi (yazma, klasör seçici, kısayol,
  /// komut). true ise otomatik eşleştirme yolu değiştirmez.
  bool pathManual;
  List<String> suggestions;

  GitFileItem({
    int? id,
    required this.localPath,
    required this.repoPath,
    required this.size,
    this.bytes,
    String? sourceName,
    this.isSelected = true,
    this.status = GitFileStatus.isNew,
    this.statusKnown = false,
    this.computedSha,
    this.remoteSha,
    this.remoteMode,
    this.conflictMessage,
    this.needsChoice = false,
    this.pathManual = false,
    List<String>? suggestions,
  })  : id = id ?? _nextId++,
        sourceName = sourceName ?? _lastSegment(localPath),
        suggestions = suggestions ?? [];

  /// Silinecek bir repo dosyası (yalnızca açık onayla push edilir).
  factory GitFileItem.deletion(String path) {
    return GitFileItem(
      localPath: path,
      repoPath: path,
      size: 0,
      status: GitFileStatus.delete,
      statusKnown: true,
    );
  }

  static String _lastSegment(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx == -1 ? normalized : normalized.substring(idx + 1);
  }

  GitFileItem copyWith({
    String? repoPath,
    bool? isSelected,
    GitFileStatus? status,
  }) {
    return GitFileItem(
      id: id,
      localPath: localPath,
      repoPath: repoPath ?? this.repoPath,
      size: size,
      bytes: bytes,
      sourceName: sourceName,
      isSelected: isSelected ?? this.isSelected,
      status: status ?? this.status,
      statusKnown: statusKnown,
      computedSha: computedSha,
      remoteSha: remoteSha,
      remoteMode: remoteMode,
      conflictMessage: conflictMessage,
      needsChoice: needsChoice,
      pathManual: pathManual,
      suggestions: List<String>.from(suggestions),
    );
  }

  /// Dosyanın özgün adı.
  String get fileName => sourceName;

  /// Push'ta kullanılacak hedef yol (ham). Yol `/` ile bitiyorsa dosya adı
  /// otomatik eklenir.
  String get targetPath => appendFileNameIfFolder(repoPath, sourceName);

  String get directoryPath {
    final idx = repoPath.lastIndexOf('/');
    if (idx == -1) return '';
    return repoPath.substring(0, idx + 1);
  }

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// --- lib/models/history_item.dart ---
class HistoryItem {
  final String id;
  final String repoFullName;
  final String branch;
  final String commitMessage;
  final String commitSha;
  final int filesCount;
  final DateTime timestamp;
  final String commitUrl;

  HistoryItem({
    required this.id,
    required this.repoFullName,
    required this.branch,
    required this.commitMessage,
    required this.commitSha,
    required this.filesCount,
    required this.timestamp,
    required this.commitUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'repoFullName': repoFullName,
      'branch': branch,
      'commitMessage': commitMessage,
      'commitSha': commitSha,
      'filesCount': filesCount,
      'timestamp': timestamp.toIso8601String(),
      'commitUrl': commitUrl,
    };
  }

  factory HistoryItem.fromMap(Map<String, dynamic> map) {
    return HistoryItem(
      id: map['id'] as String,
      repoFullName: map['repoFullName'] as String,
      branch: map['branch'] as String,
      commitMessage: map['commitMessage'] as String,
      commitSha: map['commitSha'] as String,
      filesCount: map['filesCount'] as int,
      timestamp: DateTime.parse(map['timestamp'] as String),
      commitUrl: map['commitUrl'] as String,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory HistoryItem.fromJson(String source) => HistoryItem.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

// --- lib/models/path_commit_info.dart ---
/// Bir dosya/klasörü en son değiştiren commit'in özeti.
class PathCommitInfo {
  final String sha;
  final String message;
  final String? authorName;
  final DateTime? date;
  final String? htmlUrl;

  const PathCommitInfo({
    required this.sha,
    required this.message,
    this.authorName,
    this.date,
    this.htmlUrl,
  });

  /// Commit mesajının ilk satırı.
  String get title {
    final i = message.indexOf('\n');
    return (i == -1 ? message : message.substring(0, i)).trim();
  }

  factory PathCommitInfo.fromJson(Map<String, dynamic> json) {
    final commit = json['commit'] is Map ? Map<String, dynamic>.from(json['commit'] as Map) : <String, dynamic>{};
    final author = commit['author'] is Map ? Map<String, dynamic>.from(commit['author'] as Map) : <String, dynamic>{};
    final url = json['html_url'];
    return PathCommitInfo(
      sha: (json['sha'] as String?) ?? '',
      message: (commit['message'] as String?) ?? '',
      authorName: author['name'] as String?,
      date: author['date'] is String ? DateTime.tryParse(author['date'] as String) : null,
      htmlUrl: url is String ? url : null,
    );
  }
}

/// Dosya/klasör taşıma-yeniden adlandırma için tek bir blob eşlemesi.
class RepoMove {
  final String from;
  final String to;
  final String sha;
  final String mode;

  const RepoMove({required this.from, required this.to, required this.sha, this.mode = '100644'});
}

/// GitHub API (core) istek kotası.
class RateLimitInfo {
  final int limit;
  final int remaining;
  final DateTime? resetAt;

  const RateLimitInfo({required this.limit, required this.remaining, this.resetAt});

  int get used => limit - remaining;

  factory RateLimitInfo.fromJson(Map<String, dynamic> json) {
    final resources = json['resources'];
    final core = resources is Map && resources['core'] is Map
        ? Map<String, dynamic>.from(resources['core'] as Map)
        : <String, dynamic>{};
    final reset = core['reset'];
    return RateLimitInfo(
      limit: (core['limit'] as num?)?.toInt() ?? 0,
      remaining: (core['remaining'] as num?)?.toInt() ?? 0,
      resetAt: reset is num ? DateTime.fromMillisecondsSinceEpoch(reset.toInt() * 1000) : null,
    );
  }
}

// --- lib/models/push_result.dart ---
/// `executeAtomicPush` sonucu. Sayaçlar dosya durumundan değil, gerçekten
/// push edilenlerden hesaplanır.
class PushResult {
  final String? commitSha;
  final int added;
  final int updated;
  final int deleted;
  final int skipped;
  final bool noChanges;
  final List<String> warnings;

  const PushResult({
    this.commitSha,
    this.added = 0,
    this.updated = 0,
    this.deleted = 0,
    this.skipped = 0,
    this.noChanges = false,
    this.warnings = const <String>[],
  });

  int get changedCount => added + updated + deleted;
}

// --- lib/models/repo.dart ---
class GitHubRepo {
  final int id;
  final String name;
  final String fullName;
  final String owner;
  final bool isPrivate;
  final String defaultBranch;
  final String? description;
  final DateTime? updatedAt;
  final bool isEmpty;

  GitHubRepo({
    required this.id,
    required this.name,
    required this.fullName,
    required this.owner,
    required this.isPrivate,
    required this.defaultBranch,
    this.description,
    this.updatedAt,
    this.isEmpty = false,
  });

  factory GitHubRepo.fromJson(Map<String, dynamic> json) {
    return GitHubRepo(
      id: json['id'] as int,
      name: json['name'] as String,
      fullName: json['full_name'] as String,
      owner: (json['owner'] as Map<String, dynamic>)['login'] as String,
      isPrivate: json['private'] as bool? ?? false,
      defaultBranch: json['default_branch'] as String? ?? 'main',
      description: json['description'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      isEmpty: json['size'] == 0,
    );
  }
}

class GitHubBranch {
  final String name;
  final String commitSha;

  GitHubBranch({
    required this.name,
    required this.commitSha,
  });

  factory GitHubBranch.fromJson(Map<String, dynamic> json) {
    final commit = json['commit'] as Map<String, dynamic>;
    return GitHubBranch(
      name: json['name'] as String,
      commitSha: commit['sha'] as String,
    );
  }
}

// --- lib/models/repo_listing.dart ---
/// Repo tarayıcıdaki tek satır: dosya, klasör veya alt modül.
class RepoEntry {
  final String name;
  final String path;
  final bool isDir;
  final bool isSubmodule;

  /// Dosyada kendi boyutu, klasörde altındaki tüm dosyaların toplamı (bayt).
  final int size;

  /// Yalnızca klasörler için: altındaki (iç içe dahil) dosya / klasör sayısı.
  final int fileCount;
  final int folderCount;

  final String? sha;
  final String? mode;

  const RepoEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.isSubmodule = false,
    this.size = 0,
    this.fileCount = 0,
    this.folderCount = 0,
    this.sha,
    this.mode,
  });

  bool get isHidden => name.startsWith('.');

  /// Küçük harfli uzantı (nokta yok). Uzantısız ve `.gitignore` gibi
  /// nokta-ile-başlayan adlar için boş döner.
  String get extension {
    if (isDir) return '';
    final i = name.lastIndexOf('.');
    if (i <= 0 || i == name.length - 1) return '';
    return name.substring(i + 1).toLowerCase();
  }
}

/// Yol çubuğundaki (breadcrumb) bir basamak.
class RepoCrumb {
  final String label;
  final String path;

  const RepoCrumb(this.label, this.path);
}

/// `lib/screens` -> [Kök, lib, lib/screens].
List<RepoCrumb> breadcrumbsFor(String dir, {String rootLabel = 'Kök'}) {
  final crumbs = <RepoCrumb>[RepoCrumb(rootLabel, '')];
  if (dir.isEmpty) return crumbs;
  var acc = '';
  for (final seg in dir.split('/')) {
    if (seg.isEmpty) continue;
    acc = acc.isEmpty ? seg : '$acc/$seg';
    crumbs.add(RepoCrumb(seg, acc));
  }
  return crumbs;
}

/// "file10" > "file2" doğru sıralansın diye sayı kısımlarını sayısal
/// karşılaştıran, harf büyüklüğünü yok sayan doğal sıralama.
int compareNatural(String a, String b) {
  final x = a.toLowerCase();
  final y = b.toLowerCase();
  var i = 0;
  var j = 0;
  while (i < x.length && j < y.length) {
    final cx = x.codeUnitAt(i);
    final cy = y.codeUnitAt(j);
    final dx = cx >= 48 && cx <= 57;
    final dy = cy >= 48 && cy <= 57;
    if (dx && dy) {
      var ei = i;
      while (ei < x.length && x.codeUnitAt(ei) >= 48 && x.codeUnitAt(ei) <= 57) {
        ei++;
      }
      var ej = j;
      while (ej < y.length && y.codeUnitAt(ej) >= 48 && y.codeUnitAt(ej) <= 57) {
        ej++;
      }
      final nx = x.substring(i, ei).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final ny = y.substring(j, ej).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (nx.length != ny.length) return nx.length.compareTo(ny.length);
      final c = nx.compareTo(ny);
      if (c != 0) return c;
      i = ei;
      j = ej;
    } else {
      if (cx != cy) return cx.compareTo(cy);
      i++;
      j++;
    }
  }
  return (x.length - i).compareTo(y.length - j);
}

class _FolderAgg {
  String? sha;
  int files = 0;
  int folders = 0;
  int size = 0;
}

int _sizeOf(Map<String, dynamic> e) {
  final s = e['size'];
  return s is num ? s.toInt() : 0;
}

String? _typeOf(Map<String, dynamic> e) => e['type'] is String ? e['type'] as String : null;

/// [dir] klasörünün DOĞRUDAN çocuklarını döndürür. Klasörler her zaman
/// dosyalardan önce gelir; her grubun içi [sort] ölçütüne göre sıralanır.
List<RepoEntry> buildDirectoryListing(
  List<Map<String, dynamic>> tree,
  String dir, {
  RepoSortMode sort = RepoSortMode.nameAsc,
  bool showHidden = true,
}) {
  final prefix = dir.isEmpty ? '' : '$dir/';
  final folders = <String, _FolderAgg>{};
  final files = <RepoEntry>[];

  for (final e in tree) {
    final path = e['path'];
    if (path is! String) continue;
    if (prefix.isNotEmpty && !path.startsWith(prefix)) continue;
    final rel = path.substring(prefix.length);
    if (rel.isEmpty) continue;
    final type = _typeOf(e);
    final slash = rel.indexOf('/');

    if (slash == -1) {
      // Doğrudan çocuk
      if (type == 'tree') {
        folders.putIfAbsent(rel, _FolderAgg.new).sha = e['sha'] as String?;
      } else {
        files.add(RepoEntry(
          name: rel,
          path: path,
          isDir: false,
          isSubmodule: type == 'commit',
          size: _sizeOf(e),
          sha: e['sha'] as String?,
          mode: e['mode'] as String?,
        ));
      }
    } else {
      // Alt klasörün torunu: üst klasörün toplamlarına ekle
      final top = rel.substring(0, slash);
      final agg = folders.putIfAbsent(top, _FolderAgg.new);
      if (type == 'tree') {
        agg.folders++;
      } else {
        agg.files++;
        agg.size += _sizeOf(e);
      }
    }
  }

  final dirs = folders.entries
      .map((f) => RepoEntry(
            name: f.key,
            path: prefix + f.key,
            isDir: true,
            size: f.value.size,
            fileCount: f.value.files,
            folderCount: f.value.folders,
            sha: f.value.sha,
          ))
      .toList();

  bool keep(RepoEntry e) => showHidden || !e.isHidden;
  final visibleDirs = dirs.where(keep).toList();
  final visibleFiles = files.where(keep).toList();

  int byName(RepoEntry a, RepoEntry b) => compareNatural(a.name, b.name);

  switch (sort) {
    case RepoSortMode.nameAsc:
      visibleDirs.sort(byName);
      visibleFiles.sort(byName);
      break;
    case RepoSortMode.nameDesc:
      visibleDirs.sort((a, b) => byName(b, a));
      visibleFiles.sort((a, b) => byName(b, a));
      break;
    case RepoSortMode.sizeDesc:
      int bySize(RepoEntry a, RepoEntry b) {
        final c = b.size.compareTo(a.size);
        return c != 0 ? c : byName(a, b);
      }
      visibleDirs.sort(bySize);
      visibleFiles.sort(bySize);
      break;
    case RepoSortMode.extension:
      visibleDirs.sort(byName);
      visibleFiles.sort((a, b) {
        final c = a.extension.compareTo(b.extension);
        return c != 0 ? c : byName(a, b);
      });
      break;
  }

  return <RepoEntry>[...visibleDirs, ...visibleFiles];
}

/// Tüm ağaçta yol araması (büyük/küçük harf duyarsız). Klasörler önce, sonra
/// ada göre başlayan eşleşmeler, sonra yola göre.
List<RepoEntry> searchRepoTree(
  List<Map<String, dynamic>> tree,
  String query, {
  bool showHidden = true,
  int limit = 300,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const <RepoEntry>[];

  final out = <RepoEntry>[];
  for (final e in tree) {
    final path = e['path'];
    if (path is! String) continue;
    if (!path.toLowerCase().contains(q)) continue;
    if (!showHidden && path.split('/').any((s) => s.startsWith('.'))) continue;
    final type = _typeOf(e);
    final name = path.substring(path.lastIndexOf('/') + 1);
    out.add(RepoEntry(
      name: name,
      path: path,
      isDir: type == 'tree',
      isSubmodule: type == 'commit',
      size: _sizeOf(e),
      sha: e['sha'] as String?,
      mode: e['mode'] as String?,
    ));
  }

  int rank(RepoEntry e) {
    final n = e.name.toLowerCase();
    if (n == q) return 0;
    if (n.startsWith(q)) return 1;
    if (n.contains(q)) return 2;
    return 3;
  }

  out.sort((a, b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    return compareNatural(a.path, b.path);
  });
  return out.length > limit ? out.sublist(0, limit) : out;
}

/// [dir] altındaki (iç içe) TÜM blob girdileri; klasör silme / taşıma için.
List<Map<String, dynamic>> blobsUnder(List<Map<String, dynamic>> tree, String dir) {
  final prefix = '$dir/';
  return tree
      .where((e) => e['path'] is String && (e['path'] as String).startsWith(prefix) && _typeOf(e) == 'blob')
      .toList();
}

/// Dosya adından önizleme türü.
enum PreviewKind { text, image, binary }

const Set<String> _imageExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
const Set<String> _binaryExts = {
  'zip', 'gz', 'tgz', 'rar', '7z', 'jar', 'aar', 'apk', 'aab', 'so', 'dll', 'exe', 'bin', 'class', 'dex',
  'pdf', 'mp3', 'mp4', 'mov', 'avi', 'mkv', 'wav', 'ogg', 'ttf', 'otf', 'woff', 'woff2', 'ico', 'keystore', 'jks',
  'psd', 'sketch', 'db', 'sqlite', 'o', 'a',
};

PreviewKind previewKindFor(String fileName) {
  final i = fileName.lastIndexOf('.');
  final ext = i <= 0 ? '' : fileName.substring(i + 1).toLowerCase();
  if (_imageExts.contains(ext)) return PreviewKind.image;
  if (_binaryExts.contains(ext)) return PreviewKind.binary;
  return PreviewKind.text;
}

// --- lib/models/repo_tree.dart ---
/// Repo ağacındaki tek bir düğüm (dosya veya klasör).
class RepoNode {
  final String path;
  final String type; // blob | tree | commit
  final String? sha;
  final String? mode;

  const RepoNode({
    required this.path,
    required this.type,
    this.sha,
    this.mode,
  });

  bool get isTree => type == 'tree';
  bool get isBlob => type == 'blob';
}

/// `getRecursiveTree` sonucu: düğümler + ağacın GitHub tarafından kesilip
/// kesilmediği.
class RepoTreeResult {
  final List<Map<String, dynamic>> entries;
  final bool truncated;

  const RepoTreeResult({required this.entries, this.truncated = false});

  const RepoTreeResult.empty()
      : entries = const <Map<String, dynamic>>[],
        truncated = false;
}

/// `path -> düğüm` haritası. Sınıflandırma ve çakışma denetimleri bunu kullanır.
class RepoTreeIndex {
  final Map<String, RepoNode> nodes;

  const RepoTreeIndex(this.nodes);

  factory RepoTreeIndex.fromEntries(List<Map<String, dynamic>> entries) {
    final map = <String, RepoNode>{};
    for (final e in entries) {
      final path = e['path'];
      if (path is! String) continue;
      map[path] = RepoNode(
        path: path,
        type: (e['type'] as String?) ?? 'blob',
        sha: e['sha'] as String?,
        mode: e['mode'] as String?,
      );
    }
    return RepoTreeIndex(map);
  }

  /// Klasör olmayan (blob / alt modül) tüm yollar.
  Iterable<String> get nonTreePaths =>
      nodes.values.where((n) => !n.isTree).map((n) => n.path);

  /// Verilen dosya adıyla eşleşen blob yolları.
  ///
  /// Önce TAM ad eşleşmesi aranır. Bulunamazsa büyük/küçük harf farkı ve
  /// tarayıcı/telefonun eklediği kopya son eki (`main (1).dart`) yok sayılarak
  /// aranır.
  List<String> findBlobsByName(String name) {
    final exact = nodes.values
        .where((n) => n.isBlob && (n.path == name || n.path.endsWith('/$name')))
        .map((n) => n.path)
        .toList();
    if (exact.isNotEmpty) {
      exact.sort();
      return exact;
    }

    final key = _nameKey(name);
    final loose = nodes.values
        .where((n) => n.isBlob && _nameKey(_lastSegment(n.path)) == key)
        .map((n) => n.path)
        .toList();
    loose.sort();
    return loose;
  }

  static final RegExp _dupSuffix = RegExp(r'\s*\(\d+\)(?=(\.[^./]+)?$)');

  static String _lastSegment(String path) {
    final i = path.lastIndexOf('/');
    return i == -1 ? path : path.substring(i + 1);
  }

  static String _nameKey(String name) =>
      name.toLowerCase().replaceAll(_dupSuffix, '');

  static final Expando<Map<String, List<String>>> _lowerCache =
      Expando<Map<String, List<String>>>();

  /// küçük harfli yol -> gerçek blob yolları (büyük/küçük harf duyarsız arama).
  Map<String, List<String>> get _lowerBlobs {
    final cached = _lowerCache[this];
    if (cached != null) return cached;
    final map = <String, List<String>>{};
    for (final n in nodes.values) {
      if (n.isBlob) {
        map.putIfAbsent(n.path.toLowerCase(), () => <String>[]).add(n.path);
      }
    }
    _lowerCache[this] = map;
    return map;
  }

  /// Yol repoda blob olarak varsa (birebir ya da yalnızca harf büyüklüğü
  /// farkıyla TEK eşleşme) gerçek repo yolunu döndürür; yoksa null.
  String? uniqueBlobIgnoreCase(String path) {
    final exact = nodes[path];
    if (exact != null && exact.isBlob) return path;
    final list = _lowerBlobs[path.toLowerCase()];
    if (list != null && list.length == 1) return list.first;
    return null;
  }

  /// Yolun herhangi bir üst segmenti repoda klasör DEĞİLSE (dosya/alt modül)
  /// o üst yolu döndürür; yoksa null.
  String? findFileAncestor(String path) {
    var idx = path.lastIndexOf('/');
    while (idx > 0) {
      final parent = path.substring(0, idx);
      final node = nodes[parent];
      if (node != null && !node.isTree) return parent;
      idx = parent.lastIndexOf('/');
    }
    return null;
  }

  /// Dosyanın hemen üst klasörü repoda var mı? (Kök her zaman vardır.)
  bool hasParentFolder(String path) {
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return true;
    final node = nodes[path.substring(0, idx)];
    return node != null && node.isTree;
  }
}

// =============================================================================
// 2. YARDIMCILAR (UTILS)
// =============================================================================

// --- lib/utils/app_navigator.dart ---
/// Uygulama genelinde tek `Navigator` anahtarı. Bağlamı olmayan yerlerden
/// (ör. kilit ekranından "oturumu sıfırla") rota değiştirmek için kullanılır.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

// --- lib/utils/file_icons.dart ---
/// Bir dosya uzantısı için simge + vurgu rengi.
class FileVisual {
  final IconData icon;
  final Color color;

  const FileVisual(this.icon, this.color);
}

const FileVisual _defaultFile = FileVisual(Icons.insert_drive_file_outlined, Color(0xFF8B93A7));

const Map<String, FileVisual> _byExt = {
  'dart': FileVisual(Icons.flutter_dash, Color(0xFF29B6F6)),
  'kt': FileVisual(Icons.code, Color(0xFFB455F0)),
  'java': FileVisual(Icons.code, Color(0xFFE8A200)),
  'swift': FileVisual(Icons.code, Color(0xFFFF7043)),
  'js': FileVisual(Icons.javascript, Color(0xFFE8C200)),
  'jsx': FileVisual(Icons.javascript, Color(0xFF29B6F6)),
  'ts': FileVisual(Icons.javascript, Color(0xFF3B82F6)),
  'tsx': FileVisual(Icons.javascript, Color(0xFF3B82F6)),
  'py': FileVisual(Icons.code, Color(0xFF3B82F6)),
  'rb': FileVisual(Icons.code, Color(0xFFE5484D)),
  'go': FileVisual(Icons.code, Color(0xFF00B8A9)),
  'rs': FileVisual(Icons.code, Color(0xFFFF7043)),
  'c': FileVisual(Icons.code, Color(0xFF8B93A7)),
  'cpp': FileVisual(Icons.code, Color(0xFF3B82F6)),
  'h': FileVisual(Icons.code, Color(0xFF8B93A7)),
  'json': FileVisual(Icons.data_object, Color(0xFFE8A200)),
  'yaml': FileVisual(Icons.data_object, Color(0xFFE5484D)),
  'yml': FileVisual(Icons.data_object, Color(0xFFE5484D)),
  'toml': FileVisual(Icons.data_object, Color(0xFF8B93A7)),
  'xml': FileVisual(Icons.data_object, Color(0xFFFF7043)),
  'md': FileVisual(Icons.description_outlined, Color(0xFF5B6CFF)),
  'txt': FileVisual(Icons.description_outlined, Color(0xFF8B93A7)),
  'html': FileVisual(Icons.html, Color(0xFFFF7043)),
  'css': FileVisual(Icons.css, Color(0xFF3B82F6)),
  'sh': FileVisual(Icons.terminal, Color(0xFF2EA043)),
  'bat': FileVisual(Icons.terminal, Color(0xFF2EA043)),
  'gradle': FileVisual(Icons.build_outlined, Color(0xFF00B8A9)),
  'kts': FileVisual(Icons.build_outlined, Color(0xFF00B8A9)),
  'png': FileVisual(Icons.image_outlined, Color(0xFFB455F0)),
  'jpg': FileVisual(Icons.image_outlined, Color(0xFFB455F0)),
  'jpeg': FileVisual(Icons.image_outlined, Color(0xFFB455F0)),
  'gif': FileVisual(Icons.image_outlined, Color(0xFFB455F0)),
  'webp': FileVisual(Icons.image_outlined, Color(0xFFB455F0)),
  'svg': FileVisual(Icons.image_outlined, Color(0xFFFF7043)),
  'zip': FileVisual(Icons.inventory_2_outlined, Color(0xFFE8A200)),
  'apk': FileVisual(Icons.android, Color(0xFF2EA043)),
  'pdf': FileVisual(Icons.picture_as_pdf_outlined, Color(0xFFE5484D)),
  'pem': FileVisual(Icons.vpn_key_outlined, Color(0xFFE5484D)),
  'jks': FileVisual(Icons.vpn_key_outlined, Color(0xFFE5484D)),
  'lock': FileVisual(Icons.lock_outline, Color(0xFF8B93A7)),
};

FileVisual fileVisualFor(String extension) => _byExt[extension.toLowerCase()] ?? _defaultFile;

// --- lib/utils/format_utils.dart ---
/// Godot'taki `_format_bytes()` fonksiyonunun Flutter karsiligi.
/// Bayt degerini okunabilir B / KB / MB / GB birimine cevirir.
String formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.toInt()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Bir süreyi "1 sa 24 dk" / "42 dk" / "< 1 dk" biçimine çevirir.
/// Pil kalan-süre tahmini için kullanılır (bkz. `BatteryService`).
String formatDuration(Duration d) {
  final totalMinutes = d.inMinutes;
  if (totalMinutes < 1) return '< 1 dk';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours <= 0) return '$minutes dk';
  if (minutes == 0) return '$hours sa';
  return '$hours sa $minutes dk';
}

/// Commit SHA'sını her ekranda aynı uzunlukta (7 karakter) gösterir.
String shortSha(String sha, {int length = 7}) {
  return sha.length <= length ? sha : sha.substring(0, length);
}

// --- lib/utils/path_validation.dart ---
/// Git yolu doğrulama ve normalleştirme yardımcıları.
///
/// `src/utils/pathValidation.ts` mantığının Dart karşılığıdır.
class PathValidationResult {
  final bool isValid;
  final String? error;
  final String normalizedPath;

  const PathValidationResult({
    required this.isValid,
    this.error,
    required this.normalizedPath,
  });
}

final RegExp _invalidSegmentChars = RegExp(r'[<>:"|?*\x00-\x1F]');
final RegExp _multiSlash = RegExp(r'/+');

/// Yol `/` veya `\` ile bitiyorsa (yani kullanıcı bir klasör yazdıysa) true.
bool endsWithPathSeparator(String raw) {
  final t = raw.trim();
  return t.endsWith('/') || t.endsWith('\\');
}

/// Hedef yol bir klasör gibi bitiyorsa (`lib/`, `/`) dosya adını sonuna ekler.
/// Boş yol olduğu gibi döner (doğrulamada hata olarak yakalanır).
String appendFileNameIfFolder(String raw, String fileName) {
  if (fileName.isEmpty) return raw;
  final t = raw.trim();
  if (t.isEmpty) return raw;
  if (t.endsWith('/') || t.endsWith('\\')) return '$t$fileName';
  return raw;
}

PathValidationResult _invalid(String error, String normalized) {
  return PathValidationResult(
    isValid: false,
    error: error,
    normalizedPath: normalized,
  );
}

/// Yolu normalleştirir (`\` -> `/`, baştaki/sondaki/tekrarlı `/` temizlenir)
/// ve Git için güvenli olup olmadığını denetler.
PathValidationResult normalizeAndValidateGitPath(String rawPath) {
  if (rawPath.trim().isEmpty) {
    return _invalid('Dosya yolu boş olamaz.', '');
  }

  var p = rawPath.trim().replaceAll('\\', '/');
  p = p.replaceAll(_multiSlash, '/');
  while (p.startsWith('/')) {
    p = p.substring(1);
  }
  while (p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }

  if (p.isEmpty) {
    return _invalid('Dosya yolu yalnızca eğik çizgilerden oluşamaz.', '');
  }

  for (final seg in p.split('/')) {
    if (seg == '..') {
      return _invalid('Dosya yolunda ".." (üst dizin yönlendirmesi) kullanılamaz.', p);
    }
    if (seg == '.') {
      return _invalid('Dosya yolunda geçersiz "." segmenti var.', p);
    }
    if (seg.toLowerCase() == '.git') {
      return _invalid('Dosya yolunda ".git" klasörü kullanılamaz.', p);
    }
    if (_invalidSegmentChars.hasMatch(seg)) {
      return _invalid('Dosya adı geçersiz karakterler içeriyor ($seg).', p);
    }
  }

  if (p.length > 400) {
    return _invalid('Dosya yolu 400 karakter sınırını aşıyor.', p);
  }

  return PathValidationResult(isValid: true, normalizedPath: p);
}

/// Büyük/küçük harf duyarsız şekilde mükerrer olan (normalleştirilmiş, küçük
/// harfli) yolları döndürür.
List<String> findDuplicatePaths(List<String> paths) {
  final seen = <String>{};
  final duplicates = <String>{};

  for (final raw in paths) {
    final norm = normalizeAndValidateGitPath(raw).normalizedPath.toLowerCase();
    if (!seen.add(norm)) {
      duplicates.add(norm);
    }
  }
  return duplicates.toList();
}

/// Hedef klasör önekini normalleştirir: boşsa '', değilse `a/b/` biçimi.
/// (Geçerlilik denetimi, öneklenmiş tam yol üzerinde yapılır.)
String normalizeFolderPrefix(String raw) {
  var p = raw.trim().replaceAll('\\', '/');
  p = p.replaceAll(_multiSlash, '/');
  while (p.startsWith('/')) {
    p = p.substring(1);
  }
  while (p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p.isEmpty ? '' : '$p/';
}

// --- lib/utils/repo_actions.dart ---
/// Repo tarayıcı ve dosya detay ekranlarının ortak işlemleri: silme, taşıma /
/// yeniden adlandırma, bağlantı üretme. Hepsi tek commit'tir ve geçmişe yazılır.
class RepoActions {
  RepoActions._();

  static String _enc(String path) => path.split('/').map(Uri.encodeComponent).join('/');

  /// Dosya/klasörün github.com üzerindeki sayfası.
  static String githubUrlFor(GitHubRepo repo, String branch, RepoEntry e) {
    final kind = e.isDir ? 'tree' : 'blob';
    return 'https://github.com/${repo.owner}/${repo.name}/$kind/${_enc(branch)}/${_enc(e.path)}';
  }

  /// Ham içerik adresi (yalnızca kopyalamak için; uygulama içinde açılmaz).
  static String rawUrlFor(GitHubRepo repo, String branch, RepoEntry e) {
    return 'https://raw.githubusercontent.com/${repo.owner}/${repo.name}/${_enc(branch)}/${_enc(e.path)}';
  }

  static Future<void> copy(BuildContext context, String text, String doneMessage) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(doneMessage)));
  }

  static void _showBusy(BuildContext context, String label) {
    // ignore: unawaited_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 18),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }

  static String? _authorName(AuthProvider a) =>
      (a.authorName ?? '').trim().isNotEmpty && (a.authorEmail ?? '').trim().isNotEmpty ? a.authorName : null;

  static String? _authorEmail(AuthProvider a) =>
      (a.authorName ?? '').trim().isNotEmpty && (a.authorEmail ?? '').trim().isNotEmpty ? a.authorEmail : null;

  /// Seçili öğeleri tek commit'te siler. Klasör içeren veya çok öğeli
  /// silmelerde onay için kelimenin yazılması istenir. Silindiyse true.
  static Future<bool> deleteEntries(BuildContext context, List<RepoEntry> entries) async {
    if (entries.isEmpty) return false;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final upload = Provider.of<UploadProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final token = auth.token;
    final repo = repoProv.selectedRepo;
    final branch = repoProv.selectedBranch;
    if (token == null || repo == null || branch == null) return false;

    var fileCount = 0;
    var folderCount = 0;
    var bytes = 0;
    for (final e in entries) {
      if (e.isDir) {
        folderCount++;
        fileCount += e.fileCount;
      } else {
        fileCount++;
      }
      bytes += e.size;
    }
    if (fileCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seçilen klasörler boş; silinecek dosya yok.')),
      );
      return false;
    }

    final single = entries.length == 1 ? entries.first : null;
    final title = single != null
        ? (single.isDir ? 'Klasör silinsin mi?' : 'Dosya silinsin mi?')
        : '${entries.length} öğe silinsin mi?';
    final summary = single != null && !single.isDir
        ? '${single.path} dalda ($branch) silinecek.'
        : '$fileCount dosya${folderCount > 0 ? ' ($folderCount klasör dahil)' : ''}, toplam ${formatBytes(bytes)}, '
            '"$branch" dalından tek bir commit ile silinecek. Commit geçmişinden geri alınabilir.';

    final needsTyping = folderCount > 0 || entries.length > 5;
    final bool ok;
    if (needsTyping) {
      final expected = single != null ? single.name : 'sil';
      ok = await showDialog<bool>(
            context: context,
            builder: (_) => _TypedConfirmDialog(title: title, content: summary, expected: expected),
          ) ??
          false;
    } else {
      ok = await ConfirmDialog.show(
        context,
        title: title,
        content: summary,
        confirmLabel: 'Sil',
        isDestructive: true,
      );
    }
    if (!ok || !context.mounted) return false;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final message = single != null
        ? 'chore: delete ${single.path} via Gitpush'
        : 'chore: delete ${entries.length} items via Gitpush';

    _showBusy(context, 'Siliniyor...');
    try {
      final res = await repoProv.deleteEntries(
        token: token,
        entries: entries,
        message: message,
        authorName: _authorName(auth),
        authorEmail: _authorEmail(auth),
      );
      navigator.pop();
      await upload.recordExternalCommit(
        owner: repo.owner,
        repo: repo.name,
        branch: branch,
        commitMessage: message,
        commitSha: res.commitSha,
        filesCount: res.fileCount,
      );
      settings.success();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${res.fileCount} dosya silindi (${shortSha(res.commitSha)}).')));
      return true;
    } on GitHubApiException catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('Beklenmeyen hata: $e')));
      return false;
    }
  }

  /// Yeni yol sorar; dosyayı/klasörü içeriği yeniden yüklemeden taşır
  /// (tek commit). Başarılıysa yeni yolu, değilse null döner.
  static Future<String?> renameOrMove(BuildContext context, RepoEntry entry) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final upload = Provider.of<UploadProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final token = auth.token;
    final repo = repoProv.selectedRepo;
    final branch = repoProv.selectedBranch;
    if (token == null || repo == null || branch == null) return null;

    final newPath = await showDialog<String>(
      context: context,
      builder: (_) => _PathPromptDialog(entry: entry),
    );
    if (newPath == null || !context.mounted) return null;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);

    final List<RepoMove> moves;
    try {
      moves = repoProv.planMove(entry, newPath);
    } on GitHubApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return null;
    }

    final message = 'refactor: move ${entry.path} to ${newPath.trim()} via Gitpush';
    _showBusy(context, 'Taşınıyor...');
    try {
      final sha = await repoProv.applyMoves(
        token: token,
        moves: moves,
        message: message,
        authorName: _authorName(auth),
        authorEmail: _authorEmail(auth),
      );
      navigator.pop();
      await upload.recordExternalCommit(
        owner: repo.owner,
        repo: repo.name,
        branch: branch,
        commitMessage: message,
        commitSha: sha,
        filesCount: moves.length,
      );
      settings.success();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Taşındı (${shortSha(sha)}).')));
      return newPath.trim();
    } on GitHubApiException catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return null;
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('Beklenmeyen hata: $e')));
      return null;
    }
  }
}

/// Geri alınması zor işlemler için "şunu yazarak onayla" penceresi.
class _TypedConfirmDialog extends StatefulWidget {
  final String title;
  final String content;
  final String expected;

  const _TypedConfirmDialog({required this.title, required this.content, required this.expected});

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _matches => _ctrl.text.trim().toLowerCase() == widget.expected.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.content),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              text: 'Onaylamak için ',
              children: [
                TextSpan(text: widget.expected, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                const TextSpan(text: ' yazın:'),
              ],
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          child: const Text('Sil'),
        ),
      ],
    );
  }
}

class _PathPromptDialog extends StatefulWidget {
  final RepoEntry entry;

  const _PathPromptDialog({required this.entry});

  @override
  State<_PathPromptDialog> createState() => _PathPromptDialogState();
}

class _PathPromptDialogState extends State<_PathPromptDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.entry.path);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return AlertDialog(
      title: Text(e.isDir ? 'Klasörü taşı / yeniden adlandır' : 'Dosyayı taşı / yeniden adlandır'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.isDir
                ? '${e.fileCount} dosya, içerikleri yeniden yüklenmeden tek commit ile taşınır.'
                : 'İçerik yeniden yüklenmeden tek commit ile taşınır. Klasör eklemek için yolu değiştirin (ör. lib/yeni/ad.dart).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Yeni yol'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Taşı')),
      ],
    );
  }
}

// --- lib/utils/responsive.dart ---
/// Gitpush için tablet/telefon ayrımını tek bir yerden yöneten yardımcı sınıf.
///
/// Materyal tasarım rehberine uygun olarak 600 mantıksal piksel (dp) eşiği
/// kullanılır: bir ekranın en kısa kenarı bu değerin üzerindeyse tablet
/// kabul edilir. 11 inç tabletlerin en kısa kenarı bu değerin çok
/// üzerindedir, telefonlarda ise (yatay tutulsa bile) en kısa kenar bu
/// eşiğin altında kalır.
class Responsive {
  Responsive._();

  /// Tablet kabul edilmek için gereken en kısa kenar (mantıksal piksel).
  static const double tabletBreakpoint = 600;

  /// Verilen [size] için en kısa kenar eşik değerin üzerinde/eşitse tablettir.
  static bool isTabletSize(Size size) => size.shortestSide >= tabletBreakpoint;

  /// Henüz bir [BuildContext] yokken (ör. main() içinde, ilk kare
  /// çizilmeden önce) ham görünüm bilgisinden tablet tespiti yapar.
  /// Uygulama açılışında oryantasyon kilidini ayarlamak için kullanılır.
  static bool isTabletFromView(FlutterView view) {
    final logicalSize = view.physicalSize / view.devicePixelRatio;
    return isTabletSize(logicalSize);
  }
}

// --- lib/utils/secret_guard.dart ---
/// Gizli bilgilerin (token, .env, özel anahtar vb.) yanlışlıkla repoya
/// gönderilmesini engelleyen son savunma hattı. `src/utils/secretGuard.ts`
/// mantığının Dart karşılığıdır. Yalnızca yüksek güvenilirlikli eşleşmeleri
/// yakalar (yanlış alarm düşük tutulur).
class SecretCandidate {
  final String path;
  final Uint8List bytes;
  const SecretCandidate(this.path, this.bytes);
}

class SecretFinding {
  final String path;
  final String reason;
  const SecretFinding(this.path, this.reason);
}

class SecretGuard {
  static const int _maxScanBytes = 2 * 1024 * 1024;

  static final RegExp _envFile = RegExp(r'^\.env(\..+)?$');
  static final RegExp _safeEnvSuffix =
      RegExp(r'\.(example|sample|template|dist|defaults?)$', caseSensitive: false);
  static final RegExp _keyFileExt = RegExp(r'\.(pem|p12|pfx|jks|keystore|ppk)$');
  static final RegExp _sshKey = RegExp(r'^id_(rsa|dsa|ecdsa|ed25519)$');
  static final RegExp _credJson =
      RegExp(r'^(service-?account|credentials?)[\w.-]*\.json$');

  static final List<MapEntry<String, RegExp>> _patterns = [
    MapEntry('GitHub token', RegExp(r'\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b')),
    MapEntry('GitHub fine-grained token', RegExp(r'\bgithub_pat_[A-Za-z0-9_]{50,}\b')),
    MapEntry('AWS access key', RegExp(r'\bAKIA[0-9A-Z]{16}\b')),
    MapEntry('Google API key', RegExp(r'\bAIza[0-9A-Za-z_-]{35}\b')),
    MapEntry('Anthropic API key', RegExp(r'\bsk-ant-[A-Za-z0-9_-]{20,}\b')),
    MapEntry('Slack token', RegExp(r'\bxox[baprs]-[A-Za-z0-9-]{10,}\b')),
    MapEntry('Özel anahtar (private key)', RegExp(r'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----')),
  ];

  static bool isSensitiveFileName(String path) {
    final base = path.split('/').last.toLowerCase();
    if (_envFile.hasMatch(base)) return !_safeEnvSuffix.hasMatch(base);
    if (_keyFileExt.hasMatch(base)) return true;
    if (_sshKey.hasMatch(base)) return true;
    if (base == 'key.properties' || base == '.netrc' || base == '.pgpass') return true;
    if (_credJson.hasMatch(base)) return true;
    return false;
  }

  static bool _looksBinary(Uint8List bytes) {
    final n = bytes.length < 8000 ? bytes.length : 8000;
    for (var i = 0; i < n; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  static List<SecretFinding> scan(List<SecretCandidate> files) {
    final findings = <SecretFinding>[];
    for (final f in files) {
      if (isSensitiveFileName(f.path)) {
        findings.add(SecretFinding(f.path, 'Hassas dosya adı'));
        continue;
      }
      if (f.bytes.length > _maxScanBytes || _looksBinary(f.bytes)) continue;
      final text = utf8.decode(f.bytes, allowMalformed: true);
      for (final p in _patterns) {
        if (p.value.hasMatch(text)) {
          findings.add(SecretFinding(f.path, p.key));
          break;
        }
      }
    }
    return findings;
  }

  static String formatError(List<SecretFinding> findings) {
    final shown = findings.take(5).map((f) => '${f.path} (${f.reason})').join(', ');
    final more = findings.length > 5 ? ' ve ${findings.length - 5} dosya daha' : '';
    return 'Gizli bilgi içerebilecek dosya(lar) tespit edildi, push engellendi: '
        '$shown$more. Bu dosyaları listeden çıkarın veya içindeki anahtarları '
        'kaldırıp tekrar deneyin.';
  }
}

// --- lib/utils/url_utils.dart ---
/// Yalnızca https ve GitHub alan adlarına izin verir. `intent:`, `file:`,
/// `javascript:`, `content:` gibi şemalar veya başka alan adları reddedilir
/// (geçmiş kaydı / API yanıtı üzerinden kötü niyetli bağlantı açılmasını önler).
bool isSafeExternalUri(Uri uri) {
  if (uri.scheme != 'https') return false;
  if (uri.userInfo.isNotEmpty) return false;
  final host = uri.host.toLowerCase();
  return host == 'github.com' || host.endsWith('.github.com');
}

/// Bağlantıyı harici uygulamada (tarayıcı) açar.
///
/// Ön kontrol (can-launch) bilinçli olarak YAPILMAZ: Android 11+ paket
/// görünürlüğü yüzünden manifestte `<queries>` tanımlı değilse false dönüp
/// sessizce hiçbir şey yapmıyordu. Doğrudan `launchUrl` çağrılır; başarısız
/// olursa kullanıcıya SnackBar + "Kopyala" eylemi gösterilir.
Future<void> openExternalUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final trimmed = url.trim();

  var opened = false;
  if (trimmed.isNotEmpty) {
    try {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && isSafeExternalUri(uri)) {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      opened = false;
    }
  }

  if (!opened) {
    messenger?.showSnackBar(
      SnackBar(
        content: const Text('Link açılamadı.'),
        action: SnackBarAction(
          label: 'Kopyala',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: trimmed));
          },
        ),
      ),
    );
  }
}

// =============================================================================
// 3. TEMA (THEME)
// =============================================================================

// --- lib/theme/app_theme.dart ---
class AppTheme {
  // Marka Tohum Rengi (logo ile aynı indigo). Ayarlardan başka bir vurgu
  // rengi seçilebilir; bkz. `AppSettings.accentPalette`.
  static const Color seedColor = Color(0xFF5B6CFF);

  // Durum Renkleri
  static const Color statusNew = Color(0xFF2EA043);       // Yeni dosya (Yeşil)
  static const Color statusUpdate = Color(0xFF1F6FEB);    // Güncelleme (Mavi)
  static const Color statusDelete = Color(0xFFDA3633);    // Silinecek (Kırmızı)
  static const Color statusNewFolder = Color(0xFFD29922); // Yeni Klasör (Amber)

  // Tipografi Stilleri
  static const TextStyle monoStyle = TextStyle(
    fontFamily: 'monospace',
    letterSpacing: -0.2,
  );

  static const TextStyle monoBold = TextStyle(
    fontFamily: 'monospace',
    fontWeight: FontWeight.bold,
    letterSpacing: -0.2,
  );

  // Geriye dönük uyumlu kısayollar (varsayılan vurgu rengi).
  static ThemeData get lightTheme => build(seed: seedColor, brightness: Brightness.light);
  static ThemeData get darkTheme => build(seed: seedColor, brightness: Brightness.dark);

  /// Seçilen vurgu rengi ve (koyu temada) AMOLED tercihine göre tema üretir.
  static ThemeData build({
    required Color seed,
    required Brightness brightness,
    bool amoled = false,
  }) {
    var colorScheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

    final useAmoled = amoled && brightness == Brightness.dark;
    if (useAmoled) {
      colorScheme = colorScheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0C),
        surfaceContainer: const Color(0xFF111114),
        surfaceContainerHigh: const Color(0xFF17171B),
        surfaceContainerHighest: const Color(0xFF1E1E23),
      );
    }

    final radius12 = BorderRadius.circular(12);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        space: 1,
        thickness: 1,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: BorderSide.none,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius12),
          minimumSize: const Size(64, 48), // Sabit min. genişlik: sonsuz genişlik komşu Expanded widget'ları sıfıra sıkıştırıyordu
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius12),
          minimumSize: const Size(0, 48),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: radius12,
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius12),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        elevation: 0,
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: colorScheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(color: colorScheme.onSurface),
        unselectedLabelTextStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

// =============================================================================
// 4. SERVİSLER (SERVICES)
// =============================================================================

// --- lib/services/app_lock_service.dart ---
/// PIN doğrulama sonucu.
class PinVerifyResult {
  final bool ok;

  /// Hatalı denemeler yüzünden kilitliyse kalan süre.
  final Duration lockedFor;

  /// Bu denemeden sonra toplam ardışık hatalı deneme.
  final int failedAttempts;

  const PinVerifyResult({required this.ok, this.lockedFor = Duration.zero, this.failedAttempts = 0});

  bool get isLockedOut => lockedFor > Duration.zero;
}

/// Uygulama kilidi (PIN) için güvenli saklama ve doğrulama.
///
/// * PIN düz metin SAKLANMAZ: rastgele tuz + 20.000 tur SHA-256 karması,
///   Android Keystore destekli `flutter_secure_storage` içinde tutulur.
/// * Karşılaştırma sabit zamanlıdır.
/// * Ardışık 5 hatadan sonra artan bekleme süresi uygulanır (30 sn → 32 dk);
///   bekleme süresi uygulama kapatılsa da korunur.
class AppLockService {
  AppLockService({FlutterSecureStorage? storage, DateTime Function()? clock, Random? random})
      : _storage = storage ?? const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true)),
        _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  static const int pinLength = 6;
  static const int hashRounds = 20000;
  static const int freeAttempts = 5;

  static const String _kSalt = 'gitpush_pin_salt';
  static const String _kHash = 'gitpush_pin_hash';
  static const String _kFails = 'gitpush_pin_fails';
  static const String _kUntil = 'gitpush_pin_locked_until';

  final FlutterSecureStorage _storage;
  final DateTime Function() _clock;
  final Random _random;

  static bool isValidPin(String pin) => RegExp('^\\d{$pinLength}\$').hasMatch(pin);

  /// Çok basit PIN'ler (000000, 123456 ...) reddedilir.
  static bool isWeakPin(String pin) {
    if (!isValidPin(pin)) return true;
    if (pin.split('').toSet().length == 1) return true;
    const sequences = ['012345', '123456', '234567', '345678', '456789', '987654', '876543', '765432', '654321', '543210'];
    return sequences.contains(pin);
  }

  /// Hatalı deneme sayısına göre bekleme süresi.
  static Duration lockoutFor(int failedAttempts) {
    if (failedAttempts < freeAttempts) return Duration.zero;
    final step = min(failedAttempts - freeAttempts, 6);
    return Duration(seconds: 30 * (1 << step));
  }

  /// Karma üretir (test edilebilmesi için statik ve saf).
  static String hashPin(String pin, List<int> salt, {int rounds = hashRounds}) {
    final pinBytes = utf8.encode(pin);
    var digest = sha256.convert(<int>[...salt, ...pinBytes]).bytes;
    for (var i = 0; i < rounds; i++) {
      digest = sha256.convert(<int>[...digest, ...salt, ...pinBytes]).bytes;
    }
    return base64Encode(digest);
  }

  static bool constantTimeEquals(String a, String b) {
    final x = utf8.encode(a);
    final y = utf8.encode(b);
    var diff = x.length ^ y.length;
    final n = min(x.length, y.length);
    for (var i = 0; i < n; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }

  Future<bool> hasPin() async {
    try {
      final h = await _storage.read(key: _kHash);
      return h != null && h.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) {
      throw ArgumentError('PIN $pinLength haneli olmalıdır.');
    }
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    await _storage.write(key: _kSalt, value: base64Encode(salt));
    await _storage.write(key: _kHash, value: hashPin(pin, salt));
    await _resetFailures();
  }

  /// Kalan bekleme süresi (kilitli değilse sıfır).
  Future<Duration> lockoutRemaining() async {
    try {
      final raw = await _storage.read(key: _kUntil);
      final ms = int.tryParse(raw ?? '');
      if (ms == null) return Duration.zero;
      final left = DateTime.fromMillisecondsSinceEpoch(ms).difference(_clock());
      return left > Duration.zero ? left : Duration.zero;
    } catch (_) {
      return Duration.zero;
    }
  }

  Future<PinVerifyResult> verify(String pin) async {
    final remaining = await lockoutRemaining();
    if (remaining > Duration.zero) {
      return PinVerifyResult(ok: false, lockedFor: remaining, failedAttempts: await _readFails());
    }

    try {
      final saltB64 = await _storage.read(key: _kSalt);
      final stored = await _storage.read(key: _kHash);
      if (saltB64 == null || stored == null) {
        return const PinVerifyResult(ok: false);
      }
      final computed = hashPin(pin, base64Decode(saltB64));
      if (constantTimeEquals(computed, stored)) {
        await _resetFailures();
        return const PinVerifyResult(ok: true);
      }
    } catch (_) {
      // Okuma/çözme hatası: doğrulama başarısız sayılır (güvenli taraf).
    }

    final fails = (await _readFails()) + 1;
    await _storage.write(key: _kFails, value: fails.toString());
    final wait = lockoutFor(fails);
    if (wait > Duration.zero) {
      final until = _clock().add(wait).millisecondsSinceEpoch;
      await _storage.write(key: _kUntil, value: until.toString());
    }
    return PinVerifyResult(ok: false, lockedFor: wait, failedAttempts: fails);
  }

  Future<int> _readFails() async {
    try {
      return int.tryParse(await _storage.read(key: _kFails) ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _resetFailures() async {
    await _storage.delete(key: _kFails);
    await _storage.delete(key: _kUntil);
  }

  /// PIN'i ve sayaçları tamamen siler.
  Future<void> clear() async {
    await _storage.delete(key: _kSalt);
    await _storage.delete(key: _kHash);
    await _resetFailures();
  }
}

// --- lib/services/github_device_flow.dart ---
/// GitHub'ın `POST /login/device/code` yanıtı.
class DeviceCodeInfo {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;

  const DeviceCodeInfo({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });
}

class DeviceFlowException implements Exception {
  final String message;
  DeviceFlowException(this.message);

  @override
  String toString() => message;
}

/// GitHub OAuth Device Flow (RFC 8628).
///
/// Uygulamaya yalnızca herkese açık `client_id` gömülür; `client_secret`
/// gerekmez ve ASLA istemciye konmamalıdır. Derlemede
/// `--dart-define=GITHUB_CLIENT_ID=...` ile verilir; verilmediyse kullanıcı
/// uygulama içinden kendi OAuth App Client ID'sini girebilir.
class GitHubDeviceFlow {
  static const String clientId = String.fromEnvironment('GITHUB_CLIENT_ID');

  /// Tüm depolar (özel + herkese açık).
  static const String scopeAll = 'repo workflow';

  /// Yalnızca herkese açık depolar (daha dar yetki).
  static const String scopePublic = 'public_repo workflow';

  /// Varsayılan kapsam.
  static const String scope = scopeAll;

  static bool isAllowedScope(String s) => s == scopeAll || s == scopePublic;
  static const String _deviceCodeUrl = 'https://github.com/login/device/code';
  static const String _tokenUrl = 'https://github.com/login/oauth/access_token';
  static const String _grantType = 'urn:ietf:params:oauth:grant-type:device_code';

  /// Biçim kontrolü: OAuth App (20 hex) ve GitHub App (`Iv1.` / `Iv23`) kimlikleri.
  static bool isValidClientId(String id) => RegExp(r'^[A-Za-z0-9._-]{10,40}$').hasMatch(id);

  static bool get isConfigured => isValidClientId(clientId);

  final String _clientId;
  final http.Client _client;
  final Future<void> Function(Duration) _sleep;

  GitHubDeviceFlow({
    String? clientIdOverride,
    http.Client? client,
    Future<void> Function(Duration)? sleep,
  })  : _clientId = clientIdOverride ?? clientId,
        _client = client ?? http.Client(),
        _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  /// Doğrulama adresi yalnızca github.com olabilir (sahte adrese yönlendirmeyi önler).
  static bool isTrustedVerificationUri(String raw) {
    final uri = Uri.tryParse(raw);
    return uri != null && uri.scheme == 'https' && uri.host == 'github.com';
  }

  Future<Map<String, dynamic>> _post(String url, Map<String, String> body) async {
    final response = await _client
        .post(
          Uri.parse(url),
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'Gitpush',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 20));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw DeviceFlowException('GitHub beklenmeyen bir yanıt döndürdü (${response.statusCode}).');
    }
    return decoded;
  }

  String _describeError(String code) {
    switch (code) {
      case 'device_flow_disabled':
        return 'OAuth App ayarlarında "Enable Device Flow" kapalı. GitHub → Developer settings → OAuth Apps bölümünden açın.';
      case 'incorrect_client_credentials':
        return 'Client ID geçersiz. Girdiğiniz veya derlemedeki GITHUB_CLIENT_ID değerini kontrol edin.';
      case 'expired_token':
        return 'Doğrulama kodunun süresi doldu. Lütfen tekrar deneyin.';
      case 'access_denied':
        return 'GitHub üzerinde yetkilendirme reddedildi.';
      case 'unsupported_grant_type':
      case 'incorrect_device_code':
        return 'Doğrulama oturumu geçersiz. Lütfen tekrar deneyin.';
      default:
        return 'GitHub girişi başarısız: $code';
    }
  }

  /// 1. adım: kullanıcıya gösterilecek kodu ve doğrulama adresini al.
  Future<DeviceCodeInfo> start({String scopeOverride = scope}) async {
    if (!isValidClientId(_clientId)) {
      throw DeviceFlowException('GitHub ile giriş için geçerli bir Client ID gerekli.');
    }
    if (!isAllowedScope(scopeOverride)) {
      throw DeviceFlowException('Geçersiz yetki kapsamı.');
    }
    try {
      final json = await _post(_deviceCodeUrl, {'client_id': _clientId, 'scope': scopeOverride});
      final error = json['error'];
      if (error is String) throw DeviceFlowException(_describeError(error));

      final deviceCode = json['device_code'];
      final userCode = json['user_code'];
      final uri = json['verification_uri'];
      if (deviceCode is! String || userCode is! String || uri is! String) {
        throw DeviceFlowException('GitHub yanıtı eksik alanlar içeriyor.');
      }
      if (!isTrustedVerificationUri(uri)) {
        throw DeviceFlowException('Güvenilmeyen doğrulama adresi reddedildi.');
      }
      return DeviceCodeInfo(
        deviceCode: deviceCode,
        userCode: userCode,
        verificationUri: uri,
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 900,
        interval: (json['interval'] as num?)?.toInt() ?? 5,
      );
    } on DeviceFlowException {
      rethrow;
    } on TimeoutException {
      throw DeviceFlowException('GitHub\'a bağlanılamadı (zaman aşımı).');
    } catch (_) {
      throw DeviceFlowException('GitHub\'a bağlanılamadı. İnternet bağlantınızı kontrol edin.');
    }
  }

  /// 2. adım: kullanıcı onaylayana kadar bekler. İptal edilirse `null` döner.
  Future<String?> pollForToken(
    DeviceCodeInfo info, {
    bool Function()? isCancelled,
  }) async {
    var interval = info.interval < 5 ? 5 : info.interval;
    var waited = 0;
    var failures = 0;

    while (true) {
      for (var i = 0; i < interval; i++) {
        if (isCancelled?.call() ?? false) return null;
        await _sleep(const Duration(seconds: 1));
      }
      waited += interval;
      if (isCancelled?.call() ?? false) return null;
      if (waited > info.expiresIn) throw DeviceFlowException(_describeError('expired_token'));

      Map<String, dynamic> json;
      try {
        json = await _post(_tokenUrl, {
          'client_id': _clientId,
          'device_code': info.deviceCode,
          'grant_type': _grantType,
        });
        failures = 0;
      } on DeviceFlowException {
        rethrow;
      } catch (_) {
        // Geçici ağ hatası: üst üste 3 kez olursa pes et.
        if (++failures >= 3) {
          throw DeviceFlowException('GitHub\'a bağlanılamadı. İnternet bağlantınızı kontrol edin.');
        }
        continue;
      }

      final token = json['access_token'];
      if (token is String && token.isNotEmpty) return token;

      final error = json['error'];
      if (error == 'authorization_pending') continue;
      if (error == 'slow_down') {
        interval = ((json['interval'] as num?)?.toInt() ?? interval + 5);
        continue;
      }
      throw DeviceFlowException(_describeError(error is String ? error : 'unknown'));
    }
  }
}

// --- lib/services/github_service.dart ---
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

// --- lib/services/repo_diff.dart ---
/// Gönderilecek dosyaların gruplanmış planı (önizleme + push girdisi).
class PushPlan {
  final List<GitFileItem> adds;
  final List<GitFileItem> updates;
  final List<GitFileItem> deletes;
  final List<GitFileItem> unchanged;
  final List<GitFileItem> conflicts;

  /// "Mevcut dosyaların üzerine yazma" kapalıyken atlanan güncellemeler.
  final List<GitFileItem> skipped;

  /// Repo ağacı bilinmiyorsa (alınamadıysa) push engellenir.
  final bool treeUnknown;

  const PushPlan({
    this.adds = const <GitFileItem>[],
    this.updates = const <GitFileItem>[],
    this.deletes = const <GitFileItem>[],
    this.unchanged = const <GitFileItem>[],
    this.conflicts = const <GitFileItem>[],
    this.skipped = const <GitFileItem>[],
    this.treeUnknown = false,
  });

  bool get hasBlockers => conflicts.isNotEmpty || treeUnknown;
  bool get hasChanges =>
      adds.isNotEmpty || updates.isNotEmpty || deletes.isNotEmpty;

  /// Gerçekten push edilecek öğeler (değişmeyenler ve atlananlar hariç).
  List<GitFileItem> get pushItems => [...adds, ...updates, ...deletes];

  /// Açıkça onaylanmış silme yolları (normalleştirilmiş).
  Set<String> get approvedDeletePaths => deletes
      .map((f) => normalizeAndValidateGitPath(f.repoPath).normalizedPath)
      .toSet();

  static PushPlan build(
    List<GitFileItem> selected, {
    List<GitFileItem> deletes = const <GitFileItem>[],
    bool skipExisting = false,
  }) {
    final adds = <GitFileItem>[];
    final updates = <GitFileItem>[];
    final unchanged = <GitFileItem>[];
    final conflicts = <GitFileItem>[];
    final skipped = <GitFileItem>[];
    var unknown = false;

    for (final f in selected) {
      if (!f.statusKnown) unknown = true;
      switch (f.status) {
        case GitFileStatus.isNew:
        case GitFileStatus.newFolder:
          adds.add(f);
          break;
        case GitFileStatus.update:
          if (skipExisting) {
            skipped.add(f);
          } else {
            updates.add(f);
          }
          break;
        case GitFileStatus.unchanged:
          unchanged.add(f);
          break;
        case GitFileStatus.conflict:
          conflicts.add(f);
          break;
        case GitFileStatus.delete:
          // Seçili listede silme yok; yalnızca `deletes` parametresi kullanılır.
          break;
      }
    }

    return PushPlan(
      adds: adds,
      updates: updates,
      deletes: deletes,
      unchanged: unchanged,
      conflicts: conflicts,
      skipped: skipped,
      treeUnknown: unknown,
    );
  }
}

/// ZIP yollarının repo yapısına otomatik hizalanma sonucu.
///
/// ZIP yolu, baştan [stripSegments] klasör kaldırılıp başına [addPrefix]
/// eklenerek repo yoluna çevrilir.
class ZipAlignment {
  final int stripSegments;

  /// Boş ya da `a/b/` biçiminde.
  final String addPrefix;

  /// Bu hizalamayla repoda bulunan dosya sayısı.
  final int matches;

  /// Hizalama uygulanmadan repoda bulunan dosya sayısı.
  final int baselineMatches;
  final int total;

  const ZipAlignment({
    required this.stripSegments,
    required this.addPrefix,
    required this.matches,
    required this.baselineMatches,
    required this.total,
  });

  /// Özgün (ZIP içindeki, normalleştirilmiş) yolu repo yoluna çevirir.
  String apply(String originalPath) {
    final segs = originalPath.split('/');
    final k = stripSegments < segs.length ? stripSegments : segs.length - 1;
    return '$addPrefix${segs.sublist(k).join('/')}';
  }

  String describe() {
    final parts = <String>[];
    if (stripSegments > 0) {
      parts.add('ZIP yollarından $stripSegments üst klasör kaldırıldı');
    }
    if (addPrefix.isNotEmpty) {
      parts.add('"$addPrefix" öneki eklendi');
    }
    return 'Otomatik eşleştirme: ${parts.join(', ')} '
        '($matches/$total dosya repoda bulundu).';
  }
}

class _AlignCandidate {
  final int k;
  final String prefix;
  final int votes;
  const _AlignCandidate(this.k, this.prefix, this.votes);
}

/// ZIP (Mod A) ve çoklu dosya (Mod B) için TEK sınıflandırma noktası.
class RepoDiff {
  static const int maxBlobBytes = 50 * 1024 * 1024;

  /// Her dosyanın durumunu repo ağacına göre yeniden hesaplar.
  /// [index] null ise durum bilinmiyor demektir (`statusKnown = false`).
  static void classify(List<GitFileItem> files, RepoTreeIndex? index) {
    for (final f in files) {
      if (f.status == GitFileStatus.delete) continue;
      _classifyOne(f, index);
    }
    _markBatchConflicts(files);
  }

  static void _setConflict(GitFileItem f, String message) {
    f.status = GitFileStatus.conflict;
    f.conflictMessage = message;
    f.statusKnown = true;
    f.remoteSha = null;
    f.remoteMode = null;
  }

  static void _classifyOne(GitFileItem f, RepoTreeIndex? index) {
    f.conflictMessage = null;

    if (f.needsChoice) {
      _setConflict(f, 'Birden fazla eşleşme var, seçin.');
      return;
    }

    final validation = normalizeAndValidateGitPath(f.targetPath);
    if (!validation.isValid) {
      _setConflict(f, validation.error ?? 'Geçersiz dosya yolu.');
      return;
    }

    final bytes = f.bytes;
    if (bytes == null) {
      _setConflict(f, 'Dosya içeriği okunamadı.');
      return;
    }
    if (f.size > maxBlobBytes || bytes.length > maxBlobBytes) {
      _setConflict(f, 'Dosya 50 MB sınırını aşıyor; gönderilemez.');
      return;
    }

    if (index == null) {
      f.statusKnown = false;
      f.remoteSha = null;
      f.remoteMode = null;
      return;
    }

    final path = validation.normalizedPath;
    final node = index.nodes[path];

    if (node != null) {
      if (node.isTree) {
        _setConflict(
          f,
          'Bu yol bir klasör; dosya adı ekleyin (örn. $path/${f.sourceName}).',
        );
        return;
      }
      if (!node.isBlob) {
        _setConflict(f, 'Bu yol bir alt modül (submodule); üzerine yazılamaz.');
        return;
      }

      f.computedSha ??= GitHubService.calculateGitBlobSha(bytes);
      f.remoteSha = node.sha;
      f.remoteMode = node.mode;
      f.statusKnown = true;
      f.status = f.computedSha == node.sha
          ? GitFileStatus.unchanged
          : GitFileStatus.update;
      return;
    }

    final fileAncestor = index.findFileAncestor(path);
    if (fileAncestor != null) {
      _setConflict(
        f,
        'Üst yol "$fileAncestor" repoda bir dosya; klasör olarak kullanılamaz.',
      );
      return;
    }

    f.remoteSha = null;
    f.remoteMode = null;
    f.statusKnown = true;
    f.status =
        index.hasParentFolder(path) ? GitFileStatus.isNew : GitFileStatus.newFolder;
  }

  /// Aynı yola giden dosyalar (büyük/küçük harf duyarsız) ve dosya/klasör
  /// çakışmaları (aynı pakette `a` dosyası ile `a/b` dosyası).
  static void _markBatchConflicts(List<GitFileItem> files) {
    final groups = <String, List<GitFileItem>>{};
    for (final f in files) {
      if (!f.isSelected || f.status == GitFileStatus.delete) continue;
      final v = normalizeAndValidateGitPath(f.targetPath);
      if (!v.isValid) continue;
      groups.putIfAbsent(v.normalizedPath.toLowerCase(), () => <GitFileItem>[]).add(f);
    }

    for (final group in groups.values) {
      if (group.length > 1) {
        for (final f in group) {
          _setConflict(f, 'Aynı yola giden birden fazla dosya var.');
        }
      }
    }

    for (final entry in groups.entries) {
      var idx = entry.key.lastIndexOf('/');
      while (idx > 0) {
        final parent = entry.key.substring(0, idx);
        final parentGroup = groups[parent];
        if (parentGroup != null) {
          for (final f in entry.value) {
            _setConflict(f, 'Bu yolun üst yolu ("$parent") aynı gönderimde dosya olarak var.');
          }
          for (final f in parentGroup) {
            _setConflict(f, 'Bu yol, aynı gönderimde klasör olarak da kullanılıyor.');
          }
        }
        idx = parent.lastIndexOf('/');
      }
    }
  }

  /// ZIP yollarını repodaki gerçek konuma hizalamayı dener.
  ///
  /// [originalPaths]: ZIP içindeki (normalleştirilmiş) tam yollar.
  /// [currentPaths]: şu anki ayarlarla (tek kök klasör kaldırma vb.) oluşan
  /// yollar. Yalnızca hizalama, mevcut ayara göre repoda BULUNAN dosya sayısını
  /// anlamlı biçimde artırıyorsa sonuç döner; belirsizse null (dokunulmaz).
  static ZipAlignment? detectAlignment({
    required List<String> originalPaths,
    required List<String> currentPaths,
    required RepoTreeIndex index,
    int maxStrip = 6,
  }) {
    final total = originalPaths.length;
    if (total == 0 || index.nodes.isEmpty) return null;

    // Repodaki her blob için tüm yol sonekleri -> o sonekten önceki önek
    final lowerBlobs = <String>{};
    final suffixPrefixes = <String, Set<String>>{};
    var budget = 300000;
    for (final node in index.nodes.values) {
      if (!node.isBlob) continue;
      final path = node.path;
      lowerBlobs.add(path.toLowerCase());
      var start = 0;
      while (true) {
        final suffix = path.substring(start).toLowerCase();
        suffixPrefixes
            .putIfAbsent(suffix, () => <String>{})
            .add(path.substring(0, start));
        budget--;
        final next = path.indexOf('/', start);
        if (next == -1) break;
        start = next + 1;
      }
      if (budget <= 0) break;
    }

    var baseline = 0;
    for (final p in currentPaths) {
      if (lowerBlobs.contains(p.toLowerCase())) baseline++;
    }
    if (baseline >= total) return null;

    // (kaldırılan segment sayısı, eklenecek önek) -> eşleşen dosya sayısı
    final votes = <String, int>{};
    for (final orig in originalPaths) {
      final segs = orig.split('/');
      final maxK = segs.length - 1 < maxStrip ? segs.length - 1 : maxStrip;
      for (var k = 0; k <= maxK; k++) {
        final stripped = segs.sublist(k).join('/').toLowerCase();
        final prefixes = suffixPrefixes[stripped];
        if (prefixes == null || prefixes.length > 20) continue;
        for (final pre in prefixes) {
          final key = '$k|$pre';
          votes[key] = (votes[key] ?? 0) + 1;
        }
      }
    }
    if (votes.isEmpty) return null;

    final candidates = <_AlignCandidate>[];
    votes.forEach((key, v) {
      final sep = key.indexOf('|');
      candidates.add(_AlignCandidate(
        int.parse(key.substring(0, sep)),
        key.substring(sep + 1),
        v,
      ));
    });
    candidates.sort((a, b) {
      if (a.votes != b.votes) return b.votes.compareTo(a.votes);
      if (a.k != b.k) return a.k.compareTo(b.k);
      return a.prefix.length.compareTo(b.prefix.length);
    });

    final top = candidates.first;
    if (candidates.length > 1) {
      final second = candidates[1];
      // Aynı kaldırma sayısında farklı öneklerle eşit oy: belirsiz.
      if (second.votes == top.votes && second.k == top.k) return null;
    }

    final minVotes = total == 1 ? 1 : 2;
    if (top.votes < minVotes) return null;
    if (top.votes * 100 < total * 40) return null; // en az %40 eşleşme
    if (top.votes <= baseline) return null;

    return ZipAlignment(
      stripSegments: top.k,
      addPrefix: top.prefix,
      matches: top.votes,
      baselineMatches: baseline,
      total: total,
    );
  }

  /// ZIP için "Repoda olup ZIP'te olmayanları sil" adaylarını hesaplar.
  ///
  /// Kapsam (en güvenli seçenek): hedef klasör öneki varsa yalnızca o önekin
  /// altı; yoksa yalnızca ZIP'in dokunduğu üst düzey klasörlerin altı. Kökteki
  /// gevşek dosyalar ASLA silinmez.
  static List<GitFileItem> computeUnlistedDeletes({
    required RepoTreeIndex index,
    required Iterable<String> zipEffectivePaths,
    required String normalizedPrefix,
  }) {
    final zipPaths = <String>{};
    for (final raw in zipEffectivePaths) {
      final v = normalizeAndValidateGitPath(raw);
      if (v.isValid) zipPaths.add(v.normalizedPath);
    }

    final scopes = <String>{};
    if (normalizedPrefix.isNotEmpty) {
      scopes.add(normalizedPrefix); // "a/b/" biçiminde
    } else {
      for (final p in zipPaths) {
        final slash = p.indexOf('/');
        if (slash > 0) scopes.add('${p.substring(0, slash)}/');
      }
    }
    if (scopes.isEmpty) return <GitFileItem>[];

    final result = <GitFileItem>[];
    final candidates = index.nodes.values.where((n) => n.isBlob).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final node in candidates) {
      if (zipPaths.contains(node.path)) continue;
      final inScope = scopes.any((s) => node.path.startsWith(s));
      if (inScope) result.add(GitFileItem.deletion(node.path));
    }
    return result;
  }
}

// --- lib/services/run_tracker.dart ---
class RunEvaluation {
  /// Push'un ürettiği commit'e (head_sha) ait çalışmalar.
  final List<ActionRun> matching;

  /// Eşleşen çalışma var ve hepsi tamamlandı.
  final bool allCompleted;

  const RunEvaluation({required this.matching, required this.allCompleted});

  bool get found => matching.isNotEmpty;
}

/// Eski (başka commit'e ait) çalışmaları yok sayar; yalnızca [commitSha] ile
/// eşleşenleri döndürür. Eşleşme yoksa polling devam etmelidir.
RunEvaluation evaluateRuns(List<ActionRun> runs, String commitSha) {
  final matching = runs.where((r) => r.headSha == commitSha).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final done = matching.isNotEmpty && matching.every((r) => r.isCompleted);
  return RunEvaluation(matching: matching, allCompleted: done);
}

// --- lib/services/storage_service.dart ---
class StorageService {
  static const String _keyToken = 'gitpush_github_token';
  static const String _keyUsername = 'gitpush_github_username';
  static const String _keyAuthorName = 'gitpush_author_name';
  static const String _keyAuthorEmail = 'gitpush_author_email';
  static const String _keyShortcuts = 'gitpush_custom_shortcuts';
  static const String _keyThemeMode = 'gitpush_theme_mode';
  static const String _keyLastRepo = 'gitpush_last_repo';
  static const String _keyLastBranch = 'gitpush_last_branch';
  static const String _keyHistory = 'gitpush_commit_history';
  static const String _keyClientId = 'gitpush_oauth_client_id';
  static const String _keySettings = 'gitpush_app_settings';
  static const String _keyLastActive = 'gitpush_last_active_ms';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // Token işlemleri (Secure Storage)
  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _keyToken, value: token);
  }

  Future<String?> getToken() async {
    return await _secureStorage.read(key: _keyToken);
  }

  Future<void> clearAuth() async {
    await _secureStorage.delete(key: _keyToken);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
  }

  // OAuth Client ID (herkese açık bir değerdir, gizli değildir; çıkışta silinmez)
  Future<void> saveClientId(String clientId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyClientId, clientId);
  }

  Future<String?> getClientId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyClientId);
  }

  Future<void> clearClientId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyClientId);
  }

  /// Çıkışta kişisel verilerin tamamını temizler: token, kullanıcı adı,
  /// yazar adı/e-postası, son repo/dal ve commit geçmişi.
  /// (Tema ve kısayollar kişisel veri sayılmadığı için korunur.)
  Future<void> clearAllUserData() async {
    await _secureStorage.delete(key: _keyToken);
    final prefs = await SharedPreferences.getInstance();
    for (final k in [
      _keyUsername,
      _keyAuthorName,
      _keyAuthorEmail,
      _keyLastRepo,
      _keyLastBranch,
      _keyHistory,
    ]) {
      await prefs.remove(k);
    }
  }

  // Kullanıcı adı ve Yazar bilgisi
  Future<void> saveUserInfo({required String username, String? name, String? email}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, username);
    if (name != null) await prefs.setString(_keyAuthorName, name);
    if (email != null) await prefs.setString(_keyAuthorEmail, email);
  }

  Future<Map<String, String?>> getUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'username': prefs.getString(_keyUsername),
      'name': prefs.getString(_keyAuthorName),
      'email': prefs.getString(_keyAuthorEmail),
    };
  }

  // Uygulama tercihleri (tek JSON). Gizli veri içermez.
  Future<AppSettings> getAppSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings.fromJson(prefs.getString(_keySettings));
  }

  Future<void> saveAppSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySettings, settings.toJson());
  }

  // Son etkinlik zamanı (otomatik oturum kapatma için)
  Future<DateTime?> getLastActive() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_keyLastActive);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> touchLastActive([DateTime? at]) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastActive, (at ?? DateTime.now()).millisecondsSinceEpoch);
  }

  /// Önbellek niteliğindeki tercihleri (son repo/dal) siler; tema, kısayol ve
  /// ayarlar korunur.
  Future<void> clearLastRepoAndBranch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastRepo);
    await prefs.remove(_keyLastBranch);
  }

  // Son Seçilen Repo & Branch
  Future<void> saveLastRepoAndBranch(String repoFullName, String branch) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings.fromJson(prefs.getString(_keySettings));
    if (!settings.rememberLastRepo) {
      await prefs.remove(_keyLastRepo);
      await prefs.remove(_keyLastBranch);
      return;
    }
    await prefs.setString(_keyLastRepo, repoFullName);
    await prefs.setString(_keyLastBranch, branch);
  }

  Future<Map<String, String?>> getLastRepoAndBranch() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'repo': prefs.getString(_keyLastRepo),
      'branch': prefs.getString(_keyLastBranch),
    };
  }

  // Tema Tercihi
  Future<void> saveThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode);
  }

  Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyThemeMode) ?? 'system';
  }

  // Özel Kısayollar
  Future<List<String>> getShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyShortcuts) ?? [
      'Repo kökü',
      'lib/',
      'lib/screens/',
      'lib/models/',
      'lib/services/',
      'lib/widgets/',
      'assets/',
      '.github/workflows/',
      'android/app/',
    ];
  }

  Future<void> saveShortcuts(List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyShortcuts, list);
  }

  // Geçmiş Kayıtları
  Future<List<HistoryItem>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyHistory) ?? [];
    return list.map((item) => HistoryItem.fromJson(item)).toList();
  }

  Future<void> addHistoryItem(HistoryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyHistory) ?? [];
    list.insert(0, item.toJson());
    // Ayarlardaki sınır kadar kaydı tut (varsayılan 50)
    final limit = AppSettings.fromJson(prefs.getString(_keySettings)).historyLimit;
    if (list.length > limit) {
      list.removeRange(limit, list.length);
    }
    await prefs.setStringList(_keyHistory, list);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHistory);
  }

  /// Yeni klasör kısayolu ekler (tekrarı yok sayar). Eklendiyse true.
  Future<bool> addShortcut(String raw) async {
    final value = raw.trim();
    if (value.isEmpty || value.length > 120) return false;
    final list = await getShortcuts();
    if (list.any((e) => e.toLowerCase() == value.toLowerCase())) return false;
    await saveShortcuts([...list, value]);
    return true;
  }

  Future<void> resetShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyShortcuts);
  }
}

// --- lib/services/zip_service.dart ---
class ZipServiceException implements Exception {
  final String message;
  ZipServiceException(this.message);

  @override
  String toString() => message;
}

class ZipExtractResult {
  final List<GitFileItem> items;

  /// Güvensiz/geçersiz yol içerdiği için atlanan girdiler (örn. `../x`).
  final List<String> invalidEntries;

  const ZipExtractResult({required this.items, required this.invalidEntries});
}

class ZipService {
  // Hariç tutulacak dosya ve klasör kalıpları
  static final List<Pattern> _ignoredPatterns = [
    RegExp(r'(^|/)(__MACOSX)($|/)'),
    RegExp(r'(^|/)(\.DS_Store)$'),
    RegExp(r'(^|/)(Thumbs\.db)$'),
    RegExp(r'(^|/)(\.git)($|/)'),
  ];

  static bool shouldIgnore(String path) {
    for (final pattern in _ignoredPatterns) {
      if (pattern.allMatches(path).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  // ZIP dosyasını bellek içinde aç ve GitFileItem listesine dönüştür
  static ZipExtractResult extractZipBytes({
    required Uint8List zipBytes,
    bool stripSingleRootDir = true,
  }) {
    try {
      return _extract(zipBytes, stripSingleRootDir);
    } on ZipServiceException {
      rethrow;
    } catch (_) {
      throw ZipServiceException(
        'ZIP dosyası okunamadı. Dosya bozuk veya şifreli olabilir.',
      );
    }
  }

  static ZipExtractResult _extract(Uint8List zipBytes, bool stripSingleRootDir) {
    final archive = ZipDecoder().decodeBytes(zipBytes);

    // (normalleştirilmiş ad, dosya) çiftleri
    final names = <String>[];
    final files = <ArchiveFile>[];
    final invalid = <String>[];

    for (final file in archive) {
      if (!file.isFile) continue;

      final name = file.name.replaceAll('\\', '/');
      if (shouldIgnore(name)) continue;

      // Zip Slip benzeri girdiler: mutlak yol, `..` veya geçersiz karakter
      final validation = normalizeAndValidateGitPath(name);
      if (!validation.isValid || name.startsWith('/')) {
        invalid.add(file.name);
        continue;
      }

      names.add(validation.normalizedPath);
      files.add(file);
    }

    if (files.isEmpty) {
      return ZipExtractResult(items: const <GitFileItem>[], invalidEntries: invalid);
    }

    // Tek bir üst klasör olup olmadığını kontrol et (örn: "flutter_app-master/...")
    String? commonRoot;
    if (stripSingleRootDir) {
      final firstSlash = names.first.indexOf('/');
      if (firstSlash != -1) {
        final possibleRoot = names.first.substring(0, firstSlash + 1);
        final allHaveRoot = names.every((n) => n.startsWith(possibleRoot));
        if (allHaveRoot) {
          commonRoot = possibleRoot;
        }
      }
    }

    final items = <GitFileItem>[];
    for (var i = 0; i < files.length; i++) {
      var cleanPath = names[i];
      if (commonRoot != null && cleanPath.startsWith(commonRoot)) {
        cleanPath = cleanPath.substring(commonRoot.length);
      }

      final content = files[i].content as List<int>;
      final bytes = Uint8List.fromList(content);

      items.add(GitFileItem(
        localPath: files[i].name,
        repoPath: cleanPath,
        size: bytes.length,
        bytes: bytes,
        isSelected: true,
        status: GitFileStatus.isNew,
      ));
    }

    return ZipExtractResult(items: items, invalidEntries: invalid);
  }
}

// =============================================================================
// 5. SAĞLAYICILAR (PROVIDERS)
// =============================================================================

// --- lib/providers/app_lock_provider.dart ---
/// Uygulama kilidi durumu. Arka plana gidip [AppSettings.lockTimeoutSeconds]
/// kadar bekleyen uygulama geri dönünce kilitlenir; soğuk açılışta da
/// (kilit açıksa) kilitli başlar.
class AppLockProvider extends ChangeNotifier with WidgetsBindingObserver {
  AppLockProvider({AppLockService? service, StorageService? storage, DateTime Function()? clock})
      : _service = service ?? AppLockService(),
        _storage = storage ?? StorageService(),
        _clock = clock ?? DateTime.now;

  final AppLockService _service;
  final StorageService _storage;
  final DateTime Function() _clock;

  bool _enabled = false;
  bool get enabled => _enabled;

  bool _locked = false;
  bool get locked => _locked;

  int _timeoutSeconds = 30;
  DateTime? _pausedAt;
  bool _observing = false;

  AppLockService get service => _service;

  /// Açılışta bir kez çağrılır. PIN kaydı yoksa kilit etkin sayılmaz.
  Future<void> init(AppSettings settings) async {
    _timeoutSeconds = settings.lockTimeoutSeconds;
    _enabled = settings.appLockEnabled && await _service.hasPin();
    _locked = _enabled; // soğuk açılış
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    notifyListeners();
  }

  /// Ayarlar değişince (zaman aşımı, aç/kapat) çağrılır.
  Future<void> syncSettings(AppSettings settings) async {
    _timeoutSeconds = settings.lockTimeoutSeconds;
    final hasPin = await _service.hasPin();
    final shouldEnable = settings.appLockEnabled && hasPin;
    if (shouldEnable != _enabled) {
      _enabled = shouldEnable;
      if (!_enabled) _locked = false;
      notifyListeners();
    }
  }

  /// PIN doğruysa kilidi açar.
  Future<PinVerifyResult> tryUnlock(String pin) async {
    final result = await _service.verify(pin);
    if (result.ok) {
      _locked = false;
      _pausedAt = null;
      notifyListeners();
    }
    return result;
  }

  /// Kullanıcı kilidi elle devreye almak isterse ("Şimdi kilitle").
  void lockNow() {
    if (!_enabled) return;
    _locked = true;
    notifyListeners();
  }

  /// "PIN'i unuttum" yolu: PIN silinir, kilit kalkar (oturumu kapatma işlemi
  /// çağıran tarafın sorumluluğundadır).
  Future<void> wipe() async {
    await _service.clear();
    _enabled = false;
    _locked = false;
    _pausedAt = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _pausedAt ??= _clock();
        // Otomatik oturum kapatma için son etkinliği kaydet (hata yutulur).
        _storage.touchLastActive(_clock()).catchError((Object _) {});
        break;
      case AppLifecycleState.resumed:
        final since = _pausedAt;
        _pausedAt = null;
        if (_enabled && !_locked && since != null) {
          final away = _clock().difference(since);
          if (away.inSeconds >= _timeoutSeconds) {
            _locked = true;
            notifyListeners();
          }
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

// --- lib/providers/auth_provider.dart ---
class AuthProvider extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  final GitHubService _gitHubService = GitHubService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  String? _token;
  String? get token => _token;

  String? _username;
  String? get username => _username;

  String? _avatarUrl;
  String? get avatarUrl => _avatarUrl;

  String? _authorName;
  String? get authorName => _authorName;

  String? _authorEmail;
  String? get authorEmail => _authorEmail;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // --- GitHub Device Flow durumu ---
  DeviceCodeInfo? _deviceInfo;
  DeviceCodeInfo? get deviceInfo => _deviceInfo;

  bool _deviceCancelled = false;
  bool get isDeviceFlowActive => _deviceInfo != null;

  // Kullanıcının uygulama içinden girdiği Client ID (derlemedekini geçersiz kılar).
  String? _customClientId;

  /// Kullanılacak Client ID: önce kullanıcının girdiği, yoksa derlemedeki.
  String get effectiveClientId {
    final custom = _customClientId;
    if (custom != null && GitHubDeviceFlow.isValidClientId(custom)) return custom;
    return GitHubDeviceFlow.clientId;
  }

  /// Geçerli bir Client ID var mı (derlemeden ya da kullanıcıdan)?
  bool get deviceFlowAvailable => GitHubDeviceFlow.isValidClientId(effectiveClientId);

  /// Derlemede Client ID gömülü değilse kullanıcı kendisi girebilir.
  bool get canEditClientId => !GitHubDeviceFlow.isConfigured;

  /// Client ID'yi doğrulayıp kaydeder. Biçim geçersizse `false` döner.
  Future<bool> setClientId(String raw) async {
    final id = raw.trim();
    if (!GitHubDeviceFlow.isValidClientId(id)) {
      _errorMessage = "Client ID biçimi geçersiz. GitHub OAuth App sayfasındaki Client ID'yi aynen yapıştırın.";
      notifyListeners();
      return false;
    }
    _customClientId = id;
    _errorMessage = null;
    await _storageService.saveClientId(id);
    notifyListeners();
    return true;
  }

  Future<void> clearClientId() async {
    _customClientId = null;
    await _storageService.clearClientId();
    notifyListeners();
  }

  /// "GitHub ile giriş": kod üretir, [onCode] ile arayüze bildirir, kullanıcı
  /// onaylayınca token'ı alıp normal doğrulama akışından geçirir.
  Future<bool> loginWithDeviceFlow({
    String? authorName,
    String? authorEmail,
    void Function(DeviceCodeInfo info)? onCode,
    GitHubDeviceFlow? flow,
    String scope = GitHubDeviceFlow.scope,
  }) async {
    if (_deviceInfo != null) return false;
    _errorMessage = null;
    _deviceCancelled = false;
    final deviceFlow = flow ?? GitHubDeviceFlow(clientIdOverride: effectiveClientId);

    try {
      final info = await deviceFlow.start(scopeOverride: scope);
      _deviceInfo = info;
      notifyListeners();
      onCode?.call(info);

      final token = await deviceFlow.pollForToken(info, isCancelled: () => _deviceCancelled);
      _deviceInfo = null;
      if (token == null) {
        notifyListeners();
        return false;
      }
      return await loginWithToken(token: token, authorName: authorName, authorEmail: authorEmail);
    } on DeviceFlowException catch (e) {
      _deviceInfo = null;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      _deviceInfo = null;
      _errorMessage = 'GitHub girişi sırasında beklenmeyen bir hata oluştu.';
      notifyListeners();
      return false;
    }
  }

  void cancelDeviceFlow() {
    _deviceCancelled = true;
    _deviceInfo = null;
    notifyListeners();
  }

  // Başlangıçta kayıtlı token'ı kontrol et
  Future<void> checkSavedAuth() async {
    _isLoading = true;
    notifyListeners();

    try {
      _customClientId = await _storageService.getClientId();
    } catch (_) {
      _customClientId = null;
    }

    try {
      final savedToken = await _storageService.getToken();
      if (savedToken != null && savedToken.isNotEmpty) {
        _token = savedToken;
        final userData = await _gitHubService.verifyUser(savedToken);
        _username = userData['login'] as String?;
        _avatarUrl = userData['avatar_url'] as String?;

        final userInfo = await _storageService.getUserInfo();
        _authorName = userInfo['name'];
        _authorEmail = userInfo['email'];

        _isAuthenticated = true;
      }
    } on GitHubApiException catch (e) {
      // Token GitHub tarafından reddedildiyse (iptal edilmiş / süresi dolmuş)
      // cihazda saklı kalmasın.
      _isAuthenticated = false;
      _token = null;
      if (e.statusCode == 401) {
        await _storageService.clearAuth();
      }
    } catch (_) {
      // Ağ hatası vb.: oturum bu açılış için kapalı kalır, token korunur
      _isAuthenticated = false;
      _token = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Yeni Token ile Giriş Yap
  Future<bool> loginWithToken({
    required String token,
    String? authorName,
    String? authorEmail,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final cleanToken = token.trim();
      if (!RegExp(r'^[\x21-\x7E]{1,255}$').hasMatch(cleanToken)) {
        _errorMessage =
            'Token geçersiz karakterler içeriyor (boşluk, satır sonu veya özel karakter olamaz).';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      final userData = await _gitHubService.verifyUser(cleanToken);
      _username = userData['login'] as String?;
      _avatarUrl = userData['avatar_url'] as String?;
      _token = cleanToken;
      _authorName = authorName?.trim();
      _authorEmail = authorEmail?.trim();

      await _storageService.saveToken(cleanToken);
      await _storageService.saveUserInfo(
        username: _username ?? '',
        name: _authorName,
        email: _authorEmail,
      );

      _isAuthenticated = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } on GitHubApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Beklenmeyen hata: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Yazar Bilgilerini Güncelle
  Future<void> updateAuthorInfo(String name, String email) async {
    _authorName = name.trim();
    _authorEmail = email.trim();
    await _storageService.saveUserInfo(
      username: _username ?? '',
      name: _authorName,
      email: _authorEmail,
    );
    notifyListeners();
  }

  // Oturumu Kapat
  Future<void> logout() async {
    _deviceCancelled = true;
    _deviceInfo = null;
    await _storageService.clearAllUserData();
    _isAuthenticated = false;
    _token = null;
    _username = null;
    _avatarUrl = null;
    _authorName = null;
    _authorEmail = null;
    _errorMessage = null;
    notifyListeners();
  }
}

// --- lib/providers/repo_provider.dart ---
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

// --- lib/providers/settings_provider.dart ---
/// Uygulama tercihlerinin tek kaynağı. Her değişiklik anında kalıcı yazılır
/// ve dinleyen ekranlar (tema, repo tarayıcı, önizleme...) güncellenir.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider({StorageService? storage}) : _storage = storage ?? StorageService();

  final StorageService _storage;

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  Future<void> load() async {
    try {
      _settings = await _storage.getAppSettings();
    } catch (_) {
      _settings = const AppSettings();
    }
    notifyListeners();
  }

  /// Ayarları değiştirir ve kaydeder.
  Future<void> update(AppSettings Function(AppSettings current) change) async {
    final next = change(_settings);
    _settings = next;
    notifyListeners();
    try {
      await _storage.saveAppSettings(next);
    } catch (_) {
      // Kaydedilemese de oturum boyunca geçerli kalır.
    }
  }

  /// Tüm tercihleri varsayılana döndürür (kilit durumu hariç tutulur: PIN
  /// ayrı yönetilir, burada sessizce kapatılmaz).
  Future<void> resetToDefaults() {
    return update((c) => AppSettings(
          appLockEnabled: c.appLockEnabled,
          lockTimeoutSeconds: c.lockTimeoutSeconds,
        ));
  }

  /// Ayarlarda açıksa hafif titreşim verir.
  void tap() {
    if (_settings.haptics) HapticFeedback.selectionClick();
  }

  void success() {
    if (_settings.haptics) HapticFeedback.mediumImpact();
  }
}

// --- lib/providers/theme_provider.dart ---
class ThemeProvider extends ChangeNotifier {
  final StorageService _storageService = StorageService();

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  String get themeModeString {
    switch (_themeMode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> initTheme() async {
    final modeStr = await _storageService.getThemeMode();
    if (modeStr == 'light') {
      _themeMode = ThemeMode.light;
    } else if (modeStr == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _storageService.saveThemeMode(themeModeString);
    notifyListeners();
  }
}

// --- lib/providers/upload_provider.dart ---
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

// =============================================================================
// 6. BİLEŞENLER (WIDGETS)
// =============================================================================

// --- lib/widgets/action_run_tile.dart ---
class ActionRunTile extends StatelessWidget {
  final ActionRun run;
  final VoidCallback onTap;

  const ActionRunTile({
    super.key,
    required this.run,
    required this.onTap,
  });

  Widget _buildStatusIcon(BuildContext context) {
    final theme = Theme.of(context);

    if (run.isRunning) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    if (run.isSuccess) {
      return const Icon(Icons.check_circle, color: AppTheme.statusNew, size: 22);
    }
    if (run.isFailed || run.isTimedOut || run.isStartupFailure) {
      return Icon(Icons.cancel, color: theme.colorScheme.error, size: 22);
    }
    if (run.isCancelled) {
      return Icon(Icons.block, color: theme.colorScheme.onSurfaceVariant, size: 22);
    }
    return Icon(Icons.hourglass_empty, color: theme.colorScheme.onSurfaceVariant, size: 22);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: onTap,
        leading: _buildStatusIcon(context),
        title: Text(
          run.name,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              run.commitMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  run.headBranch,
                  style: AppTheme.monoStyle.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  shortSha(run.headSha),
                  style: AppTheme.monoStyle.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  run.statusLabel,
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.open_in_new, size: 16),
      ),
    );
  }
}

// --- lib/widgets/app_lock_gate.dart ---
/// `MaterialApp.builder` içinde kullanılır: uygulama kilitliyken içeriğin
/// üstüne PIN ekranını bindirir ve altındaki içeriğe dokunmayı/erişimi keser.
class AppLockGate extends StatelessWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final locked = Provider.of<AppLockProvider>(context).locked;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: locked,
          child: IgnorePointer(ignoring: locked, child: child),
        ),
        if (locked) const Positioned.fill(child: LockScreen()),
      ],
    );
  }
}

// --- lib/widgets/confirm_dialog.dart ---
class ConfirmDialog extends StatelessWidget {
  final String title;
  final String content;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDestructive;

  const ConfirmDialog({
    super.key,
    required this.title,
    required this.content,
    this.confirmLabel = 'Onayla',
    this.cancelLabel = 'Vazgeç',
    this.isDestructive = false,
  });

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String content,
    String confirmLabel = 'Onayla',
    String cancelLabel = 'Vazgeç',
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => ConfirmDialog(
        title: title,
        content: content,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        isDestructive: isDestructive,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: isDestructive
              ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

// --- lib/widgets/empty_state.dart ---
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- lib/widgets/error_view.dart ---
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 56,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- lib/widgets/file_card.dart ---
class FileCard extends StatefulWidget {
  final GitFileItem file;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback onSelectPath;
  final ValueChanged<String> onPathChanged;
  final VoidCallback onDelete;
  final VoidCallback? onToggleSelect;
  final ValueChanged<String>? onSelectSuggestion;

  const FileCard({
    super.key,
    required this.file,
    this.isSelected = false,
    this.selectionMode = false,
    required this.onSelectPath,
    required this.onPathChanged,
    required this.onDelete,
    this.onToggleSelect,
    this.onSelectSuggestion,
  });

  @override
  State<FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<FileCard> {
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: widget.file.repoPath);
  }

  @override
  void didUpdateWidget(covariant FileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  /// Yol; path picker, öneri çipi, kısayol veya metin komutuyla değiştiğinde
  /// ekrandaki alan da güncellenir (imleç konumu korunur).
  void _syncController() {
    final newText = widget.file.repoPath;
    if (_pathController.text == newText) return;

    final oldSelection = _pathController.selection;
    final offset = oldSelection.isValid && oldSelection.end <= newText.length
        ? oldSelection.end
        : newText.length;
    _pathController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  IconData _getFileIcon(String path) {
    if (path.endsWith('.dart')) return Icons.flutter_dash;
    if (path.endsWith('.yaml') || path.endsWith('.yml')) return Icons.settings_suggest;
    if (path.endsWith('.json')) return Icons.data_object;
    if (path.endsWith('.md')) return Icons.article;
    if (path.endsWith('.png') || path.endsWith('.jpg')) return Icons.image;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = widget.file;

    final hasError = file.status == GitFileStatus.conflict;
    final validation = normalizeAndValidateGitPath(file.targetPath);
    final showResolved = !hasError &&
        validation.isValid &&
        validation.normalizedPath != file.repoPath;

    return Dismissible(
      key: ValueKey('file_${file.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => widget.onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.error),
      ),
      child: Card(
        color: widget.isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: widget.isSelected
              ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Satır 1: İkon + Ad + StatusBadge + Sil butonu
              // (uzun basınca seçim modu, seçim modunda dokununca seç/bırak)
              InkWell(
                onLongPress: widget.onToggleSelect,
                onTap: widget.selectionMode ? widget.onToggleSelect : null,
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    if (widget.selectionMode) ...[
                      Icon(
                        widget.isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Icon(
                      _getFileIcon(file.fileName),
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        file.fileName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (file.statusKnown) StatusBadge(status: file.status),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: widget.onDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Listeden çıkar',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              // Satır 2: Boyut bilgisi
              Text(
                file.formattedSize,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              // Satır 3: Hedef Yol Girişi + Yol Seçici Butonu
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _pathController,
                      style: AppTheme.monoStyle.copyWith(fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Hedef Repo Yolu',
                        hintText: 'lib/screens/a.dart',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        errorText: hasError ? (file.conflictMessage ?? 'Çakışma') : null,
                        errorMaxLines: 3,
                        helperText: showResolved ? '→ ${validation.normalizedPath}' : null,
                      ),
                      onChanged: widget.onPathChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: widget.onSelectPath,
                    icon: const Icon(Icons.folder_open, size: 18),
                    tooltip: 'Repo klasörlerinden seç',
                  ),
                ],
              ),
              // Satır 4: Akıllı Öneri / Uyarı
              if (file.needsChoice) ...[
                const SizedBox(height: 6),
                Text(
                  'Birden fazla eşleşme var, seçin.',
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
                ),
              ],
              if (file.suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Eşleşen:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    ...file.suggestions.take(6).map(
                          (path) => InkWell(
                            onTap: () {
                              widget.onPathChanged(path);
                              widget.onSelectSuggestion?.call(path);
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                path,
                                style: AppTheme.monoStyle.copyWith(
                                  fontSize: 10,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// --- lib/widgets/file_tree_view.dart ---
class FileTreeView extends StatelessWidget {
  final List<GitFileItem> files;
  final ValueChanged<int> onToggle;

  const FileTreeView({
    super.key,
    required this.files,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final item = files[index];
        final hasConflict = item.isSelected && item.status == GitFileStatus.conflict;
        return CheckboxListTile(
          value: item.isSelected,
          onChanged: (_) => onToggle(index),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            item.repoPath,
            style: AppTheme.monoStyle.copyWith(
              fontSize: 12,
              color: item.isSelected ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          subtitle: hasConflict
              ? Text(
                  item.conflictMessage ?? 'Çakışma',
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
                )
              : null,
          secondary: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (item.statusKnown) StatusBadge(status: item.status),
              const SizedBox(height: 2),
              Text(
                item.formattedSize,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- lib/widgets/gitpush_logo.dart ---
/// Gitpush logosu: koyu zemin üzerinde yukarı ok (push) ve altında commit
/// düğümü. `assets/icon/icon.svg` ile aynı geometri; ek paket (flutter_svg)
/// gerekmeden `CustomPainter` ile çizilir, her boyutta keskindir.
class GitpushLogo extends StatelessWidget {
  final double size;

  /// Köşe yuvarlaklığı oranı (0.219 ≈ 28/128, ikonla aynı).
  final double radiusFactor;

  const GitpushLogo({super.key, this.size = 72, this.radiusFactor = 0.219});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter(radiusFactor)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final double radiusFactor;

  const _LogoPainter(this.radiusFactor);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 128.0);

    // Düz zemin
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 128, 128),
        Radius.circular(128 * radiusFactor),
      ),
      Paint()..color = const Color(0xFF0E1015),
    );

    // Ok: gövde + uç
    final arrow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFFFFFFF);
    canvas.drawPath(
      Path()
        ..moveTo(64, 88)
        ..lineTo(64, 32),
      arrow,
    );
    canvas.drawPath(
      Path()
        ..moveTo(46, 50)
        ..lineTo(64, 32)
        ..lineTo(82, 50),
      arrow,
    );

    // Commit düğümü: okun çıktığı nokta (zemin renginde ince halka ile ayrılır)
    const node = Offset(64, 92);
    canvas.drawCircle(node, 11, Paint()..color = const Color(0xFF8C9BFF));
    canvas.drawCircle(
      node,
      11,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFF0E1015),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) => oldDelegate.radiusFactor != radiusFactor;
}

// --- lib/widgets/mode_card.dart ---
class ModeCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;
  final String badgeText;
  final VoidCallback onTap;

  const ModeCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.badgeText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: title,
      hint: description,
      child: Card(
        color: theme.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: iconColor, size: 28),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badgeText,
                        style: AppTheme.monoBold.copyWith(
                          fontSize: 10,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'BAŞLAT',
                      style: AppTheme.monoBold.copyWith(
                        fontSize: 12,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- lib/widgets/path_picker_sheet.dart ---
class PathPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> repoTree;
  final String fileName;
  final ValueChanged<String> onPathSelected;

  const PathPickerSheet({
    super.key,
    required this.repoTree,
    required this.fileName,
    required this.onPathSelected,
  });

  @override
  State<PathPickerSheet> createState() => _PathPickerSheetState();
}

class _PathPickerSheetState extends State<PathPickerSheet> {
  final TextEditingController _newFolderController = TextEditingController();
  String _currentDir = '';

  List<String> get _foldersInCurrentDir {
    final Set<String> dirs = {};
    for (final node in widget.repoTree) {
      if (node['type'] == 'tree') {
        final path = node['path'] as String;
        if (_currentDir.isEmpty) {
          final first = path.split('/')[0];
          dirs.add(first);
        } else if (path.startsWith('$_currentDir/')) {
          final sub = path.substring('$_currentDir/'.length);
          final first = sub.split('/')[0];
          dirs.add(first);
        }
      }
    }
    return dirs.toList()..sort();
  }

  void _navigateTo(String folder) {
    setState(() {
      if (_currentDir.isEmpty) {
        _currentDir = folder;
      } else {
        _currentDir = '$_currentDir/$folder';
      }
    });
  }

  void _navigateUp() {
    setState(() {
      final lastSlash = _currentDir.lastIndexOf('/');
      if (lastSlash == -1) {
        _currentDir = '';
      } else {
        _currentDir = _currentDir.substring(0, lastSlash);
      }
    });
  }

  void _confirmPath(String folder) {
    final full = folder.isEmpty ? widget.fileName : '$folder/${widget.fileName}';
    widget.onPathSelected(full);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Tutamaç
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Başlık ve Breadcrumb
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    if (_currentDir.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: _navigateUp,
                      ),
                    Expanded(
                      child: Text(
                        _currentDir.isEmpty ? '/ (Kök Dizin)' : '/$_currentDir',
                        style: AppTheme.monoBold.copyWith(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _confirmPath(_currentDir),
                      child: const Text('Bu Klasöre Koy'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Yeni Klasör Girişi
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newFolderController,
                        style: AppTheme.monoStyle.copyWith(fontSize: 12),
                        decoration: const InputDecoration(
                          hintText: 'Yeni klasör adı...',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final name = _newFolderController.text.trim();
                        if (name.isNotEmpty) {
                          final target = _currentDir.isEmpty ? name : '$_currentDir/$name';
                          _confirmPath(target);
                        }
                      },
                      child: const Text('Oluştur & Seç'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Klasör Listesi
              Expanded(
                child: _foldersInCurrentDir.isEmpty
                    ? Center(
                        child: Text(
                          'Alt klasör bulunamadı',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _foldersInCurrentDir.length,
                        itemBuilder: (context, index) {
                          final folder = _foldersInCurrentDir[index];
                          return ListTile(
                            leading: Icon(
                              Icons.folder,
                              color: theme.colorScheme.primary,
                            ),
                            title: Text(folder, style: AppTheme.monoStyle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _navigateTo(folder),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- lib/widgets/pin_dialogs.dart ---
/// Mevcut PIN'i doğrulatır. Doğruysa true döner.
Future<bool> verifyCurrentPin(BuildContext context, {String title = 'Mevcut PIN'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => _PinDialog(title: title, mode: _PinMode.verify),
  );
  return r ?? false;
}

/// Yeni PIN'i iki kez girdirip kaydeder. Kaydedildiyse true döner.
Future<bool> createNewPin(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => const _PinDialog(title: 'Yeni PIN', mode: _PinMode.create),
  );
  return r ?? false;
}

enum _PinMode { verify, create }

class _PinDialog extends StatefulWidget {
  final String title;
  final _PinMode mode;

  const _PinDialog({required this.title, required this.mode});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  int _reset = 0;
  String? _error;
  String? _first; // create modunda ilk giriş
  bool _busy = false;

  Future<void> _onPin(String pin) async {
    final lock = Provider.of<AppLockProvider>(context, listen: false);
    if (widget.mode == _PinMode.verify) {
      setState(() => _busy = true);
      final r = await lock.service.verify(pin);
      if (!mounted) return;
      if (r.ok) {
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _busy = false;
        _reset++;
        _error = r.isLockedOut ? 'Çok fazla deneme. ${r.lockedFor.inSeconds} sn bekleyin.' : 'Hatalı PIN.';
      });
      return;
    }

    if (_first == null) {
      if (AppLockService.isWeakPin(pin)) {
        setState(() {
          _reset++;
          _error = 'Çok kolay bir PIN (tekrar eden / ardışık). Başka bir tane seçin.';
        });
        return;
      }
      setState(() {
        _first = pin;
        _reset++;
        _error = null;
      });
      return;
    }

    if (pin != _first) {
      setState(() {
        _first = null;
        _reset++;
        _error = 'PIN\'ler eşleşmedi. Baştan başlayın.';
      });
      return;
    }
    setState(() => _busy = true);
    await lock.service.setPin(pin);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.mode == _PinMode.create;
    final subtitle = creating
        ? (_first == null ? '${AppLockService.pinLength} haneli bir PIN seçin' : 'PIN\'i tekrar girin')
        : 'PIN\'inizi girin';
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            SizedBox(
              width: 260,
              child: FittedBox(
                child: PinPad(onCompleted: _onPin, errorText: _error, enabled: !_busy, resetToken: _reset),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
      ],
    );
  }
}

// --- lib/widgets/pin_pad.dart ---
/// 6 haneli PIN girişi: nokta göstergesi + sayısal tuş takımı.
/// [resetToken] değiştiğinde girilen rakamlar temizlenir.
class PinPad extends StatefulWidget {
  final ValueChanged<String> onCompleted;
  final String? errorText;
  final bool enabled;
  final int resetToken;

  const PinPad({
    super.key,
    required this.onCompleted,
    this.errorText,
    this.enabled = true,
    this.resetToken = 0,
  });

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  @override
  void didUpdateWidget(covariant PinPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken) {
      setState(() => _pin = '');
    }
  }

  void _add(String digit) {
    if (!widget.enabled || _pin.length >= AppLockService.pinLength) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += digit);
    if (_pin.length == AppLockService.pinLength) {
      final done = _pin;
      widget.onCompleted(done);
    }
  }

  void _back() {
    if (!widget.enabled || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget key(String label, {VoidCallback? onTap, Widget? child}) {
      return SizedBox(
        width: 72,
        height: 60,
        child: Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.enabled ? onTap : null,
            child: Center(
              child: child ??
                  Text(
                    label,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
            ),
          ),
        ),
      );
    }

    Widget row(List<String> digits) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final d in digits)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: key(d, onTap: () => _add(d)),
              ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < AppLockService.pinLength; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.symmetric(horizontal: 7),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? cs.primary : Colors.transparent,
                  border: Border.all(
                    color: widget.errorText != null ? cs.error : (i < _pin.length ? cs.primary : cs.outline),
                    width: 1.6,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(
          height: 36,
          child: Center(
            child: widget.errorText == null
                ? null
                : Text(
                    widget.errorText!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.error, fontSize: 12.5),
                  ),
          ),
        ),
        row(const ['1', '2', '3']),
        row(const ['4', '5', '6']),
        row(const ['7', '8', '9']),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 84),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: key('0', onTap: () => _add('0')),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: key(
                  '',
                  onTap: _back,
                  child: Icon(Icons.backspace_outlined, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- lib/widgets/progress_sheet.dart ---
class ProgressSheet extends StatelessWidget {
  final String currentStep;
  final int current;
  final int total;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  const ProgressSheet({
    super.key,
    required this.currentStep,
    required this.current,
    required this.total,
    this.error,
    this.onRetry,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double progress = total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;

    return PopScope(
      canPop: false, // Gönderim sırasında geri tuşu engellenir
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (error == null)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 12),
                Text(
                  error == null ? 'Gönderim Sürüyor' : 'Gönderim Başarısız Oldu',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: error != null ? 1.0 : (total > 0 ? progress : null),
              color: error != null ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              currentStep,
              style: AppTheme.monoStyle.copyWith(
                fontSize: 13,
                color: error != null ? theme.colorScheme.error : theme.colorScheme.onSurface,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onCancel != null)
                    TextButton(
                      onPressed: onCancel,
                      child: const Text('İptal'),
                    ),
                  const SizedBox(width: 8),
                  if (onRetry != null)
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Tekrar Dene'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- lib/widgets/quick_command_chips.dart ---
class QuickCommandChips extends StatelessWidget {
  final List<String> shortcuts;
  final ValueChanged<String> onSelect;
  final VoidCallback onAddShortcut;

  const QuickCommandChips({
    super.key,
    required this.shortcuts,
    required this.onSelect,
    required this.onAddShortcut,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          ...shortcuts.map((shortcut) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(shortcut),
                onPressed: () => onSelect(shortcut),
                avatar: const Icon(Icons.bolt, size: 14),
              ),
            );
          }),
          ActionChip(
            label: const Text('+ Kısayol'),
            onPressed: onAddShortcut,
            avatar: const Icon(Icons.add, size: 14),
          ),
        ],
      ),
    );
  }
}

// --- lib/widgets/repo_branch_chip.dart ---
class RepoBranchChip extends StatelessWidget {
  final String? repoFullName;
  final String? branchName;
  final VoidCallback onTap;

  const RepoBranchChip({
    super.key,
    required this.repoFullName,
    required this.branchName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = repoFullName != null && repoFullName!.isNotEmpty;

    return Semantics(
      button: true,
      label: 'Repository ve branch değiştir',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.source_outlined,
                  size: 16,
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    isSelected ? '$repoFullName · $branchName' : 'Depo seçiniz',
                    style: AppTheme.monoBold.copyWith(
                      fontSize: 12,
                      color: isSelected ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- lib/widgets/section_card.dart ---
class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık ve sağ eylem dar ekranda sığmazsa alt satıra kayar.
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

// --- lib/widgets/send_bottom_bar.dart ---
class SendBottomBar extends StatelessWidget {
  final String summaryText;
  final String buttonLabel;
  final VoidCallback? onButtonPressed;
  final bool isLoading;

  const SendBottomBar({
    super.key,
    required this.summaryText,
    required this.buttonLabel,
    required this.onButtonPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                summaryText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: isLoading ? null : onButtonPressed,
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// --- lib/widgets/status_badge.dart ---
class StatusBadge extends StatelessWidget {
  final GitFileStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (status) {
      case GitFileStatus.isNew:
        bg = AppTheme.statusNew.withValues(alpha: 0.15);
        fg = AppTheme.statusNew;
        icon = Icons.add_circle_outline;
        label = 'Yeni';
        break;
      case GitFileStatus.update:
        bg = AppTheme.statusUpdate.withValues(alpha: 0.15);
        fg = AppTheme.statusUpdate;
        icon = Icons.sync;
        label = 'Güncelleme';
        break;
      case GitFileStatus.delete:
        bg = AppTheme.statusDelete.withValues(alpha: 0.15);
        fg = AppTheme.statusDelete;
        icon = Icons.remove_circle_outline;
        label = 'Silinecek';
        break;
      case GitFileStatus.newFolder:
        bg = AppTheme.statusNewFolder.withValues(alpha: 0.15);
        fg = AppTheme.statusNewFolder;
        icon = Icons.create_new_folder_outlined;
        label = 'Yeni Klasör';
        break;
      case GitFileStatus.unchanged:
        bg = Colors.grey.withValues(alpha: 0.15);
        fg = Colors.grey;
        icon = Icons.check;
        label = 'Değişmedi';
        break;
      case GitFileStatus.conflict:
        bg = AppTheme.statusDelete.withValues(alpha: 0.15);
        fg = AppTheme.statusDelete;
        icon = Icons.error_outline;
        label = 'Çakışma';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 7. EKRANLAR (SCREENS)
// =============================================================================

// --- lib/screens/actions_screen.dart ---
class ActionsScreen extends StatefulWidget {
  /// Sekme şu an görünür mü? (MainShell IndexedStack tüm sekmeleri baştan kurar.)
  final bool isActive;

  const ActionsScreen({super.key, this.isActive = true});

  @override
  State<ActionsScreen> createState() => _ActionsScreenState();
}

class _ActionsScreenState extends State<ActionsScreen> {
  final GitHubService _gitHubService = GitHubService();
  List<ActionRun> _runs = [];
  bool _isLoading = false;
  String? _error;
  String? _loadedKey;
  bool _fetchScheduled = false;

  @override
  void didUpdateWidget(covariant ActionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sekmeye geçince yenile
    if (widget.isActive && !oldWidget.isActive) {
      _fetchRuns();
    }
  }

  Future<void> _fetchRuns() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repo = Provider.of<RepoProvider>(context, listen: false);
    final selected = repo.selectedRepo;
    final token = auth.token;
    if (token == null || selected == null) return;

    _loadedKey = _keyFor(repo);
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final list = await _gitHubService.getActionRuns(token, selected.owner, selected.name);
      if (!mounted) return;
      setState(() => _runs = list);
    } on GitHubApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _runs = [];
        _error = 'İş akışları alınamadı: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _runs = [];
        _error = 'İş akışları alınamadı: $e';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _keyFor(RepoProvider repo) =>
      '${repo.selectedRepo?.fullName}#${repo.selectedBranch}#${repo.treeRevision}';

  Future<void> _triggerWorkflow() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repo = Provider.of<RepoProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final selected = repo.selectedRepo;
    final token = auth.token;
    if (token == null || selected == null) return;

    try {
      await _gitHubService.triggerWorkflow(
        token,
        selected.owner,
        selected.name,
        'build.yml',
        repo.selectedBranch ?? 'main',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Workflow (build.yml) tetiklendi!')),
      );
      _fetchRuns();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Tetikleme hatası: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = Provider.of<RepoProvider>(context);

    if (repo.selectedRepo == null) {
      return const EmptyState(
        icon: Icons.bolt,
        message: 'GitHub Actions görüntülemek için bir repo seçiniz.',
      );
    }

    // Repo/dal değişti veya push sonrası ağaç yenilendi: görünürse yeniden yükle.
    if (widget.isActive && !_isLoading && !_fetchScheduled && _loadedKey != _keyFor(repo)) {
      _fetchScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchScheduled = false;
        if (mounted) _fetchRuns();
      });
    }

    if (_isLoading && _runs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _fetchRuns);
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _triggerWorkflow,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Workflow Başlat'),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchRuns,
        // Boş durum da kaydırılabilir olmalı ki çek-yenile çalışsın.
        child: _runs.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.play_circle_outline,
                    message: 'Bu depoda henüz GitHub Actions çalıştırması bulunmuyor.',
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
                itemCount: _runs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final run = _runs[index];
                  final fallback = repo.selectedRepo == null
                      ? ''
                      : 'https://github.com/${repo.selectedRepo!.owner}/${repo.selectedRepo!.name}/actions';
                  return ActionRunTile(
                    run: run,
                    onTap: () => openExternalUrl(
                      context,
                      run.htmlUrl.isNotEmpty ? run.htmlUrl : fallback,
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// --- lib/screens/commits_screen.dart ---
/// Seçili dalın (veya tek bir dosyanın) commit geçmişi. Sayfa sayfa yüklenir.
class CommitsScreen extends StatefulWidget {
  /// Doluysa yalnızca bu yolu değiştiren commit'ler listelenir.
  final String? path;

  const CommitsScreen({super.key, this.path});

  @override
  State<CommitsScreen> createState() => _CommitsScreenState();
}

class _CommitsScreenState extends State<CommitsScreen> {
  static const int _pageSize = 30;

  final List<PathCommitInfo> _items = [];
  bool _loading = true;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await repoProv.loadCommits(token, path: widget.path, page: _page);
      if (!mounted) return;
      setState(() {
        _items.addAll(list);
        _hasMore = list.length >= _pageSize;
        _page++;
      });
    } on GitHubApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Geçmiş alınamadı: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _ago(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'az önce';
    if (diff.inHours < 1) return '${diff.inMinutes} dk önce';
    if (diff.inDays < 1) return '${diff.inHours} sa önce';
    if (diff.inDays < 30) return '${diff.inDays} gün önce';
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}.${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final branch = Provider.of<RepoProvider>(context).selectedBranch ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.path == null ? 'Commit geçmişi' : widget.path!.split('/').last),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.path ?? branch,
                style: AppTheme.monoStyle.copyWith(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
      body: _items.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty && _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('Tekrar dene')),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _items.length + 1,
                  separatorBuilder: (_, __) => const Divider(indent: 16),
                  itemBuilder: (context, i) {
                    if (i == _items.length) {
                      if (_items.isEmpty) {
                        return const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Commit bulunamadı.')));
                      }
                      if (_error != null) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                        );
                      }
                      if (!_hasMore) return const SizedBox(height: 8);
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: _loading
                              ? const CircularProgressIndicator()
                              : OutlinedButton(onPressed: _load, child: const Text('Daha fazla yükle')),
                        ),
                      );
                    }
                    final c = _items[i];
                    return ListTile(
                      leading: Icon(Icons.commit, color: theme.colorScheme.primary),
                      title: Text(c.title.isEmpty ? '(mesaj yok)' : c.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${c.authorName ?? 'bilinmiyor'} · ${_ago(c.date)} · ${shortSha(c.sha)}',
                        style: AppTheme.monoStyle.copyWith(fontSize: 11),
                      ),
                      onTap: c.htmlUrl == null ? null : () => openExternalUrl(context, c.htmlUrl!),
                      onLongPress: () => RepoActions.copy(context, c.sha, 'SHA kopyalandı.'),
                    );
                  },
                ),
    );
  }
}

// --- lib/screens/file_detail_screen.dart ---
/// Tek bir dosyanın ayrıntıları: bilgi, son commit, içerik önizlemesi ve
/// işlemler (kopyala, GitHub'da aç, taşı/yeniden adlandır, sil).
class FileDetailScreen extends StatefulWidget {
  final RepoEntry entry;

  const FileDetailScreen({super.key, required this.entry});

  @override
  State<FileDetailScreen> createState() => _FileDetailScreenState();
}

class _FileDetailScreenState extends State<FileDetailScreen> {
  static const int _maxImageBytes = 4 * 1024 * 1024;
  static const int _maxRenderedLines = 3000;

  late final PreviewKind _kind = previewKindFor(widget.entry.name);

  bool _loading = true;
  String? _error;
  String? _notice; // önizleme yok açıklaması (sınır, ikili dosya...)
  Uint8List? _imageBytes;
  String? _text;
  int _totalLines = 0;
  bool? _wrap;

  PathCommitInfo? _commit;
  bool _commitLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadContent();
      _loadCommit();
    });
  }

  String? get _token => Provider.of<AuthProvider>(context, listen: false).token;

  Future<void> _loadContent() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false).settings;
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final token = _token;
    final entry = widget.entry;

    if (entry.isSubmodule) {
      setState(() {
        _loading = false;
        _notice = 'Bu bir alt modül (submodule); içeriği başka bir depoda tutulur.';
      });
      return;
    }
    if (_kind == PreviewKind.binary) {
      setState(() {
        _loading = false;
        _notice = 'İkili dosya (${formatBytes(entry.size)}); önizleme desteklenmiyor.';
      });
      return;
    }

    final limit = _kind == PreviewKind.image ? _maxImageBytes : settings.previewMaxKb * 1024;
    if (entry.size > limit) {
      setState(() {
        _loading = false;
        _notice = 'Dosya (${formatBytes(entry.size)}) önizleme sınırından büyük '
            '(${formatBytes(limit)}). Ayarlardan sınırı yükseltebilir veya GitHub\'da açabilirsiniz.';
      });
      return;
    }
    if (token == null) return;

    try {
      final bytes = await repoProv.readFileBytes(token, entry, maxBytes: limit);
      if (!mounted) return;

      if (_kind == PreviewKind.image) {
        setState(() {
          _imageBytes = bytes;
          _loading = false;
        });
        return;
      }

      // Metin: NUL bayt içeriyorsa veya UTF-8 değilse ikili say.
      if (bytes.contains(0)) {
        setState(() {
          _loading = false;
          _notice = 'Dosya ikili içerik gibi görünüyor; önizleme gösterilmiyor.';
        });
        return;
      }
      String decoded;
      try {
        decoded = utf8.decode(bytes);
      } on FormatException {
        setState(() {
          _loading = false;
          _notice = 'Dosya UTF-8 metin değil; önizleme gösterilmiyor.';
        });
        return;
      }
      if (decoded.startsWith('﻿')) decoded = decoded.substring(1);
      final lines = decoded.split('\n');
      setState(() {
        _text = decoded;
        _totalLines = decoded.isEmpty ? 0 : (decoded.endsWith('\n') ? lines.length - 1 : lines.length);
        _loading = false;
      });
    } on GitHubApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'İçerik alınamadı: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadCommit() async {
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final token = _token;
    if (token == null) return;
    try {
      final c = await repoProv.lastCommitFor(token, widget.entry.path);
      if (!mounted) return;
      setState(() {
        _commit = c;
        _commitLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _commitLoading = false);
    }
  }

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  Future<void> _delete() async {
    final done = await RepoActions.deleteEntries(context, [widget.entry]);
    if (done && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _edit() async {
    final text = _text;
    if (text == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FileEditorScreen(path: widget.entry.path, initialText: text, mode: widget.entry.mode),
      ),
    );
    if (saved == true && mounted) Navigator.of(context).pop(true);
  }

  void _history() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommitsScreen(path: widget.entry.path)));
  }

  Future<void> _move() async {
    final newPath = await RepoActions.renameOrMove(context, widget.entry);
    if (newPath != null && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repoProv = Provider.of<RepoProvider>(context);
    final settings = Provider.of<SettingsProvider>(context).settings;
    final repo = repoProv.selectedRepo;
    final branch = repoProv.selectedBranch;
    final entry = widget.entry;
    final visual = fileVisualFor(entry.extension);
    final wrap = _wrap ?? settings.previewWrapLines;

    return Scaffold(
      appBar: AppBar(
        title: Text(entry.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (_text != null)
            IconButton(
              tooltip: 'Düzenle',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
          if (_text != null)
            IconButton(
              tooltip: 'İçeriği kopyala',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () => RepoActions.copy(context, _text!, 'İçerik kopyalandı.'),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'github':
                  if (repo != null && branch != null) {
                    openExternalUrl(context, RepoActions.githubUrlFor(repo, branch, entry));
                  }
                  break;
                case 'path':
                  RepoActions.copy(context, entry.path, 'Yol kopyalandı.');
                  break;
                case 'raw':
                  if (repo != null && branch != null) {
                    RepoActions.copy(context, RepoActions.rawUrlFor(repo, branch, entry), 'Ham bağlantı kopyalandı.');
                  }
                  break;
                case 'sha':
                  if (entry.sha != null) RepoActions.copy(context, entry.sha!, 'SHA kopyalandı.');
                  break;
                case 'history':
                  _history();
                  break;
                case 'move':
                  _move();
                  break;
                case 'delete':
                  _delete();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'history', child: _MenuRow(Icons.history, 'Dosya geçmişi')),
              const PopupMenuItem(value: 'github', child: _MenuRow(Icons.open_in_new, 'GitHub\'da aç')),
              const PopupMenuItem(value: 'path', child: _MenuRow(Icons.copy, 'Yolu kopyala')),
              const PopupMenuItem(value: 'raw', child: _MenuRow(Icons.link, 'Ham bağlantıyı kopyala')),
              if (entry.sha != null) const PopupMenuItem(value: 'sha', child: _MenuRow(Icons.tag, 'SHA kopyala')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'move', child: _MenuRow(Icons.drive_file_move_outlined, 'Taşı / yeniden adlandır')),
              const PopupMenuItem(
                value: 'delete',
                child: _MenuRow(Icons.delete_outline, 'Dosyayı sil', color: AppTheme.statusDelete),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Başlık kartı
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: visual.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(visual.icon, color: visual.color, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.path,
                          style: AppTheme.monoStyle.copyWith(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Ayrıntılar
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  _InfoTile(label: 'Boyut', value: '${formatBytes(entry.size)} (${entry.size} bayt)'),
                  if (_totalLines > 0) _InfoTile(label: 'Satır', value: '$_totalLines'),
                  _InfoTile(label: 'Dal', value: branch ?? '-'),
                  if (entry.mode != null) _InfoTile(label: 'Kip', value: _modeLabel(entry.mode!)),
                  if (entry.sha != null)
                    _InfoTile(
                      label: 'SHA',
                      value: shortSha(entry.sha!, length: 12),
                      onTap: () => RepoActions.copy(context, entry.sha!, 'SHA kopyalandı.'),
                    ),
                  _InfoTile(
                    label: 'Son değişiklik',
                    value: _commitLoading
                        ? 'Yükleniyor...'
                        : _commit == null
                            ? 'Bilinmiyor'
                            : '${_commit!.title}${_commit!.date != null ? '\n${_fmtDate(_commit!.date!)}' : ''}'
                                '${_commit!.authorName != null ? ' · ${_commit!.authorName}' : ''}',
                    onTap: _commit?.htmlUrl == null ? null : () => openExternalUrl(context, _commit!.htmlUrl!),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Önizleme
          _buildPreview(theme, wrap),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _move,
                  icon: const Icon(Icons.drive_file_move_outlined, size: 18),
                  label: const Text('Taşı / Ad'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.statusDelete),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Sil'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _modeLabel(String mode) {
    switch (mode) {
      case '100644':
        return '100644 (normal dosya)';
      case '100755':
        return '100755 (çalıştırılabilir)';
      case '120000':
        return '120000 (sembolik bağlantı)';
      case '160000':
        return '160000 (alt modül)';
      default:
        return mode;
    }
  }

  Widget _buildPreview(ThemeData theme, bool wrap) {
    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadContent();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Tekrar dene'),
            ),
          ],
        ),
      );
    } else if (_notice != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.visibility_off_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(_notice!, style: theme.textTheme.bodyMedium)),
          ],
        ),
      );
    } else if (_imageBytes != null) {
      body = ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        child: Container(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          constraints: const BoxConstraints(maxHeight: 420),
          child: InteractiveViewer(
            maxScale: 6,
            child: Image.memory(
              _imageBytes!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Görsel çözülemedi.')),
              ),
            ),
          ),
        ),
      );
    } else if (_text != null) {
      body = _buildText(theme, wrap);
    } else {
      body = const SizedBox.shrink();
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Text('ÖNİZLEME', style: AppTheme.monoBold.copyWith(fontSize: 11, color: theme.colorScheme.primary)),
                const Spacer(),
                if (_text != null)
                  TextButton.icon(
                    onPressed: () => setState(() => _wrap = !wrap),
                    icon: Icon(wrap ? Icons.wrap_text : Icons.notes, size: 16),
                    label: Text(wrap ? 'Kaydır: açık' : 'Kaydır: kapalı', style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          const Divider(),
          body,
        ],
      ),
    );
  }

  Widget _buildText(ThemeData theme, bool wrap) {
    final settings = Provider.of<SettingsProvider>(context).settings;
    final fontSize = settings.previewFontSize;
    final style = AppTheme.monoStyle.copyWith(fontSize: fontSize, height: 1.45, color: theme.colorScheme.onSurface);
    final numStyle = style.copyWith(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7));

    if (_text!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Dosya boş.'),
      );
    }

    var lines = _text!.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines = lines.sublist(0, lines.length - 1);
    final truncated = lines.length > _maxRenderedLines;
    if (truncated) lines = lines.sublist(0, _maxRenderedLines);

    final gutterWidth = (lines.length.toString().length * (fontSize * 0.62)) + 8;
    final numbers = List<String>.generate(lines.length, (i) => '${i + 1}').join('\n');
    final content = lines.join('\n');

    final code = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: gutterWidth,
          padding: const EdgeInsets.only(left: 4, right: 4, top: 12, bottom: 12),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          child: Text(numbers, textAlign: TextAlign.right, style: numStyle),
        ),
        const SizedBox(width: 10),
        if (wrap)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 12, right: 12),
              child: SelectableText(content, style: style),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 12, right: 16),
            child: SelectableText(content, style: style),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wrap)
          code
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: code,
          ),
        if (truncated)
          Container(
            color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
            padding: const EdgeInsets.all(12),
            child: Text(
              'İlk $_maxRenderedLines satır gösteriliyor (toplam $_totalLines). '
              'Tamamını kopyalamak için üstteki "İçeriği kopyala" düğmesini veya GitHub\'ı kullanın.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MenuRow(this.icon, this.label, {this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _InfoTile({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onTap != null ? theme.colorScheme.primary : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- lib/screens/file_editor_screen.dart ---
/// Metin dosyasını uygulama içinde düzenleyip tek commit ile kaydeder; ya da
/// yeni dosya oluşturur ([isNew]). Kayıttan önce gizli bilgi taraması yapılır.
class FileEditorScreen extends StatefulWidget {
  final String path;
  final String initialText;
  final bool isNew;
  final String? mode;

  const FileEditorScreen({
    super.key,
    required this.path,
    this.initialText = '',
    this.isNew = false,
    this.mode,
  });

  @override
  State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  late final TextEditingController _pathCtrl = TextEditingController(text: widget.path);
  late final TextEditingController _textCtrl = TextEditingController(text: widget.initialText);
  late final TextEditingController _msgCtrl = TextEditingController(
    text: widget.isNew ? 'feat: add ${widget.path.split('/').last} via Gitpush' : 'chore: update ${widget.path} via Gitpush',
  );
  bool _saving = false;
  String? _error;

  bool get _dirty => widget.isNew ? _textCtrl.text.isNotEmpty : _textCtrl.text != widget.initialText;

  @override
  void dispose() {
    _pathCtrl.dispose();
    _textCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Değişiklikler atılsın mı?'),
        content: const Text('Kaydedilmemiş değişiklikler kaybolacak.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Düzenlemeye dön')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('At')),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _save() async {
    if (_saving) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final upload = Provider.of<UploadProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final token = auth.token;
    final repo = repoProv.selectedRepo;
    final branch = repoProv.selectedBranch;
    if (token == null || repo == null || branch == null) return;

    final path = _pathCtrl.text.trim();
    final message = _msgCtrl.text.trim().isEmpty ? 'chore: update $path via Gitpush' : _msgCtrl.text.trim();

    if (widget.isNew) {
      final problem = repoProv.newFilePathProblem(path);
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
    } else if (!_dirty) {
      setState(() => _error = 'Değişiklik yok.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final bytes = Uint8List.fromList(utf8.encode(_textCtrl.text));
      final hasAuthor = (auth.authorName ?? '').trim().isNotEmpty && (auth.authorEmail ?? '').trim().isNotEmpty;
      final sha = await repoProv.saveFile(
        token: token,
        path: path,
        bytes: bytes,
        message: message,
        mode: widget.mode,
        authorName: hasAuthor ? auth.authorName : null,
        authorEmail: hasAuthor ? auth.authorEmail : null,
      );
      await upload.recordExternalCommit(
        owner: repo.owner,
        repo: repo.name,
        branch: branch,
        commitMessage: message,
        commitSha: sha,
        filesCount: 1,
      );
      settings.success();
      messenger.showSnackBar(SnackBar(content: Text('Kaydedildi (${shortSha(sha)}).')));
      navigator.pop(true);
    } on GitHubApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Beklenmeyen hata: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontSize = Provider.of<SettingsProvider>(context).settings.previewFontSize;

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNew ? 'Yeni dosya' : 'Düzenle'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check, size: 18),
                label: const Text('Kaydet'),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _pathCtrl,
                    enabled: widget.isNew && !_saving,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Dosya yolu', isDense: true),
                    style: AppTheme.monoStyle.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _msgCtrl,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Commit mesajı', isDense: true),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12.5)),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: TextField(
                controller: _textCtrl,
                enabled: !_saving,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                style: AppTheme.monoStyle.copyWith(fontSize: fontSize, height: 1.4),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.all(16),
                  hintText: 'İçerik...',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- lib/screens/history_screen.dart ---
/// MainShell zaten AppBar sağlar; bu ekran kendi Scaffold/AppBar'ını taşımaz.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<UploadProvider>(context, listen: false).loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final upload = Provider.of<UploadProvider>(context);
    final history = upload.historyItems;

    if (history.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        message: 'Henüz bu uygulamadan bir gönderim yapılmadı.',
      );
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8, top: 4),
            child: TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Geçmişi Temizle'),
              onPressed: () async {
                final ok = await ConfirmDialog.show(
                  context,
                  title: 'Geçmiş Temizlensin mi?',
                  content: 'Tüm yerel gönderim kayıtları silinecek.',
                  isDestructive: true,
                );
                if (ok) upload.clearHistory();
              },
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: history.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = history[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.commit, color: AppTheme.statusNew),
                  title: Text(item.commitMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${item.repoFullName} (${item.branch}) · ${shortSha(item.commitSha)}',
                    style: AppTheme.monoStyle.copyWith(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.open_in_browser, size: 18),
                  onTap: () => openExternalUrl(context, item.commitUrl),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// --- lib/screens/lock_screen.dart ---
/// Uygulama kilitliyken tüm içeriğin üstünü örten PIN ekranı.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  int _resetToken = 0;
  String? _error;
  bool _busy = false;
  bool _showForgot = false;
  Duration _lockLeft = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refreshLockout();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLockout() async {
    final lock = Provider.of<AppLockProvider>(context, listen: false);
    final left = await lock.service.lockoutRemaining();
    if (!mounted) return;
    _startCountdown(left);
  }

  void _startCountdown(Duration left) {
    _timer?.cancel();
    setState(() => _lockLeft = left);
    if (left <= Duration.zero) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final next = _lockLeft - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        t.cancel();
        setState(() {
          _lockLeft = Duration.zero;
          _error = null;
          _resetToken++;
        });
      } else {
        setState(() => _lockLeft = next);
      }
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m > 0 ? '$m dk ${s.toString().padLeft(2, '0')} sn' : '$s sn';
  }

  Future<void> _onPin(String pin) async {
    if (_busy || _lockLeft > Duration.zero) return;
    setState(() => _busy = true);
    final lock = Provider.of<AppLockProvider>(context, listen: false);
    final result = await lock.tryUnlock(pin);
    if (!mounted) return;
    if (result.ok) return; // kilit kalktı; bu ekran ağaçtan çıkar
    setState(() {
      _busy = false;
      _resetToken++;
      if (result.isLockedOut) {
        _error = 'Çok fazla hatalı deneme.';
      } else {
        final left = AppLockService.freeAttempts - result.failedAttempts;
        _error = left > 0 ? 'Hatalı PIN. Kalan deneme: $left' : 'Hatalı PIN.';
      }
    });
    if (result.isLockedOut) _startCountdown(result.lockedFor);
  }

  Future<void> _wipeAndLogout() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repo = Provider.of<RepoProvider>(context, listen: false);
    final upload = Provider.of<UploadProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final lock = Provider.of<AppLockProvider>(context, listen: false);

    repo.reset();
    upload.resetAll();
    await auth.logout();
    await settings.update((c) => c.copyWith(appLockEnabled: false));
    await lock.wipe();
    appNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const SetupScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = Provider.of<AuthProvider>(context);
    final lockedOut = _lockLeft > Duration.zero;

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GitpushLogo(size: 72),
                  const SizedBox(height: 16),
                  Text('Gitpush kilitli', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    auth.username != null ? '@${auth.username} için PIN girin' : 'Devam etmek için PIN girin',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  if (lockedOut) ...[
                    Icon(Icons.timer_outlined, color: theme.colorScheme.error, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      'Çok fazla hatalı deneme.\n${_fmt(_lockLeft)} sonra tekrar deneyin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 16),
                  ] else
                    PinPad(
                      onCompleted: _onPin,
                      errorText: _error,
                      enabled: !_busy,
                      resetToken: _resetToken,
                    ),
                  const SizedBox(height: 8),
                  if (!_showForgot)
                    TextButton(
                      onPressed: () => setState(() => _showForgot = true),
                      child: const Text('PIN\'imi unuttum'),
                    )
                  else
                    Card(
                      color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              'PIN geri alınamaz. Sıfırlamak için oturum kapatılır; kayıtlı token, '
                              'yazar bilgileri ve geçmiş bu cihazdan silinir. Tekrar giriş yapmanız gerekir.',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => setState(() => _showForgot = false),
                                    child: const Text('Vazgeç'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                                    onPressed: _wipeAndLogout,
                                    child: const Text('Sıfırla'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- lib/screens/main_shell.dart ---
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const List<String> _titles = [
    'Gönder',
    'Repo Tarayıcı',
    'GitHub Actions',
    'Geçmiş',
    'Ayarlar',
  ];

  // Telefon: alt gezinme çubuğu (mevcut davranış).
  static const List<NavigationDestination> _barDestinations = [
    NavigationDestination(
      icon: Icon(Icons.upload_file_outlined),
      selectedIcon: Icon(Icons.upload_file),
      label: 'Gönder',
    ),
    NavigationDestination(
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder),
      label: 'Repo',
    ),
    NavigationDestination(
      icon: Icon(Icons.bolt_outlined),
      selectedIcon: Icon(Icons.bolt),
      label: 'Actions',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history),
      label: 'Geçmiş',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Ayarlar',
    ),
  ];

  // Tablet: yan gezinme çubuğu (NavigationRail), aynı sıra ve etiketlerle.
  static const List<NavigationRailDestination> _railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.upload_file_outlined),
      selectedIcon: Icon(Icons.upload_file),
      label: Text('Gönder'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder),
      label: Text('Repo'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.bolt_outlined),
      selectedIcon: Icon(Icons.bolt),
      label: Text('Actions'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history),
      label: Text('Geçmiş'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: Text('Ayarlar'),
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final repo = Provider.of<RepoProvider>(context, listen: false);
      if (auth.token != null && repo.repositories.isEmpty) {
        repo.loadRepositories(auth.token!);
      }
    });
  }

  void _openRepoPicker() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RepoPickerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repoProvider = Provider.of<RepoProvider>(context);
    final isTablet = Responsive.isTabletSize(MediaQuery.sizeOf(context));

    final content = IndexedStack(
      index: _currentIndex,
      children: [
        const SendScreen(),
        const RepoBrowserScreen(),
        ActionsScreen(isActive: _currentIndex == 2),
        const HistoryScreen(),
        const SettingsScreen(),
      ],
    );

    final appBar = AppBar(
      title: Text(_titles[_currentIndex]),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: RepoBranchChip(
              repoFullName: repoProvider.selectedRepo?.fullName,
              branchName: repoProvider.selectedBranch,
              onTap: _openRepoPicker,
            ),
          ),
        ),
      ],
    );

    if (isTablet) {
      // 11 inç ve benzeri tabletler için: sabit alt bar yerine yan gezinme
      // çubuğu ve içeriğe daha geniş bir maksimum genişlik.
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
              },
              labelType: NavigationRailLabelType.all,
              destinations: _railDestinations,
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: content,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Telefon: mevcut düzen (alt gezinme çubuğu, dar içerik alanı).
    return Scaffold(
      appBar: appBar,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: content,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: _barDestinations,
      ),
    );
  }
}

// --- lib/screens/multi_file_screen.dart ---
class MultiFileScreen extends StatefulWidget {
  const MultiFileScreen({super.key});

  @override
  State<MultiFileScreen> createState() => _MultiFileScreenState();
}

class _MultiFileScreenState extends State<MultiFileScreen> {
  final StorageService _storageService = StorageService();
  List<String> _shortcuts = [];

  // Seçim modu: kartlara uzun basınca açılır; kısayol / kaldırma seçililere uygulanır.
  final Set<int> _selectedIds = <int>{};
  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  int _lastTreeRevision = -1;

  @override
  void initState() {
    super.initState();
    _loadShortcuts();
  }

  Future<void> _loadShortcuts() async {
    final list = await _storageService.getShortcuts();
    if (!mounted) return;
    setState(() => _shortcuts = list);
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final List<GitFileItem> items = [];
      for (final f in result.files) {
        final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
        if (bytes != null) {
          items.add(GitFileItem(
            localPath: f.path ?? f.name,
            repoPath: f.name,
            sourceName: f.name,
            size: f.size,
            bytes: bytes,
            status: GitFileStatus.isNew,
          ));
        }
      }

      if (!mounted) return;
      Provider.of<UploadProvider>(context, listen: false).addMultiFiles(items);
    }
  }

  void _showAddShortcutDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni Kısayol Ekle'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Klasör yolu (Örn: lib/core/)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () async {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                final updated = [..._shortcuts, val];
                await _storageService.saveShortcuts(updated);
                if (!mounted) return;
                setState(() => _shortcuts = updated);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _showTextCommandDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Metinle Komut Gir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Formatlar:\n• dosya=hedef/yol\n• klasör/: dosya1.dart dosya2.dart',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 5,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'a.dart=lib/screens/a.dart\nlib/models/: c.dart d.dart',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              Provider.of<UploadProvider>(context, listen: false).parseAndApplyTextCommands(ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
  }

  void _openPathPickerForFile(GitFileItem file) {
    final repoProvider = Provider.of<RepoProvider>(context, listen: false);
    final uploadProvider = Provider.of<UploadProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => PathPickerSheet(
        repoTree: repoProvider.currentTree,
        fileName: file.fileName,
        onPathSelected: (selected) {
          uploadProvider.updateMultiFilePathById(file.id, selected);
        },
      ),
    );
  }

  void _toggleSelection(int id) {
    setState(() {
      if (!_selectedIds.remove(id)) {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _clearAll(UploadProvider upload) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Tümü kaldırılsın mı?',
      content: '${upload.multiFiles.length} dosya listeden kaldırılacak.',
      isDestructive: true,
      confirmLabel: 'Tümünü Kaldır',
    );
    if (!ok || !mounted) return;

    final removed = upload.clearMultiFiles();
    setState(_selectedIds.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${removed.length} dosya kaldırıldı'),
        action: SnackBarAction(
          label: 'Geri Al',
          onPressed: () => upload.restoreMultiFiles(removed),
        ),
      ),
    );
  }

  void _removeSelected(UploadProvider upload) {
    final ids = Set<int>.from(_selectedIds);
    final removed = upload.multiFiles.where((f) => ids.contains(f.id)).toList();
    upload.removeMultiFilesByIds(ids);
    setState(_selectedIds.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${removed.length} dosya kaldırıldı'),
        action: SnackBarAction(
          label: 'Geri Al',
          onPressed: () => upload.restoreMultiFiles(removed),
        ),
      ),
    );
  }

  Future<void> _goToPreview() async {
    final upload = Provider.of<UploadProvider>(context, listen: false);
    if (upload.multiFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir dosya ekleyin.')),
      );
      return;
    }

    await PreviewScreen.open(
      context,
      source: PreviewSource.multi,
      commitMessage: Provider.of<SettingsProvider>(context, listen: false).settings.defaultCommitMessage.isNotEmpty
          ? Provider.of<SettingsProvider>(context, listen: false).settings.defaultCommitMessage
          : 'Gitpush: Çoklu dosya güncellemesi',
    );
  }

  @override
  Widget build(BuildContext context) {
    final upload = Provider.of<UploadProvider>(context);
    final repo = Provider.of<RepoProvider>(context);
    final files = upload.multiFiles;

    // Repo/dal/ağaç değişince (veya ilk açılışta) durumları yeniden hesapla.
    if (_lastTreeRevision != repo.treeRevision) {
      _lastTreeRevision = repo.treeRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        upload.reclassifyAll(repo.treeIndex, truncated: repo.treeTruncated);
      });
    }

    // Kaldırılmış dosyaların seçimlerini temizle
    final liveIds = files.map((f) => f.id).toSet();
    _selectedIds.removeWhere((id) => !liveIds.contains(id));

    final newFolderCount = files.where((f) => f.status == GitFileStatus.newFolder).length;
    final conflictCount = files.where((f) => f.status == GitFileStatus.conflict).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode
            ? '${_selectedIds.length} seçili'
            : 'Çoklu Dosya Güncelle (Mod B)'),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Seçilenleri kaldır',
              onPressed: () => _removeSelected(upload),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Seçimi temizle',
              onPressed: () => setState(_selectedIds.clear),
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.code),
              tooltip: 'Metinle komut gir',
              onPressed: _showTextCommandDialog,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickFiles,
        icon: const Icon(Icons.add),
        label: const Text('Dosya Ekle'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              // Üstte Hazır Komut Çipleri
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: QuickCommandChips(
                  shortcuts: _shortcuts,
                  onSelect: (prefix) {
                    upload.applyShortcutToMultiFiles(prefix, _selectedIds);
                  },
                  onAddShortcut: _showAddShortcutDialog,
                ),
              ),
              if (_isSelectionMode)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Kısayollar yalnızca seçili ${_selectedIds.length} dosyaya uygulanır.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),

              // Görünür toplu eylem satırı
              if (files.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      Text('${files.length} dosya'),
                      TextButton(
                        onPressed: () => setState(() {
                          _selectedIds
                            ..clear()
                            ..addAll(files.map((f) => f.id));
                        }),
                        child: const Text('Tümünü Seç'),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () => _clearAll(upload),
                        child: const Text('Tümünü Kaldır'),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1),

              // Ağaç alınamadıysa uyarı
              if (repo.treeError != null)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.errorContainer,
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    'Repo dosya listesi alınamadı: ${repo.treeError}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),

              // Dosya Kartları Listesi
              Expanded(
                child: files.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.note_add_outlined, size: 56, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text('Henüz dosya eklenmedi.'),
                            const SizedBox(height: 8),
                            FilledButton.tonal(
                              onPressed: _pickFiles,
                              child: const Text('Telefonunuzdan Dosya Seçin'),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 80),
                        itemCount: files.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final file = files[index];
                          return FileCard(
                            key: ValueKey('card_${file.id}'),
                            file: file,
                            isSelected: _selectedIds.contains(file.id),
                            selectionMode: _isSelectionMode,
                            onToggleSelect: () => _toggleSelection(file.id),
                            onSelectPath: () => _openPathPickerForFile(file),
                            onPathChanged: (newPath) {
                              upload.updateMultiFilePathById(file.id, newPath);
                            },
                            onDelete: () {
                              final removed = file;
                              final removedIndex = files.indexOf(file);
                              upload.removeMultiFile(removedIndex);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${removed.fileName} kaldırıldı'),
                                  action: SnackBarAction(
                                    label: 'Geri Al',
                                    onPressed: () {
                                      upload.restoreMultiFiles([removed], atIndex: removedIndex);
                                    },
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SendBottomBar(
        summaryText:
            '${files.length} dosya${newFolderCount > 0 ? " · $newFolderCount yeni klasör" : ""}${conflictCount > 0 ? " · $conflictCount çakışma" : ""}',
        buttonLabel: 'Önizle',
        onButtonPressed: files.isEmpty ? null : _goToPreview,
      ),
    );
  }
}

// --- lib/screens/preview_screen.dart ---
class PreviewScreen extends StatefulWidget {
  final PreviewSource source;
  final String commitMessage;

  const PreviewScreen({
    super.key,
    required this.source,
    required this.commitMessage,
  });

  /// Önizlemeye girmeden ÖNCE repo ağacını taze çeker. Alınamazsa önizlemeye
  /// geçilmez ("hepsi yeni" varsayılmaz).
  static Future<void> open(
    BuildContext context, {
    required PreviewSource source,
    required String commitMessage,
  }) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final upload = Provider.of<UploadProvider>(context, listen: false);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final token = auth.token;
    if (token == null || repoProv.selectedRepo == null || repoProv.selectedBranch == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Önce bir depo ve dal seçmelisiniz.')),
      );
      return;
    }

    // Yükleniyor göstergesi
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    final ok = await repoProv.refreshTree(token);
    navigator.pop(); // yükleniyor göstergesini kapat

    if (!ok || repoProv.treeIndex == null) {
      final reason = repoProv.treeError;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Repo dosya listesi alınamadı, yeniden deneyin.${reason != null ? '\n$reason' : ''}',
          ),
        ),
      );
      return;
    }

    upload.reclassifyAll(repoProv.treeIndex, truncated: repoProv.treeTruncated);
    if (!context.mounted) return;

    await navigator.push(
      MaterialPageRoute(
        builder: (_) => PreviewScreen(source: source, commitMessage: commitMessage),
      ),
    );
  }

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late final TextEditingController _commitMsgCtrl;

  /// Push başladığında plan dondurulur (push sonrası sıfırlanan provider
  /// durumu ekranda "değişiklik yok" gibi görünmesin).
  PushPlan? _frozenPlan;
  bool _pushing = false;

  @override
  void initState() {
    super.initState();
    _commitMsgCtrl = TextEditingController(text: widget.commitMessage);
  }

  @override
  void dispose() {
    _commitMsgCtrl.dispose();
    super.dispose();
  }

  Future<void> _startPush(PushPlan plan) async {
    if (_pushing) return; // çift dokunuş koruması
    if (plan.hasBlockers || !plan.hasChanges) return;

    // Silme varsa çift onay
    if (plan.deletes.isNotEmpty) {
      final first = await ConfirmDialog.show(
        context,
        title: 'Dosyalar silinecek',
        content: '${plan.deletes.length} dosya depodan kalıcı olarak silinecek. Devam edilsin mi?',
        isDestructive: true,
      );
      if (!first || !mounted) return;

      final second = await ConfirmDialog.show(
        context,
        title: 'Son onay',
        content: '${plan.deletes.length} dosyanın silinmesini onaylıyor musunuz? '
            'Bu işlem commit geçmişinden geri alınabilir ancak yine de dikkatli olun.',
        isDestructive: true,
        confirmLabel: 'Evet, sil',
      );
      if (!second || !mounted) return;
    }

    await _runPush(plan);
  }

  Future<void> _runPush(PushPlan plan) async {
    if (_pushing) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final upload = Provider.of<UploadProvider>(context, listen: false);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final repo = repoProv.selectedRepo;
    final branch = repoProv.selectedBranch;
    final token = auth.token;
    if (repo == null || branch == null || token == null) return;

    setState(() {
      _pushing = true;
      _frozenPlan = plan;
    });

    // ignore: unawaited_futures
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Consumer<UploadProvider>(
          builder: (context, up, _) {
            return ProgressSheet(
              currentStep: up.uploadStep,
              current: up.uploadProgressCurrent,
              total: up.uploadProgressTotal,
              error: up.uploadError,
              onRetry: () {
                Navigator.pop(sheetContext);
                // Güncel sınıflandırmayla yeniden dene
                final fresh = upload.planFor(widget.source);
                if (!fresh.hasBlockers && fresh.hasChanges) {
                  _runPush(fresh);
                }
              },
              onCancel: () => Navigator.pop(sheetContext),
            );
          },
        );
      },
    );

    final commitMessage = _commitMsgCtrl.text.trim().isEmpty
        ? 'Gitpush: güncelleme'
        : _commitMsgCtrl.text.trim();
    final hasAuthor = (auth.authorName ?? '').trim().isNotEmpty &&
        (auth.authorEmail ?? '').trim().isNotEmpty;

    final success = await upload.executePush(
      token: token,
      owner: repo.owner,
      repo: repo.name,
      branch: branch,
      commitMessage: commitMessage,
      plan: plan,
      authorName: hasAuthor ? auth.authorName : null,
      authorEmail: hasAuthor ? auth.authorEmail : null,
    );

    if (!mounted) return;

    if (!success) {
      setState(() {
        _pushing = false;
        _frozenPlan = null;
      });
      // Dal siz işlem yaparken değiştiyse ağacı yenile ve yeniden sınıflandır.
      if (upload.uploadErrorKind == 'branch_moved' || upload.uploadErrorKind == 'safety_net') {
        final ok = await repoProv.refreshTree(token);
        if (ok) {
          upload.reclassifyAll(repoProv.treeIndex, truncated: repoProv.treeTruncated);
        }
      }
      return; // hata, ProgressSheet içinde gösteriliyor
    }

    navigator.pop(); // Progress modalını kapat
    final result = upload.lastResult;

    if (result == null || result.noChanges) {
      setState(() {
        _pushing = false;
        _frozenPlan = null;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Değişiklik yok: Repodaki dosyalarla aynı, commit atılmadı.')),
      );
      return;
    }

    // Başarılı: yükleme durumunu temizle, ağacı ve Actions'ı yenile
    final owner = repo.owner;
    final repoName = repo.name;
    final isPrivate = repo.isPrivate;
    final commitUrl = upload.lastCommitUrl ?? '';

    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          result: result,
          commitUrl: commitUrl,
          owner: owner,
          repo: repoName,
          branch: branch,
          isPrivate: isPrivate,
        ),
      ),
    );
    upload.resetAfterPush();
    // ignore: unawaited_futures
    repoProv.refreshTree(token);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upload = Provider.of<UploadProvider>(context);
    final repoProv = Provider.of<RepoProvider>(context);

    final plan = _frozenPlan ?? upload.planFor(widget.source);
    final addList = plan.adds;
    final updateList = plan.updates;
    final deleteList = plan.deletes;
    final unchangedList = plan.unchanged;
    final conflictList = plan.conflicts;

    final canPush = !plan.hasBlockers && plan.hasChanges && !_pushing && !upload.isUploading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gönderim Önizlemesi'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Üstte Sayaç Çipleri
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildCounterChip('+${addList.length} eklenecek', AppTheme.statusNew),
                  _buildCounterChip('~${updateList.length} güncellenecek', AppTheme.statusUpdate),
                  _buildCounterChip('-${deleteList.length} silinecek', AppTheme.statusDelete),
                  _buildCounterChip('=${unchangedList.length} değişmedi', Colors.grey),
                ],
              ),
              const SizedBox(height: 16),

              if (repoProv.treeTruncated) ...[
                _buildBanner(
                  'Repo çok büyük; durum tahminleri eksik olabilir.',
                  Icons.info_outline,
                  const Color(0xFFD29922).withValues(alpha: 0.18),
                  theme.colorScheme.onSurface,
                ),
                const SizedBox(height: 12),
              ],

              if (plan.treeUnknown) ...[
                _buildBanner(
                  'Repo dosya listesi alınamadı; gönderim engellendi. Geri dönüp tekrar deneyin.',
                  Icons.error_outline,
                  theme.colorScheme.errorContainer,
                  theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(height: 12),
              ],

              if (conflictList.isNotEmpty) ...[
                _buildBanner(
                  '${conflictList.length} dosyada sorun var; düzeltilene kadar gönderim engellendi.',
                  Icons.block,
                  theme.colorScheme.errorContainer,
                  theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(height: 12),
              ],

              // Silinecek Dosya Varsa Kırmızı Uyarı Bandı
              if (deleteList.isNotEmpty) ...[
                _buildBanner(
                  'DİKKAT: ${deleteList.length} dosya depodan kalıcı olarak silinecek!',
                  Icons.warning_amber_rounded,
                  theme.colorScheme.errorContainer,
                  theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(height: 12),
              ],

              if (!plan.hasChanges && !plan.hasBlockers) ...[
                _buildBanner(
                  'Değişiklik yok: Seçilen dosyalar repodakilerle aynı. Commit atılmayacak.',
                  Icons.info_outline,
                  theme.colorScheme.surfaceContainerHighest,
                  theme.colorScheme.onSurface,
                ),
                const SizedBox(height: 12),
              ],

              // Gruplu Listeler
              if (conflictList.isNotEmpty)
                _buildGroupTile('Engellenen Dosyalar (${conflictList.length})', conflictList, AppTheme.statusDelete, showMessage: true),
              if (addList.isNotEmpty)
                _buildGroupTile('Eklenecek Dosyalar (${addList.length})', addList, AppTheme.statusNew),
              if (updateList.isNotEmpty)
                _buildGroupTile('Güncellenecek Dosyalar (${updateList.length})', updateList, AppTheme.statusUpdate),
              if (deleteList.isNotEmpty)
                _buildGroupTile('Silinecek Dosyalar (${deleteList.length})', deleteList, AppTheme.statusDelete),
              if (plan.skipped.isNotEmpty)
                _buildGroupTile(
                  'Atlanacak - üzerine yazılmıyor (${plan.skipped.length})',
                  plan.skipped,
                  Colors.grey,
                  initiallyExpanded: false,
                ),
              if (unchangedList.isNotEmpty)
                _buildGroupTile(
                  'Değişmeyen Dosyalar - gönderilmez (${unchangedList.length})',
                  unchangedList,
                  Colors.grey,
                  initiallyExpanded: false,
                ),

              const SizedBox(height: 16),
              // Commit Mesajı
              Card(
                color: theme.colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Commit Mesajı',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _commitMsgCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'feat: add changes...',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SendBottomBar(
        summaryText: '${plan.pushItems.length} dosya işlenecek · ${unchangedList.length} değişmedi',
        buttonLabel: 'Onayla ve Gönder',
        onButtonPressed: canPush ? () => _startPush(plan) : null,
      ),
    );
  }

  Widget _buildBanner(String text, IconData icon, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCounterChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildGroupTile(
    String title,
    List<GitFileItem> items,
    Color color, {
    bool initiallyExpanded = true,
    bool showMessage = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: Icon(Icons.circle, color: color, size: 12),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        children: items.map((f) {
          final path = f.status == GitFileStatus.delete ? f.repoPath : f.targetPath;
          final subtitle = showMessage
              ? (f.conflictMessage ?? 'Çakışma')
              : (f.status == GitFileStatus.delete ? 'Repodan silinecek' : f.formattedSize);
          return ListTile(
            dense: true,
            title: Text(path, style: AppTheme.monoStyle.copyWith(fontSize: 12)),
            subtitle: Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: showMessage ? AppTheme.statusDelete : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// --- lib/screens/repo_browser_screen.dart ---
/// Repo tarayıcı: klasörler her zaman üstte, sıralama ve arama, çoklu seçim,
/// klasör özetleri (dosya sayısı / boyut), dosya detay ekranı ve toplu işlemler.
class RepoBrowserScreen extends StatefulWidget {
  const RepoBrowserScreen({super.key});

  @override
  State<RepoBrowserScreen> createState() => _RepoBrowserScreenState();
}

class _RepoBrowserScreenState extends State<RepoBrowserScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _crumbScroll = ScrollController();

  String _currentDir = '';
  String _query = '';
  bool _searching = false;
  final Set<String> _selected = <String>{};

  // Önbellek: ağaç değişmedikçe dizin / istatistik yeniden hesaplanmaz.
  int _cacheRevision = -1;
  String _cacheDir = '\u0000';
  RepoSortMode _cacheSort = RepoSortMode.nameAsc;
  bool _cacheHidden = true;
  List<RepoEntry> _entries = const <RepoEntry>[];
  int _statFiles = 0;
  int _statFolders = 0;
  int _statBytes = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _crumbScroll.dispose();
    super.dispose();
  }

  bool get _selecting => _selected.isNotEmpty;

  void _recompute(RepoProvider repoProv, AppSettings settings) {
    final rev = repoProv.treeRevision;
    if (rev == _cacheRevision &&
        _currentDir == _cacheDir &&
        settings.repoSort == _cacheSort &&
        settings.showHiddenFiles == _cacheHidden) {
      return;
    }
    final treeChanged = rev != _cacheRevision;
    _cacheRevision = rev;
    _cacheDir = _currentDir;
    _cacheSort = settings.repoSort;
    _cacheHidden = settings.showHiddenFiles;

    final tree = repoProv.currentTree;
    _entries = buildDirectoryListing(
      tree,
      _currentDir,
      sort: settings.repoSort,
      showHidden: settings.showHiddenFiles,
    );

    if (treeChanged) {
      var files = 0;
      var folders = 0;
      var bytes = 0;
      for (final e in tree) {
        final type = e['type'];
        if (type == 'tree') {
          folders++;
        } else {
          files++;
          final s = e['size'];
          if (s is num) bytes += s.toInt();
        }
      }
      _statFiles = files;
      _statFolders = folders;
      _statBytes = bytes;
    }
  }

  void _enterDir(String path) {
    setState(() {
      _currentDir = path;
      _query = '';
      _searching = false;
      _searchCtrl.clear();
      _selected.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_crumbScroll.hasClients) {
        _crumbScroll.animateTo(
          _crumbScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _newFile() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FileEditorScreen(path: _currentDir.isEmpty ? '' : '$_currentDir/', isNew: true),
      ),
    );
  }

  void _goUp() {
    final idx = _currentDir.lastIndexOf('/');
    _enterDir(idx == -1 ? '' : _currentDir.substring(0, idx));
  }

  Future<void> _refresh() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    if (token != null) await repoProv.refreshTree(token);
  }

  void _toggleSelect(RepoEntry e) {
    Provider.of<SettingsProvider>(context, listen: false).tap();
    setState(() {
      if (!_selected.remove(e.path)) _selected.add(e.path);
    });
  }

  Future<void> _open(RepoEntry e) async {
    if (_selecting) {
      _toggleSelect(e);
      return;
    }
    if (e.isDir) {
      _enterDir(e.path);
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FileDetailScreen(entry: e)),
    );
  }

  List<RepoEntry> _selectedEntries(List<RepoEntry> visible) {
    return visible.where((e) => _selected.contains(e.path)).toList();
  }

  Future<void> _deleteSelected(List<RepoEntry> visible) async {
    final chosen = _selectedEntries(visible);
    final done = await RepoActions.deleteEntries(context, chosen);
    if (done && mounted) setState(_selected.clear);
  }

  void _showEntryActions(RepoEntry e) {
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final repo = repoProv.selectedRepo;
    final branch = repoProv.selectedBranch;
    final theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        Widget item(IconData icon, String label, VoidCallback onTap, {Color? color}) {
          return ListTile(
            leading: Icon(icon, color: color),
            title: Text(label, style: TextStyle(color: color)),
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    e.path,
                    style: AppTheme.monoBold.copyWith(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                item(e.isDir ? Icons.folder_open : Icons.visibility_outlined, e.isDir ? 'Klasörü aç' : 'Ayrıntılar ve önizleme',
                    () => _open(e)),
                item(Icons.checklist, 'Seç', () => _toggleSelect(e)),
                item(Icons.copy, 'Yolu kopyala', () => RepoActions.copy(context, e.path, 'Yol kopyalandı.')),
                if (repo != null && branch != null)
                  item(Icons.open_in_new, 'GitHub\'da aç',
                      () => openExternalUrl(context, RepoActions.githubUrlFor(repo, branch, e))),
                if (!e.isSubmodule)
                  item(Icons.drive_file_move_outlined, 'Taşı / yeniden adlandır', () => RepoActions.renameOrMove(context, e)),
                if (!e.isSubmodule)
                  item(
                    Icons.delete_outline,
                    e.isDir ? 'Klasörü sil' : 'Dosyayı sil',
                    () => RepoActions.deleteEntries(context, [e]),
                    color: AppTheme.statusDelete,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repoProvider = Provider.of<RepoProvider>(context);
    final settingsProv = Provider.of<SettingsProvider>(context);
    final settings = settingsProv.settings;

    if (repoProvider.selectedRepo == null) {
      return const EmptyState(
        icon: Icons.folder_open,
        message: 'Lütfen önce üst kısımdan bir depo seçin.',
      );
    }

    if (repoProvider.treeError != null) {
      return ErrorView(
        message: 'Repo dosya listesi alınamadı: ${repoProvider.treeError}',
        onRetry: _refresh,
      );
    }
    if (repoProvider.isTreeLoading && repoProvider.currentTree.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    _recompute(repoProvider, settings);

    final searching = _query.trim().isNotEmpty;
    final List<RepoEntry> visible = searching
        ? searchRepoTree(repoProvider.currentTree, _query, showHidden: settings.showHiddenFiles)
        : _entries;

    // Silinmiş/yenilenmiş öğeleri seçimden düşür
    _selected.removeWhere((p) => !visible.any((e) => e.path == p));

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton.extended(
              onPressed: _newFile,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Yeni dosya'),
            ),
      body: Column(
      children: [
        _buildToolbar(theme, settings, settingsProv, visible),
        if (!searching) _buildBreadcrumbs(theme),
        if (repoProvider.treeTruncated)
          Container(
            width: double.infinity,
            color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Bu depo çok büyük; GitHub dosya listesini kesti. Bazı dosyalar burada görünmeyebilir.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (!searching) _buildStatsLine(theme, repoProvider.isTreeLoading),
        const Divider(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: visible.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 260,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                searching ? Icons.search_off : Icons.folder_off_outlined,
                                size: 44,
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                              const SizedBox(height: 10),
                              Text(searching ? 'Eşleşen dosya yok' : 'Bu klasör boş'),
                              if (!settings.showHiddenFiles && !searching)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    'Gizli (.) dosyalar kapalı',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(indent: 72),
                    itemBuilder: (context, index) => _buildTile(theme, visible[index], searching),
                  ),
          ),
        ),
      ],
    ),
    );
  }

  Widget _buildToolbar(ThemeData theme, AppSettings settings, SettingsProvider settingsProv, List<RepoEntry> visible) {
    if (_selecting) {
      return Container(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Seçimi kapat',
              icon: const Icon(Icons.close),
              onPressed: () => setState(_selected.clear),
            ),
            Expanded(
              child: Text('${_selected.length} seçili', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: 'Tümünü seç',
              icon: const Icon(Icons.select_all),
              onPressed: () => setState(() {
                _selected
                  ..clear()
                  ..addAll(visible.map((e) => e.path));
              }),
            ),
            IconButton(
              tooltip: 'Seçilenleri sil',
              icon: const Icon(Icons.delete_outline, color: AppTheme.statusDelete),
              onPressed: () => _deleteSelected(visible),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() {
                  _query = v;
                  _searching = v.trim().isNotEmpty;
                }),
                textInputAction: TextInputAction.search,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: 'Depoda dosya ara...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searching
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() {
                            _searchCtrl.clear();
                            _query = '';
                            _searching = false;
                          }),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  isDense: true,
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Sırala ve göster',
            icon: const Icon(Icons.sort),
            onSelected: (v) {
              if (v == 'hidden') {
                settingsProv.update((c) => c.copyWith(showHiddenFiles: !c.showHiddenFiles));
              } else {
                final mode = RepoSortMode.values.firstWhere((m) => m.name == v, orElse: () => RepoSortMode.nameAsc);
                settingsProv.update((c) => c.copyWith(repoSort: mode));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                enabled: false,
                height: 32,
                child: Text('Klasörler her zaman üstte', style: TextStyle(fontSize: 12)),
              ),
              for (final m in RepoSortMode.values)
                CheckedPopupMenuItem<String>(
                  value: m.name,
                  checked: settings.repoSort == m,
                  child: Text(m.label),
                ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem<String>(
                value: 'hidden',
                checked: settings.showHiddenFiles,
                child: const Text('Gizli (.) dosyaları göster'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Commit geçmişi',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CommitsScreen())),
          ),
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs(ThemeData theme) {
    final crumbs = breadcrumbsFor(_currentDir);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          if (_currentDir.isNotEmpty)
            IconButton(
              tooltip: 'Üst klasör',
              icon: const Icon(Icons.arrow_upward, size: 20),
              onPressed: _goUp,
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: ListView.separated(
              controller: _crumbScroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 12),
              itemCount: crumbs.length,
              separatorBuilder: (_, __) => Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
              itemBuilder: (context, i) {
                final c = crumbs[i];
                final isLast = i == crumbs.length - 1;
                return Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: isLast ? null : () => _enterDir(c.path),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        children: [
                          if (i == 0) ...[
                            Icon(Icons.home_outlined, size: 16, color: isLast ? theme.colorScheme.primary : null),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            c.label,
                            style: AppTheme.monoBold.copyWith(
                              fontSize: 13,
                              color: isLast ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsLine(ThemeData theme, bool loading) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Depo: $_statFiles dosya · $_statFolders klasör · ${formatBytes(_statBytes)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (loading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }

  Widget _buildTile(ThemeData theme, RepoEntry e, bool searching) {
    final selected = _selected.contains(e.path);
    final visual = e.isDir
        ? FileVisual(Icons.folder_rounded, theme.colorScheme.primary)
        : e.isSubmodule
            ? const FileVisual(Icons.account_tree_outlined, Color(0xFF8B93A7))
            : fileVisualFor(e.extension);

    String subtitle;
    if (e.isDir) {
      final parts = <String>[
        '${e.fileCount} dosya',
        if (e.folderCount > 0) '${e.folderCount} klasör',
        formatBytes(e.size),
      ];
      subtitle = parts.join(' · ');
    } else if (e.isSubmodule) {
      subtitle = 'Alt modül';
    } else {
      subtitle = formatBytes(e.size);
    }
    if (searching) {
      final slash = e.path.lastIndexOf('/');
      final parent = slash == -1 ? 'Kök' : e.path.substring(0, slash);
      subtitle = '$parent · $subtitle';
    }

    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: visual.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: selected
            ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
            : Icon(visual.icon, color: visual.color, size: 24),
      ),
      title: Text(
        e.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.monoStyle.copyWith(
          fontSize: 13.5,
          fontWeight: e.isDir ? FontWeight.w700 : FontWeight.w500,
          color: e.isHidden ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: _selecting
          ? null
          : IconButton(
              tooltip: 'İşlemler',
              icon: const Icon(Icons.more_vert, size: 20),
              onPressed: () => _showEntryActions(e),
            ),
      onTap: () => _open(e),
      onLongPress: () => _selecting ? _showEntryActions(e) : _toggleSelect(e),
    );
  }
}

// --- lib/screens/repo_picker_screen.dart ---
class RepoPickerScreen extends StatefulWidget {
  const RepoPickerScreen({super.key});

  @override
  State<RepoPickerScreen> createState() => _RepoPickerScreenState();
}

class _RepoPickerScreenState extends State<RepoPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showNewRepoDialog() {
    final nameCtrl = TextEditingController();
    bool isPrivate = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Yeni Depo Oluştur'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Depo Adı'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Özel (Private) Depo'),
                value: isPrivate,
                onChanged: (val) => setModalState(() => isPrivate = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isNotEmpty) {
                  final auth = Provider.of<AuthProvider>(context, listen: false);
                  final repoProv = Provider.of<RepoProvider>(context, listen: false);
                  Navigator.pop(ctx);
                  final created = await repoProv.createNewRepo(auth.token!, name, isPrivate);
                  if (created != null && mounted) {
                    Navigator.pop(context);
                  }
                }
              },
              child: const Text('Oluştur'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewBranchDialog() {
    final branchCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni Dal (Branch) Oluştur'),
        content: TextField(
          controller: branchCtrl,
          decoration: const InputDecoration(labelText: 'Dal Adı (Örn: feature-1)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () async {
              final b = branchCtrl.text.trim();
              if (b.isNotEmpty) {
                final auth = Provider.of<AuthProvider>(context, listen: false);
                final repoProv = Provider.of<RepoProvider>(context, listen: false);
                Navigator.pop(ctx);
                final success = await repoProv.createNewBranch(auth.token!, b);
                if (success && mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteBranch(String name) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dal silinsin mi?'),
        content: Text('"$name" dalı GitHub\'dan silinecek. Birleştirilmemiş commit\'ler kaybolabilir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || auth.token == null) return;
    try {
      await repoProv.deleteBranch(auth.token!, name);
      messenger.showSnackBar(SnackBar(content: Text('"$name" silindi.')));
    } on GitHubApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = Provider.of<AuthProvider>(context);
    final repoProvider = Provider.of<RepoProvider>(context);

    final sortMode = Provider.of<SettingsProvider>(context).settings.repoListSort;
    final filteredRepos = repoProvider.repositories.where((r) {
      return r.fullName.toLowerCase().contains(_filter.toLowerCase());
    }).toList();
    switch (sortMode) {
      case RepoListSort.recent:
        filteredRepos.sort((a, b) => (b.updatedAt ?? DateTime(1970)).compareTo(a.updatedAt ?? DateTime(1970)));
        break;
      case RepoListSort.name:
        filteredRepos.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
        break;
      case RepoListSort.privateFirst:
        filteredRepos.sort((a, b) {
          if (a.isPrivate != b.isPrivate) return a.isPrivate ? -1 : 1;
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        });
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Repo & Dal Seçimi'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewRepoDialog,
        icon: const Icon(Icons.add),
        label: const Text('Yeni Repo'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              // Arama Çubuğu
              Padding(
                padding: const EdgeInsets.all(16),
                child: SearchBar(
                  controller: _searchController,
                  hintText: 'Depolarda ara...',
                  leading: const Icon(Icons.search),
                  onChanged: (val) => setState(() => _filter = val),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: filteredRepos.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final repo = filteredRepos[index];
                    final isSelected = repo.fullName == repoProvider.selectedRepo?.fullName;

                    return ExpansionTile(
                      key: ValueKey(repo.id),
                      initiallyExpanded: isSelected,
                      leading: Icon(
                        repo.isPrivate ? Icons.lock_outline : Icons.public,
                        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        repo.fullName,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        '${repo.description != null && repo.description!.isNotEmpty ? '${repo.description}\n' : ''}Varsayılan: ${repo.defaultBranch}',
                        style: AppTheme.monoStyle.copyWith(fontSize: 11),
                      ),
                      onExpansionChanged: (expanded) {
                        if (expanded) {
                          repoProvider.selectRepository(auth.token!, repo);
                        }
                      },
                      children: [
                        // Dallar listesi
                        Container(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'DALLAR (silmek için uzun bas)',
                                    style: AppTheme.monoBold.copyWith(
                                      fontSize: 11,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _showNewBranchDialog,
                                    icon: const Icon(Icons.add, size: 14),
                                    label: const Text('Yeni Dal', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                              ...repoProvider.branches.map((b) {
                                final isCurrentBranch = b.name == repoProvider.selectedBranch;
                                return ListTile(
                                  dense: true,
                                  title: Text(b.name, style: AppTheme.monoStyle),
                                  trailing: isCurrentBranch
                                      ? Icon(Icons.check, color: theme.colorScheme.primary, size: 18)
                                      : null,
                                  onTap: () {
                                    repoProvider.selectBranch(auth.token!, b.name);
                                    Navigator.pop(context);
                                  },
                                  onLongPress: b.name == repo.defaultBranch ? null : () => _confirmDeleteBranch(b.name),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- lib/screens/result_screen.dart ---
class ResultScreen extends StatefulWidget {
  final PushResult result;
  final String commitUrl;
  final String owner;
  final String repo;
  final String branch;
  final bool isPrivate;

  const ResultScreen({
    super.key,
    required this.result,
    required this.commitUrl,
    required this.owner,
    required this.repo,
    required this.branch,
    this.isPrivate = false,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  static const int _pollIntervalSeconds = 10;
  static const int _pollLimitSeconds = 300;

  final GitHubService _gitHubService = GitHubService();
  Timer? _pollTimer;
  List<ActionRun> _runs = [];
  bool _isPolling = true;
  bool _notFound = false;
  String? _pollError;
  int _pollSeconds = 0;
  bool _requestInFlight = false;

  String get _sha => widget.result.commitSha ?? '';

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _isPolling = false;
  }

  void _startPolling() {
    _pollActions();
    _pollTimer = Timer.periodic(const Duration(seconds: _pollIntervalSeconds), (timer) {
      _pollSeconds += _pollIntervalSeconds;
      if (_pollSeconds >= _pollLimitSeconds) {
        // Süre doldu: eşleşen çalışma hiç görünmediyse bunu bildir.
        if (mounted) {
          setState(() {
            _stopPolling();
            if (_runs.isEmpty && _pollError == null) _notFound = true;
          });
        } else {
          timer.cancel();
        }
        return;
      }
      _pollActions();
    });
  }

  Future<void> _pollActions() async {
    if (_requestInFlight) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token;
    if (token == null || _sha.isEmpty) {
      setState(_stopPolling);
      return;
    }

    _requestInFlight = true;
    try {
      final runs = await _gitHubService.getActionRuns(token, widget.owner, widget.repo);
      if (!mounted) return;

      final evaluation = evaluateRuns(runs, _sha);
      setState(() {
        _pollError = null;
        _runs = evaluation.matching;
        if (evaluation.allCompleted) _stopPolling();
      });
    } on GitHubApiException catch (e) {
      if (!mounted) return;
      // Yetki/erişim hatası tekrarlarla düzelmez; polling durur.
      setState(() {
        _pollError = e.message;
        _stopPolling();
      });
    } finally {
      _requestInFlight = false;
    }
  }

  String get _actionsUrl => 'https://github.com/${widget.owner}/${widget.repo}/actions';
  String get _releasesUrl => 'https://github.com/${widget.owner}/${widget.repo}/releases';

  Color _runColor(ActionRun run, ThemeData theme) {
    if (run.isSuccess) return AppTheme.statusNew;
    if (run.isFailed || run.isTimedOut || run.isStartupFailure) return theme.colorScheme.error;
    if (run.isCancelled) return theme.colorScheme.onSurfaceVariant;
    return theme.colorScheme.primary;
  }

  IconData _runIcon(ActionRun run) {
    if (run.isSuccess) return Icons.check_circle;
    if (run.isFailed || run.isTimedOut || run.isStartupFailure) return Icons.cancel;
    if (run.isCancelled) return Icons.block;
    return Icons.hourglass_empty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.result;
    final anySuccess = _runs.any((r) => r.isSuccess);
    final allDone = _runs.isNotEmpty && _runs.every((r) => r.isCompleted);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gönderim Tamamlandı'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Başarı İkonu
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.statusNew.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, size: 64, color: AppTheme.statusNew),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Başarıyla Gönderildi!',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Sayaçlar (gerçek push sonucundan)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text('+${result.added} eklendi', style: const TextStyle(color: AppTheme.statusNew, fontWeight: FontWeight.bold)),
                  Text('~${result.updated} güncellendi', style: const TextStyle(color: AppTheme.statusUpdate, fontWeight: FontWeight.bold)),
                  Text('-${result.deleted} silindi', style: const TextStyle(color: AppTheme.statusDelete, fontWeight: FontWeight.bold)),
                  Text('=${result.skipped} atlandı', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ],
              ),
              for (final w in result.warnings) ...[
                const SizedBox(height: 8),
                Text(w, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              ],
              const SizedBox(height: 16),

              // Commit SHA & Kopyala
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      shortSha(_sha),
                      style: AppTheme.monoBold.copyWith(fontSize: 14),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'SHA Kopyala',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _sha));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Commit SHA kopyalandı!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Canlı Build Durumu Kartı
              Card(
                color: theme.colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Canlı Build Durumu',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (_isPolling)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_pollError != null)
                        Text(
                          'Durum alınamadı: $_pollError',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                        )
                      else if (_runs.isNotEmpty)
                        ...[
                          for (final run in _runs.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Icon(_runIcon(run), size: 18, color: _runColor(run, theme)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(run.name, style: const TextStyle(fontSize: 12)),
                                ),
                                Text(
                                  run.statusLabel,
                                  style: AppTheme.monoStyle.copyWith(fontSize: 12, color: _runColor(run, theme)),
                                ),
                              ],
                            ),
                          ),
                        ]
                      else if (_notFound)
                        const Text(
                          'Workflow tetiklenmedi/bulunamadı. Bu commit için bir GitHub Actions çalışması görünmedi.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        )
                      else
                        const Text(
                          'Bu commit için GitHub Actions çalışması bekleniyor...',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Eylem Butonları
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const MainShell()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.home),
                label: const Text('Ana Ekrana Dön'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => openExternalUrl(context, widget.commitUrl),
                icon: const Icon(Icons.open_in_browser),
                label: const Text("GitHub'da Aç"),
              ),
              if (widget.isPrivate)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Özel depo: tarayıcıda GitHub\'a giriş yapmadıysanız bağlantı 404 gösterebilir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  final url = _runs.isNotEmpty && _runs.first.htmlUrl.isNotEmpty
                      ? _runs.first.htmlUrl
                      : _actionsUrl;
                  openExternalUrl(context, url);
                },
                icon: const Icon(Icons.bolt),
                label: const Text("Actions'ta Aç"),
              ),
              if (allDone && anySuccess) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => openExternalUrl(context, _releasesUrl),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text("Releases'ı Aç"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// --- lib/screens/send_screen.dart ---
class SendScreen extends StatelessWidget {
  const SendScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repoProvider = Provider.of<RepoProvider>(context);
    final uploadProvider = Provider.of<UploadProvider>(context);

    if (repoProvider.selectedRepo == null) {
      return EmptyState(
        icon: Icons.source_outlined,
        message: 'Dosya göndermek için önce bir GitHub deposu seçmelisiniz.',
        actionLabel: 'Depo Seç',
        onAction: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RepoPickerScreen()),
          );
        },
      );
    }

    final repo = repoProvider.selectedRepo!;
    final branch = repoProvider.selectedBranch ?? repo.defaultBranch;

    return RefreshIndicator(
      onRefresh: () async {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final token = auth.token;
        if (token != null) {
          // Dalları ve repo ağacını yenile
          await repoProvider.loadBranches(token, repo);
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // Repo / Branch Özeti Kartı
          SectionCard(
            title: 'Aktif Hedef Depo',
            trailing: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RepoPickerScreen()),
                );
              },
              child: const Text('Değiştir'),
            ),
            child: Row(
              children: [
                Icon(
                  repo.isPrivate ? Icons.lock : Icons.public,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        repo.fullName,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Dal: $branch',
                        style: AppTheme.monoStyle.copyWith(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Mod A: ZIP'ten Aktar
          ModeCard(
            title: "ZIP'ten Aktar",
            description: 'Telefonda seçtiğiniz bir ZIP arşivini açın, dosya ağacını inceleyin ve tek seferde repoya yükleyin.',
            icon: Icons.folder_zip_outlined,
            iconColor: AppTheme.statusUpdate,
            badgeText: 'MOD A',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ZipTransferScreen()),
              );
            },
          ),
          const SizedBox(height: 12),

          // Mod B: Dosyaları Güncelle
          ModeCard(
            title: 'Dosyaları Güncelle',
            description: 'Birden fazla dosyayı, her biri farklı repo yoluna (klasör yoksa otomatik oluşturularak) tek commit ile yükleyin.',
            icon: Icons.upload_file_outlined,
            iconColor: AppTheme.statusNew,
            badgeText: 'MOD B',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MultiFileScreen()),
              );
            },
          ),
          const SizedBox(height: 16),

          // Son Gönderim Kartı
          if (uploadProvider.historyItems.isNotEmpty) ...[
            SectionCard(
              title: 'Son Gönderim',
              child: Builder(
                builder: (context) {
                  final last = uploadProvider.historyItems.first;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        last.commitMessage,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            shortSha(last.commitSha),
                            style: AppTheme.monoStyle.copyWith(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${last.filesCount} dosya',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// --- lib/screens/settings_screen.dart ---
const String kAppVersion = '1.2.1+4';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final StorageService _storage = StorageService();
  final GitHubService _github = GitHubService();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _commitCtrl = TextEditingController();
  final TextEditingController _shortcutCtrl = TextEditingController();
  List<String> _shortcuts = [];
  RateLimitInfo? _rate;
  String? _rateError;
  bool _rateLoading = false;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false).settings;
    _nameCtrl.text = auth.authorName ?? '';
    _emailCtrl.text = auth.authorEmail ?? '';
    _commitCtrl.text = settings.defaultCommitMessage;
    _loadShortcuts();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _commitCtrl.dispose();
    _shortcutCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadShortcuts() async {
    final list = await _storage.getShortcuts();
    if (mounted) setState(() => _shortcuts = list);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadRate() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;
    setState(() {
      _rateLoading = true;
      _rateError = null;
    });
    try {
      final r = await _github.getRateLimit(token);
      if (mounted) setState(() => _rate = r);
    } on GitHubApiException catch (e) {
      if (mounted) setState(() => _rateError = e.message);
    } finally {
      if (mounted) setState(() => _rateLoading = false);
    }
  }

  /// Token'ın türünü yalnızca ön ekinden çıkarır; token asla gösterilmez.
  String _tokenKind(String? token) {
    if (token == null) return 'Yok';
    if (token.startsWith('github_pat_')) return 'Fine-grained PAT';
    if (token.startsWith('ghp_')) return 'Klasik PAT';
    if (token.startsWith('gho_')) return 'OAuth (GitHub ile giriş)';
    if (token.startsWith('ghu_') || token.startsWith('ghs_')) return 'GitHub App';
    return 'Bilinmeyen tür';
  }

  Future<T?> _pick<T>(String title, Map<T, String> options, T current) {
    return showModalBottomSheet<T>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            for (final e in options.entries)
              ListTile(
                title: Text(e.value),
                trailing: e.key == current ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary) : null,
                onTap: () => Navigator.pop(ctx, e.key),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ok = await ConfirmDialog.show(
      context,
      title: 'Çıkış Yapılsın mı?',
      content: 'Kayıtlı token, yazar bilgileri ve geçmiş bu cihazdan silinecek.',
      isDestructive: true,
    );
    if (!ok || !mounted) return;
    final repoProv = Provider.of<RepoProvider>(context, listen: false);
    final uploadProv = Provider.of<UploadProvider>(context, listen: false);
    final navigator = Navigator.of(context);
    await auth.logout();
    repoProv.reset();
    uploadProv.resetAll();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SetupScreen()),
      (route) => false,
    );
  }

  Future<void> _toggleLock(bool on) async {
    final settingsProv = Provider.of<SettingsProvider>(context, listen: false);
    final lock = Provider.of<AppLockProvider>(context, listen: false);
    if (on) {
      final created = await createNewPin(context);
      if (!created || !mounted) return;
      await settingsProv.update((c) => c.copyWith(appLockEnabled: true));
      await lock.syncSettings(settingsProv.settings);
      _snack('Uygulama kilidi açıldı.');
    } else {
      final ok = await verifyCurrentPin(context, title: 'Kilidi kapat');
      if (!ok || !mounted) return;
      await lock.service.clear();
      await settingsProv.update((c) => c.copyWith(appLockEnabled: false));
      await lock.syncSettings(settingsProv.settings);
      _snack('Uygulama kilidi kapatıldı.');
    }
  }

  Future<void> _changePin() async {
    final ok = await verifyCurrentPin(context);
    if (!ok || !mounted) return;
    final created = await createNewPin(context);
    if (created && mounted) _snack('PIN değiştirildi.');
  }

  Future<void> _resetAll() async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Ayarlar sıfırlansın mı?',
      content: 'Görünüm, repo tarayıcı ve önizleme tercihleri varsayılana döner. Hesap ve PIN etkilenmez.',
      confirmLabel: 'Sıfırla',
    );
    if (!ok || !mounted) return;
    final settingsProv = Provider.of<SettingsProvider>(context, listen: false);
    await settingsProv.resetToDefaults();
    if (!mounted) return;
    _commitCtrl.text = settingsProv.settings.defaultCommitMessage;
    _snack('Ayarlar sıfırlandı.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = Provider.of<AuthProvider>(context);
    final themeProv = Provider.of<ThemeProvider>(context);
    final settingsProv = Provider.of<SettingsProvider>(context);
    final lock = Provider.of<AppLockProvider>(context);
    final s = settingsProv.settings;

    void set(AppSettings Function(AppSettings) f) => settingsProv.update(f);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // ---------------- Hesap ----------------
        _Section(
          title: 'Hesap',
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundImage: auth.avatarUrl != null ? NetworkImage(auth.avatarUrl!) : null,
                    child: auth.avatarUrl == null ? const Icon(Icons.person) : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(auth.username ?? 'Kullanıcı', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        Text(_tokenKind(auth.token),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(foregroundColor: theme.colorScheme.error, minimumSize: const Size(64, 40)),
                    onPressed: _logout,
                    child: const Text('Çıkış'),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('Token\'ları GitHub\'da yönet'),
              subtitle: const Text('Süre, yetki ve iptal ayarları'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => openExternalUrl(context, 'https://github.com/settings/tokens'),
            ),
            ListTile(
              leading: const Icon(Icons.speed_outlined),
              title: const Text('GitHub API kotası'),
              subtitle: Text(_rateLoading
                  ? 'Sorgulanıyor...'
                  : _rateError ??
                      (_rate == null
                          ? 'Kalan istek hakkını görmek için dokunun'
                          : '${_rate!.remaining} / ${_rate!.limit} kalan'
                              '${_rate!.resetAt != null ? ' · sıfırlanma ${_hhmm(_rate!.resetAt!)}' : ''}')),
              trailing: const Icon(Icons.refresh, size: 18),
              onTap: _loadRate,
            ),
          ],
        ),

        // ---------------- Görünüm ----------------
        _Section(
          title: 'Görünüm',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('Sistem'), icon: Icon(Icons.brightness_auto)),
                  ButtonSegment(value: ThemeMode.light, label: Text('Açık'), icon: Icon(Icons.light_mode)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Koyu'), icon: Icon(Icons.dark_mode)),
                ],
                selected: {themeProv.themeMode},
                onSelectionChanged: (set) => themeProv.setThemeMode(set.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vurgu rengi', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < AppSettings.accentPalette.length; i++)
                        Semantics(
                          label: AppSettings.accentNames[i],
                          selected: s.accentIndex == i,
                          button: true,
                          child: GestureDetector(
                            onTap: () {
                              settingsProv.tap();
                              set((c) => c.copyWith(accentIndex: i));
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Color(AppSettings.accentPalette[i]),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: s.accentIndex == i ? theme.colorScheme.onSurface : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: s.accentIndex == i ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.contrast),
              title: const Text('AMOLED siyah'),
              subtitle: const Text('Koyu temada saf siyah zemin'),
              value: s.amoledDark,
              onChanged: (v) => set((c) => c.copyWith(amoledDark: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.vibration),
              title: const Text('Dokunsal geri bildirim'),
              subtitle: const Text('Seçim ve başarılı işlemlerde hafif titreşim'),
              value: s.haptics,
              onChanged: (v) => set((c) => c.copyWith(haptics: v)),
            ),
          ],
        ),

        // ---------------- Commit ----------------
        _Section(
          title: 'Commit',
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Yazar adı'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Yazar e-postası'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _commitCtrl,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Varsayılan commit mesajı',
                      helperText: 'Boş bırakılırsa her ekran kendi metnini kullanır',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(minimumSize: const Size(64, 42)),
                      onPressed: () {
                        auth.updateAuthorInfo(_nameCtrl.text, _emailCtrl.text);
                        set((c) => c.copyWith(defaultCommitMessage: _commitCtrl.text.trim()));
                        _snack('Commit ayarları kaydedildi.');
                      },
                      child: const Text('Kaydet'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // ---------------- Repo ve dosyalar ----------------
        _Section(
          title: 'Repo ve dosyalar',
          children: [
            ListTile(
              leading: const Icon(Icons.sort),
              title: const Text('Dosya sıralaması'),
              subtitle: Text('${s.repoSort.label} · klasörler her zaman üstte'),
              onTap: () async {
                final v = await _pick<RepoSortMode>(
                    'Dosya sıralaması', {for (final m in RepoSortMode.values) m: m.label}, s.repoSort);
                if (v != null) set((c) => c.copyWith(repoSort: v));
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_outlined),
              title: const Text('Gizli (.) dosyaları göster'),
              value: s.showHiddenFiles,
              onChanged: (v) => set((c) => c.copyWith(showHiddenFiles: v)),
            ),
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('Depo listesi sıralaması'),
              subtitle: Text(s.repoListSort.label),
              onTap: () async {
                final v = await _pick<RepoListSort>(
                    'Depo listesi sıralaması', {for (final m in RepoListSort.values) m: m.label}, s.repoListSort);
                if (v != null) set((c) => c.copyWith(repoListSort: v));
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.history_toggle_off),
              title: const Text('Son depoyu hatırla'),
              subtitle: const Text('Açılışta son seçilen depo ve dal'),
              value: s.rememberLastRepo,
              onChanged: (v) async {
                set((c) => c.copyWith(rememberLastRepo: v));
                if (!v) await _storage.clearLastRepoAndBranch();
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Önizleme boyut sınırı'),
              subtitle: Text('${s.previewMaxKb} KB üstü dosyalar indirilmez'),
              onTap: () async {
                final v = await _pick<int>(
                  'Önizleme boyut sınırı',
                  {for (final k in AppSettings.previewMaxKbOptions) k: k >= 1024 ? '${k ~/ 1024} MB' : '$k KB'},
                  s.previewMaxKb,
                );
                if (v != null) set((c) => c.copyWith(previewMaxKb: v));
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.wrap_text),
              title: const Text('Önizlemede satır kaydır'),
              value: s.previewWrapLines,
              onChanged: (v) => set((c) => c.copyWith(previewWrapLines: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.format_size),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Slider(
                      min: 10,
                      max: 18,
                      divisions: 8,
                      value: s.previewFontSize,
                      label: '${s.previewFontSize.round()} pt',
                      onChanged: (v) => set((c) => c.copyWith(previewFontSize: v)),
                    ),
                  ),
                  Text('${s.previewFontSize.round()} pt', style: AppTheme.monoStyle),
                ],
              ),
            ),
          ],
        ),

        // ---------------- Güvenlik ----------------
        _Section(
          title: 'Güvenlik',
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.lock_outline),
              title: const Text('Uygulama kilidi (PIN)'),
              subtitle: const Text('Açılışta ve arka plandan dönünce 6 haneli PIN ister'),
              value: lock.enabled,
              onChanged: _toggleLock,
            ),
            if (lock.enabled) ...[
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: const Text('PIN\'i değiştir'),
                onTap: _changePin,
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Otomatik kilitlenme'),
                subtitle: Text(_timeoutLabel(s.lockTimeoutSeconds)),
                onTap: () async {
                  final v = await _pick<int>(
                    'Arka plandan dönünce kilitle',
                    {for (final t in AppSettings.lockTimeoutOptions) t: _timeoutLabel(t)},
                    s.lockTimeoutSeconds,
                  );
                  if (v == null) return;
                  await settingsProv.update((c) => c.copyWith(lockTimeoutSeconds: v));
                  await lock.syncSettings(settingsProv.settings);
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_clock),
                title: const Text('Şimdi kilitle'),
                onTap: lock.lockNow,
              ),
            ],
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Kullanılmazsa oturumu kapat'),
              subtitle: Text(s.autoLogoutDays == 0 ? 'Kapalı' : '${s.autoLogoutDays} gün açılmazsa token silinir'),
              onTap: () async {
                final v = await _pick<int>(
                  'Otomatik oturum kapatma',
                  {for (final d in AppSettings.autoLogoutOptions) d: d == 0 ? 'Kapalı' : '$d gün'},
                  s.autoLogoutDays,
                );
                if (v != null) set((c) => c.copyWith(autoLogoutDays: v));
              },
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Güvenlik özeti'),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Nasıl korunuyorsunuz?'),
                  content: const SingleChildScrollView(
                    child: Text(
                      '• Token Android Keystore ile şifreli saklanır; ekranda gösterilmez.\n'
                      '• Token yalnızca https://api.github.com adresine gönderilir.\n'
                      '• Gönderimden önce .env, anahtar ve token içeren dosyalar taranır; bulunursa push durur.\n'
                      '• Silme ve taşıma işlemleri tek commit\'tir; dal arada değişirse hiçbir şey ezilmez.\n'
                      '• PIN düz metin tutulmaz (tuzlu, 20.000 turlu SHA-256); 5 hatadan sonra bekleme süresi artar.\n'
                      '• Uygulama yedeklemesi ve düz HTTP kapalıdır.\n\n'
                      'Mümkünse süresi kısa, yalnızca gerekli depolara yetkili fine-grained token kullanın.',
                    ),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))],
                ),
              ),
            ),
          ],
        ),

        // ---------------- Veri ----------------
        _Section(
          title: 'Veri ve kısayollar',
          children: [
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Geçmiş kayıt sınırı'),
              subtitle: Text('Son ${s.historyLimit} gönderim saklanır'),
              onTap: () async {
                final v = await _pick<int>(
                  'Geçmiş kayıt sınırı',
                  {for (final n in AppSettings.historyLimitOptions) n: '$n kayıt'},
                  s.historyLimit,
                );
                if (v != null) set((c) => c.copyWith(historyLimit: v));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Geçmişi temizle'),
              onTap: () async {
                final upload = Provider.of<UploadProvider>(context, listen: false);
                final ok = await ConfirmDialog.show(
                  context,
                  title: 'Geçmiş temizlensin mi?',
                  content: 'Tüm yerel gönderim kayıtları silinecek.',
                  isDestructive: true,
                );
                if (ok) {
                  await upload.clearHistory();
                  _snack('Geçmiş temizlendi.');
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Hazır klasör kısayolları', style: theme.textTheme.bodyMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _shortcuts.length; i++)
                    Chip(
                      label: Text(_shortcuts[i]),
                      onDeleted: () async {
                        final updated = List<String>.from(_shortcuts)..removeAt(i);
                        await _storage.saveShortcuts(updated);
                        setState(() => _shortcuts = updated);
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _shortcutCtrl,
                      autocorrect: false,
                      decoration: const InputDecoration(hintText: 'Yeni kısayol (ör. docs/)', isDense: true),
                      onSubmitted: (_) => _addShortcut(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(onPressed: _addShortcut, icon: const Icon(Icons.add)),
                  IconButton(
                    tooltip: 'Varsayılana dön',
                    onPressed: () async {
                      await _storage.resetShortcuts();
                      await _loadShortcuts();
                    },
                    icon: const Icon(Icons.restore),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: const Text('Ayarları sıfırla'),
              onTap: _resetAll,
            ),
          ],
        ),

        // ---------------- Hakkında ----------------
        _Section(
          title: 'Hakkında',
          children: [
            const ListTile(
              leading: GitpushLogo(size: 40),
              title: Text('Gitpush'),
              subtitle: Text('Sürüm $kAppVersion · Android odaklı mobil Git istemcisi'),
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('Açık kaynak lisansları'),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Gitpush',
                applicationVersion: kAppVersion,
                applicationIcon: const Padding(padding: EdgeInsets.all(12), child: GitpushLogo(size: 56)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addShortcut() async {
    final added = await _storage.addShortcut(_shortcutCtrl.text);
    if (!mounted) return;
    if (added) {
      _shortcutCtrl.clear();
      await _loadShortcuts();
    } else {
      _snack('Geçersiz veya zaten var.');
    }
  }

  static String _hhmm(DateTime d) {
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  static String _timeoutLabel(int sec) {
    if (sec == 0) return 'Her seferinde (dosya seçici sonrası da)';
    if (sec < 60) return '$sec saniye sonra';
    return '${sec ~/ 60} dakika sonra';
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
            child: Text(
              title.toUpperCase(),
              style: AppTheme.monoBold.copyWith(fontSize: 11.5, letterSpacing: 1.0, color: theme.colorScheme.primary),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ],
      ),
    );
  }
}

// --- lib/screens/setup_screen.dart ---
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _clientIdController = TextEditingController();
  bool _obscureToken = true;

  /// true: yalnızca herkese açık depolar (`public_repo`), false: tüm depolar (`repo`).
  bool _publicOnly = false;

  @override
  void dispose() {
    _clientIdController.dispose();
    _tokenController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _showHelpSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: ListView(
                controller: controller,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'GitHub Token Nasıl Alınır?',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text('1. GitHub hesabınızda sağ üstteki profilinize tıklayın.'),
                  const SizedBox(height: 6),
                  const Text('2. Settings -> Developer settings -> Personal access tokens -> Tokens (classic) yolunu izleyin.'),
                  const SizedBox(height: 6),
                  const Text('3. "Generate new token (classic)" butonuna basın.'),
                  const SizedBox(height: 6),
                  const Text('4. Gerekli İzinler (Scopes):'),
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• repo (Zorunlu: depolara erişim, commit ve Actions çalışmalarını okuma/tetikleme)', style: AppTheme.monoBold.copyWith(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('• workflow (.github/workflows/ altındaki dosyaları göndermek/değiştirmek için; yoksa GitHub bu dosyaları reddeder)', style: AppTheme.monoBold.copyWith(fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text("5. \"Generate token\" deyip ghp_ ile başlayan tokenı kopyalayın ve Gitpush'a yapıştırın."),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () async {
                      await openExternalUrl(
                        context,
                        'https://github.com/settings/tokens/new?scopes=repo,workflow&description=Gitpush%20App',
                      );
                    },
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('GitHub Token Sayfasını Aç'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Client ID girilmesini ister. Kaydedilirse `true` döner.
  Future<bool> _promptClientId() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _clientIdController.text = auth.effectiveClientId;
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('GitHub ile giriş kurulumu'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Token yapıştırmadan girmek için ücretsiz bir OAuth App gerekir (tek seferlik, 1 dakika):'),
                const SizedBox(height: 8),
                const Text(
                  '1. GitHub → Settings → Developer settings → OAuth Apps → New OAuth App\n'
                  '2. Callback URL olarak https://github.com yazın\n'
                  '3. Oluşturunca "Enable Device Flow" kutusunu işaretleyin\n'
                  "4. Client ID'yi aşağıya yapıştırın (Client secret gerekmez)",
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () => openExternalUrl(ctx, 'https://github.com/settings/applications/new'),
                  icon: const Icon(Icons.open_in_browser, size: 16),
                  label: const Text('OAuth App oluştur'),
                ),
                TextField(
                  controller: _clientIdController,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: AppTheme.monoStyle.copyWith(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Client ID',
                    hintText: 'Ov23li...',
                    errorText: errorText,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await auth.setClientId(_clientIdController.text);
                if (ok) {
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } else {
                  setDialogState(() => errorText = 'Geçersiz Client ID biçimi');
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    return saved ?? false;
  }

  Future<void> _handleDeviceLogin() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);

    // Client ID yoksa (derlemede gömülü değil, kullanıcı da girmemiş) önce iste.
    if (!auth.deviceFlowAvailable) {
      final ok = await _promptClientId();
      if (!ok || !mounted) return;
    }

    final success = await auth.loginWithDeviceFlow(
      authorName: _nameController.text.trim(),
      authorEmail: _emailController.text.trim(),
      scope: _publicOnly ? GitHubDeviceFlow.scopePublic : GitHubDeviceFlow.scopeAll,
      onCode: (info) async {
        // Kod panoya kopyalanır ve GitHub doğrulama sayfası açılır.
        await Clipboard.setData(ClipboardData(text: info.userCode));
        if (mounted) await openExternalUrl(context, info.verificationUri);
      },
    );
    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    }
  }

  Widget _buildDeviceFlowSection(BuildContext context, AuthProvider auth) {
    final theme = Theme.of(context);
    final info = auth.deviceInfo;

    if (info != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              "GitHub'da bu kodu girin",
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            SelectableText(
              info.userCode,
              style: AppTheme.monoBold.copyWith(fontSize: 28, letterSpacing: 3),
            ),
            const SizedBox(height: 6),
            Text(
              'Kod panoya kopyalandı. Onayladığınızda uygulama otomatik giriş yapar.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => openExternalUrl(context, info.verificationUri),
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: const Text("GitHub'ı Aç"),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: auth.cancelDeviceFlow,
                  child: const Text('İptal'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment<bool>(value: false, label: Text('Tüm depolar')),
            ButtonSegment<bool>(value: true, label: Text('Yalnız herkese açık')),
          ],
          selected: {_publicOnly},
          onSelectionChanged: (selection) => setState(() => _publicOnly = selection.first),
        ),
        const SizedBox(height: 6),
        Text(
          _publicOnly
              ? 'Yalnızca herkese açık (public) depolara erişir; özel depolarınıza dokunamaz.'
              : 'Özel ve herkese açık tüm depolarınıza erişir.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: auth.isLoading ? null : _handleDeviceLogin,
          icon: const Icon(Icons.login),
          label: const Text('GitHub ile Giriş Yap'),
        ),
        if (auth.canEditClientId)
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: auth.isLoading ? null : _promptClientId,
              child: Text(auth.deviceFlowAvailable ? "Client ID'yi değiştir" : 'Client ID ayarla'),
            ),
          ),
      ],
    );
  }

  Future<void> _handleLogin() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen Personal Access Token giriniz.')),
      );
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final success = await auth.loginWithToken(
      token: token,
      authorName: _nameController.text.trim(),
      authorEmail: _emailController.text.trim(),
    );

    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                color: theme.colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo ve Başlık
                      const GitpushLogo(size: 84),
                      const SizedBox(height: 16),
                      Text(
                        'Gitpush',
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Telefonda kod yazmadan GitHub reposuna dosya aktarın',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),

                      // 3 Adımlı Gösterge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStepItem(context, '1', 'Giriş Yap'),
                          _buildStepDivider(),
                          _buildStepItem(context, '2', 'Bilgi Gir'),
                          _buildStepDivider(),
                          _buildStepItem(context, '3', 'Doğrula'),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // GitHub ile Giriş (Device Flow) - her zaman görünür; Client ID yoksa ilk dokunuşta istenir
                      ...[
                        _buildDeviceFlowSection(context, auth),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'veya token ile',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Token Alanı
                      TextField(
                        controller: _tokenController,
                        obscureText: _obscureToken,
                        // Token klavye önerilerine / öğrenme sözlüğüne / otomatik
                        // doldurmaya sızmasın
                        enableSuggestions: false,
                        autocorrect: false,
                        enableIMEPersonalizedLearning: false,
                        keyboardType: TextInputType.visiblePassword,
                        style: AppTheme.monoStyle.copyWith(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Personal Access Token',
                          hintText: 'ghp_xxxxxxxxxxxx',
                          prefixIcon: const Icon(Icons.key),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureToken ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscureToken = !_obscureToken),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Yazar Adı (Opsiyonel)
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Commit Yazar Adı (Opsiyonel)',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Yazar E-posta (Opsiyonel)
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Commit Yazar E-postası (Opsiyonel)',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Yardım Butonu
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _showHelpSheet,
                          icon: const Icon(Icons.help_outline, size: 16),
                          label: const Text('Token nasıl alınır?'),
                        ),
                      ),

                      // Hata Mesajı
                      if (auth.errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          auth.errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Giriş Butonu
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: (auth.isLoading || auth.isDeviceFlowActive) ? null : _handleLogin,
                          child: auth.isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                )
                              : const Text('Giriş Yap ve Doğrula'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepItem(BuildContext context, String number, String label) {
    final theme = Theme.of(context);
    return Column(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          child: Text(number, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
        ),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
      ],
    );
  }

  Widget _buildStepDivider() {
    return Container(width: 24, height: 1, color: Colors.grey.shade400);
  }
}

// --- lib/screens/zip_transfer_screen.dart ---
class ZipTransferScreen extends StatefulWidget {
  const ZipTransferScreen({super.key});

  @override
  State<ZipTransferScreen> createState() => _ZipTransferScreenState();
}

class _ZipTransferScreenState extends State<ZipTransferScreen> {
  late final TextEditingController _targetPathController;
  final TextEditingController _commitMessageController = TextEditingController();

  int _lastTreeRevision = -1;

  @override
  void initState() {
    super.initState();
    final custom = Provider.of<SettingsProvider>(context, listen: false).settings.defaultCommitMessage;
    _commitMessageController.text = custom.isNotEmpty ? custom : 'Gitpush: zip aktarımı';
    final upload = Provider.of<UploadProvider>(context, listen: false);
    _targetPathController = TextEditingController(text: upload.zipPrefix);
  }

  @override
  void dispose() {
    _targetPathController.dispose();
    _commitMessageController.dispose();
    super.dispose();
  }

  Future<void> _pickZipFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);

      if (bytes != null) {
        if (!mounted) return;
        final upload = Provider.of<UploadProvider>(context, listen: false);
        try {
          upload.setZipArchive(fileName: file.name, bytes: bytes);
        } on ZipServiceException catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        }
      }
    }
  }

  void _showPathPicker() {
    final repoProvider = Provider.of<RepoProvider>(context, listen: false);
    final upload = Provider.of<UploadProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => PathPickerSheet(
        repoTree: repoProvider.currentTree,
        fileName: '',
        onPathSelected: (selectedPath) {
          _targetPathController.text = selectedPath;
          upload.setZipPrefix(selectedPath);
        },
      ),
    );
  }

  Future<bool> _onWillPop() async {
    final uploadProvider = Provider.of<UploadProvider>(context, listen: false);
    if (uploadProvider.zipFiles.isNotEmpty) {
      final ok = await ConfirmDialog.show(
        context,
        title: 'Vazgeçilsin mi?',
        content: 'Yüklenen ZIP dosyası ve seçimleriniz sıfırlanacak.',
      );
      if (ok) uploadProvider.resetZip();
      return ok;
    }
    uploadProvider.resetZip();
    return true;
  }

  Future<void> _goToPreview() async {
    final uploadProvider = Provider.of<UploadProvider>(context, listen: false);
    final selectedCount = uploadProvider.zipFiles.where((f) => f.isSelected).length;

    if (selectedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir dosya seçin.')),
      );
      return;
    }

    // Provider'daki nesneler değiştirilmez; önizleme öneklenmiş kopyaları okur.
    await PreviewScreen.open(
      context,
      source: PreviewSource.zip,
      commitMessage: _commitMessageController.text.trim(),
    );
  }

  Future<void> _onDeleteUnlistedChanged(UploadProvider upload, bool value) async {
    if (value) {
      final ok = await ConfirmDialog.show(
        context,
        title: 'Emin misiniz?',
        content: 'Hedef klasör kapsamındaki, ZIP\'te olmayan repo dosyaları silinecek. '
            'Silinecek dosyaları önizlemede tek tek göreceksiniz.',
        isDestructive: true,
      );
      if (ok) upload.setZipDeleteUnlisted(true);
    } else {
      upload.setZipDeleteUnlisted(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uploadProvider = Provider.of<UploadProvider>(context);
    final repo = Provider.of<RepoProvider>(context);
    final files = uploadProvider.zipFiles;
    final selectedCount = files.where((f) => f.isSelected).length;

    // Repo/dal/ağaç değişince (veya ilk açılışta) durumları yeniden hesapla.
    if (_lastTreeRevision != repo.treeRevision) {
      _lastTreeRevision = repo.treeRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        uploadProvider.reclassifyAll(repo.treeIndex, truncated: repo.treeTruncated);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("ZIP'ten Aktar (Mod A)"),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. ZIP Seç Bölümü
                SectionCard(
                  title: '1. ZIP Dosyası',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (uploadProvider.zipFileName == null) ...[
                        OutlinedButton.icon(
                          onPressed: _pickZipFile,
                          icon: const Icon(Icons.file_open_outlined),
                          label: const Text('Telefonunuzdan .ZIP Seçin'),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            const Icon(Icons.archive, color: AppTheme.statusUpdate),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    uploadProvider.zipFileName!,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '${(uploadProvider.zipFileSize / 1024).toStringAsFixed(1)} KB · ${files.length} dosya ayıklandı',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: _pickZipFile,
                              child: const Text('Değiştir'),
                            ),
                          ],
                        ),
                        if (uploadProvider.zipInvalidEntries.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${uploadProvider.zipInvalidEntries.length} girdi geçersiz/güvensiz yol içerdiği için atlandı.',
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Dosyalar Ağacı ve Filtre
                if (files.isNotEmpty) ...[
                  SectionCard(
                    title: '2. Aktarılacak Dosyalar ($selectedCount/${files.length})',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: () => uploadProvider.selectAllZipFiles(true),
                              child: const Text('Tümünü Seç'),
                            ),
                            TextButton(
                              onPressed: () => uploadProvider.selectAllZipFiles(false),
                              child: const Text('Hiçbirini Seçme'),
                            ),
                          ],
                        ),
                        FileTreeView(
                          files: files,
                          onToggle: (index) {
                            uploadProvider.toggleZipFileSelection(
                              index,
                              !files[index].isSelected,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 3. Seçenekler
                SectionCard(
                  title: '3. Aktarım Seçenekleri',
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _targetPathController,
                              style: AppTheme.monoStyle.copyWith(fontSize: 12),
                              onChanged: uploadProvider.setZipPrefix,
                              decoration: const InputDecoration(
                                labelText: 'Hedef Klasör (Boş = Repo Kökü)',
                                hintText: 'örnek: src/ veya packages/app/',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: _showPathPicker,
                            icon: const Icon(Icons.folder_open),
                            tooltip: 'Klasör seç',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("ZIP'in tek üst klasörünü kaldır"),
                        subtitle: const Text('Örn: "proje-master/..." kökünü düzleştirir'),
                        value: uploadProvider.zipStripRootDir,
                        onChanged: uploadProvider.setZipStripRootDir,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Yolları repoya otomatik eşleştir'),
                        subtitle: const Text(
                          'ZIP\'teki fazla/eksik klasörleri repodaki gerçek konuma uydurur '
                          '(Hedef Klasör doluysa devre dışı)',
                        ),
                        value: uploadProvider.zipAutoAlign,
                        onChanged: uploadProvider.setZipAutoAlign,
                      ),
                      if (uploadProvider.zipAlignNotice != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              uploadProvider.zipAlignNotice!,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Mevcut dosyaların üzerine yaz'),
                        subtitle: const Text('Kapalıysa repoda zaten var olan yollar atlanır'),
                        value: uploadProvider.zipOverwriteExisting,
                        onChanged: uploadProvider.setZipOverwriteExisting,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Repoda olup ZIP'te olmayanları SİL"),
                        subtitle: const Text(
                          'DİKKAT: Yalnızca hedef klasör (veya ZIP\'in kapsadığı üst klasörler) '
                          'içindeki dosyalar silinir. Önizlemede ayrıca onaylanır.',
                        ),
                        value: uploadProvider.zipDeleteUnlisted,
                        onChanged: (val) => _onDeleteUnlistedChanged(uploadProvider, val),
                      ),
                      if (uploadProvider.zipDeleteNotice != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            uploadProvider.zipDeleteNotice!,
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _commitMessageController,
                        decoration: const InputDecoration(
                          labelText: 'Commit Mesajı',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SendBottomBar(
          summaryText: '$selectedCount dosya seçili',
          buttonLabel: 'Önizle ve Gönder',
          onButtonPressed: files.isEmpty ? null : _goToPreview,
        ),
      ),
    );
  }
}

// =============================================================================
// 8. GİRİŞ NOKTASI (MAIN)
// =============================================================================

// --- lib/main.dart ---
/// Ayarlardaki süre kadar hiç açılmayan oturum (token) cihazdan silinir.
/// Silindiyse true döner. Açılışta, oturum yüklenmeden ÖNCE çağrılır.
Future<bool> applyAutoLogout(StorageService storage, AppSettings settings, {DateTime? now}) async {
  final days = settings.autoLogoutDays;
  if (days <= 0) return false;
  final last = await storage.getLastActive();
  if (last == null) return false;
  if ((now ?? DateTime.now()).difference(last).inDays >= days) {
    await storage.clearAllUserData();
    return true;
  }
  return false;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cihaz tablet mi telefon mu, ilk kare çizilmeden önce belirlenir.
  // Tabletlerde uygulama sadece yatay modda çalışır (dik mod gerekmiyor);
  // telefonlarda mevcut davranış (serbest dönüş) korunur.
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final isTablet = Responsive.isTabletFromView(view);

  await SystemChrome.setPreferredOrientations(
    isTablet
        ? const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        : const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
  );

  final storage = StorageService();

  final settingsProvider = SettingsProvider(storage: storage);
  await settingsProvider.load();

  // Uzun süre kullanılmayan oturumu kapat (ayarlardan açılırsa).
  await applyAutoLogout(storage, settingsProvider.settings);
  await storage.touchLastActive();

  final themeProvider = ThemeProvider();
  await themeProvider.initTheme();

  final authProvider = AuthProvider();
  await authProvider.checkSavedAuth();

  final lockProvider = AppLockProvider(storage: storage);
  await lockProvider.init(settingsProvider.settings);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: lockProvider),
        ChangeNotifierProvider(create: (_) => RepoProvider()),
        ChangeNotifierProvider(create: (_) => UploadProvider()),
      ],
      child: const GitpushApp(),
    ),
  );
}

class GitpushApp extends StatelessWidget {
  const GitpushApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final settings = Provider.of<SettingsProvider>(context).settings;
    final seed = Color(settings.accentColorValue);

    return MaterialApp(
      title: 'Gitpush',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: AppTheme.build(seed: seed, brightness: Brightness.light),
      darkTheme: AppTheme.build(seed: seed, brightness: Brightness.dark, amoled: settings.amoledDark),
      themeMode: themeProvider.themeMode,
      builder: (context, child) => AppLockGate(child: child ?? const SizedBox.shrink()),
      home: authProvider.isAuthenticated
          ? const MainShell()
          : const SetupScreen(),
    );
  }
}
