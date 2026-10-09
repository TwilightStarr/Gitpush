import 'dart:ui';

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
