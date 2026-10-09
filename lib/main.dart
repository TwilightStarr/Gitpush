import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'models/app_settings.dart';
import 'providers/app_lock_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/repo_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/upload_provider.dart';
import 'screens/main_shell.dart';
import 'screens/setup_screen.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'utils/app_navigator.dart';
import 'utils/responsive.dart';
import 'widgets/app_lock_gate.dart';

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
