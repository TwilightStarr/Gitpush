import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
