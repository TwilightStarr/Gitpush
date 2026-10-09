import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../services/app_lock_service.dart';
import 'pin_pad.dart';

/// Mevcut PIN'i doğrulatır. Doğruysa true döner.
Future<bool> verifyCurrentPin(BuildContext context, {String title = 'Mevcut PIN'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => _PinDialog(title: title, mode: _PinMode.verify),
  );
  return r ?? false;
}

/// Yeni PIN'i iki kez girdirip kaydeder. Kaydedildiyse true döner.
Future<bool> createNewPin(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => const _PinDialog(title: 'Yeni PIN', mode: _PinMode.create),
  );
  return r ?? false;
}

enum _PinMode { verify, create }

class _PinDialog extends StatefulWidget {
  final String title;
  final _PinMode mode;

  const _PinDialog({required this.title, required this.mode});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  int _reset = 0;
  String? _error;
  String? _first; // create modunda ilk giriş
  bool _busy = false;

  Future<void> _onPin(String pin) async {
    final lock = Provider.of<AppLockProvider>(context, listen: false);
    if (widget.mode == _PinMode.verify) {
      setState(() => _busy = true);
      final r = await lock.service.verify(pin);
      if (!mounted) return;
      if (r.ok) {
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _busy = false;
        _reset++;
        _error = r.isLockedOut ? 'Çok fazla deneme. ${r.lockedFor.inSeconds} sn bekleyin.' : 'Hatalı PIN.';
      });
      return;
    }

    if (_first == null) {
      if (AppLockService.isWeakPin(pin)) {
        setState(() {
          _reset++;
          _error = 'Çok kolay bir PIN (tekrar eden / ardışık). Başka bir tane seçin.';
        });
        return;
      }
      setState(() {
        _first = pin;
        _reset++;
        _error = null;
      });
      return;
    }

    if (pin != _first) {
      setState(() {
        _first = null;
        _reset++;
        _error = 'PIN\'ler eşleşmedi. Baştan başlayın.';
      });
      return;
    }
    setState(() => _busy = true);
    await lock.service.setPin(pin);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.mode == _PinMode.create;
    final subtitle = creating
        ? (_first == null ? '${AppLockService.pinLength} haneli bir PIN seçin' : 'PIN\'i tekrar girin')
        : 'PIN\'inizi girin';
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            SizedBox(
              width: 260,
              child: FittedBox(
                child: PinPad(onCompleted: _onPin, errorText: _error, enabled: !_busy, resetToken: _reset),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
      ],
    );
  }
}
