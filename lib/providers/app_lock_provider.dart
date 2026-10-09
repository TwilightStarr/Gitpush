import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/app_lock_service.dart';
import '../services/storage_service.dart';

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
