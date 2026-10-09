import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_lock_service.dart';

/// 6 haneli PIN girişi: nokta göstergesi + sayısal tuş takımı.
/// [resetToken] değiştiğinde girilen rakamlar temizlenir.
class PinPad extends StatefulWidget {
  final ValueChanged<String> onCompleted;
  final String? errorText;
  final bool enabled;
  final int resetToken;

  const PinPad({
    super.key,
    required this.onCompleted,
    this.errorText,
    this.enabled = true,
    this.resetToken = 0,
  });

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  @override
  void didUpdateWidget(covariant PinPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken) {
      setState(() => _pin = '');
    }
  }

  void _add(String digit) {
    if (!widget.enabled || _pin.length >= AppLockService.pinLength) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += digit);
    if (_pin.length == AppLockService.pinLength) {
      final done = _pin;
      widget.onCompleted(done);
    }
  }

  void _back() {
    if (!widget.enabled || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget key(String label, {VoidCallback? onTap, Widget? child}) {
      return SizedBox(
        width: 72,
        height: 60,
        child: Material(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.enabled ? onTap : null,
            child: Center(
              child: child ??
                  Text(
                    label,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
            ),
          ),
        ),
      );
    }

    Widget row(List<String> digits) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final d in digits)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: key(d, onTap: () => _add(d)),
              ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < AppLockService.pinLength; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.symmetric(horizontal: 7),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? cs.primary : Colors.transparent,
                  border: Border.all(
                    color: widget.errorText != null ? cs.error : (i < _pin.length ? cs.primary : cs.outline),
                    width: 1.6,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(
          height: 36,
          child: Center(
            child: widget.errorText == null
                ? null
                : Text(
                    widget.errorText!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.error, fontSize: 12.5),
                  ),
          ),
        ),
        row(const ['1', '2', '3']),
        row(const ['4', '5', '6']),
        row(const ['7', '8', '9']),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 84),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: key('0', onTap: () => _add('0')),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: key(
                  '',
                  onTap: _back,
                  child: Icon(Icons.backspace_outlined, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
