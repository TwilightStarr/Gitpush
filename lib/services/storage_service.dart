import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/history_item.dart';

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
