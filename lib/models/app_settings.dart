import 'dart:convert';

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
