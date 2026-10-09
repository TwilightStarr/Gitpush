import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/repo_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/upload_provider.dart';
import '../services/app_lock_service.dart';
import '../utils/app_navigator.dart';
import '../widgets/gitpush_logo.dart';
import '../widgets/pin_pad.dart';
import 'setup_screen.dart';

/// Uygulama kilitliyken tüm içeriğin üstünü örten PIN ekranı.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  int _resetToken = 0;
  String? _error;
  bool _busy = false;
  bool _showForgot = false;
  Duration _lockLeft = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refreshLockout();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLockout() async {
    final lock = Provider.of<AppLockProvider>(context, listen: false);
    final left = await lock.service.lockoutRemaining();
    if (!mounted) return;
    _startCountdown(left);
  }

  void _startCountdown(Duration left) {
    _timer?.cancel();
    setState(() => _lockLeft = left);
    if (left <= Duration.zero) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final next = _lockLeft - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        t.cancel();
        setState(() {
          _lockLeft = Duration.zero;
          _error = null;
          _resetToken++;
        });
      } else {
        setState(() => _lockLeft = next);
      }
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m > 0 ? '$m dk ${s.toString().padLeft(2, '0')} sn' : '$s sn';
  }

  Future<void> _onPin(String pin) async {
    if (_busy || _lockLeft > Duration.zero) return;
    setState(() => _busy = true);
    final lock = Provider.of<AppLockProvider>(context, listen: false);
    final result = await lock.tryUnlock(pin);
    if (!mounted) return;
    if (result.ok) return; // kilit kalktı; bu ekran ağaçtan çıkar
    setState(() {
      _busy = false;
      _resetToken++;
      if (result.isLockedOut) {
        _error = 'Çok fazla hatalı deneme.';
      } else {
        final left = AppLockService.freeAttempts - result.failedAttempts;
        _error = left > 0 ? 'Hatalı PIN. Kalan deneme: $left' : 'Hatalı PIN.';
      }
    });
    if (result.isLockedOut) _startCountdown(result.lockedFor);
  }

  Future<void> _wipeAndLogout() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final repo = Provider.of<RepoProvider>(context, listen: false);
    final upload = Provider.of<UploadProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final lock = Provider.of<AppLockProvider>(context, listen: false);

    repo.reset();
    upload.resetAll();
    await auth.logout();
    await settings.update((c) => c.copyWith(appLockEnabled: false));
    await lock.wipe();
    appNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const SetupScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = Provider.of<AuthProvider>(context);
    final lockedOut = _lockLeft > Duration.zero;

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GitpushLogo(size: 72),
                  const SizedBox(height: 16),
                  Text('Gitpush kilitli', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    auth.username != null ? '@${auth.username} için PIN girin' : 'Devam etmek için PIN girin',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  if (lockedOut) ...[
                    Icon(Icons.timer_outlined, color: theme.colorScheme.error, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      'Çok fazla hatalı deneme.\n${_fmt(_lockLeft)} sonra tekrar deneyin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 16),
                  ] else
                    PinPad(
                      onCompleted: _onPin,
                      errorText: _error,
                      enabled: !_busy,
                      resetToken: _resetToken,
                    ),
                  const SizedBox(height: 8),
                  if (!_showForgot)
                    TextButton(
                      onPressed: () => setState(() => _showForgot = true),
                      child: const Text('PIN\'imi unuttum'),
                    )
                  else
                    Card(
                      color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              'PIN geri alınamaz. Sıfırlamak için oturum kapatılır; kayıtlı token, '
                              'yazar bilgileri ve geçmiş bu cihazdan silinir. Tekrar giriş yapmanız gerekir.',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => setState(() => _showForgot = false),
                                    child: const Text('Vazgeç'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                                    onPressed: _wipeAndLogout,
                                    child: const Text('Sıfırla'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
