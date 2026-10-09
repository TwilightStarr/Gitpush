import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

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
