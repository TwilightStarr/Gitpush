import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../services/storage_service.dart';

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
