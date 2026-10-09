import 'package:flutter/material.dart';

/// Uygulama genelinde tek `Navigator` anahtarı. Bağlamı olmayan yerlerden
/// (ör. kilit ekranından "oturumu sıfırla") rota değiştirmek için kullanılır.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
