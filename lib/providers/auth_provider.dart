import 'package:flutter/material.dart';
import '../services/github_device_flow.dart';
import '../services/github_service.dart';
import '../services/storage_service.dart';

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
