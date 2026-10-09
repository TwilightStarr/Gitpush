import 'package:flutter/material.dart';

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
