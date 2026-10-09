import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../screens/lock_screen.dart';

/// `MaterialApp.builder` içinde kullanılır: uygulama kilitliyken içeriğin
/// üstüne PIN ekranını bindirir ve altındaki içeriğe dokunmayı/erişimi keser.
class AppLockGate extends StatelessWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final locked = Provider.of<AppLockProvider>(context).locked;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: locked,
          child: IgnorePointer(ignoring: locked, child: child),
        ),
        if (locked) const Positioned.fill(child: LockScreen()),
      ],
    );
  }
}
