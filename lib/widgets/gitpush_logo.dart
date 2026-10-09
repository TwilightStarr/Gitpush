import 'package:flutter/material.dart';

/// Gitpush logosu: koyu zemin üzerinde yukarı ok (push) ve altında commit
/// düğümü. `assets/icon/icon.svg` ile aynı geometri; ek paket (flutter_svg)
/// gerekmeden `CustomPainter` ile çizilir, her boyutta keskindir.
class GitpushLogo extends StatelessWidget {
  final double size;

  /// Köşe yuvarlaklığı oranı (0.219 ≈ 28/128, ikonla aynı).
  final double radiusFactor;

  const GitpushLogo({super.key, this.size = 72, this.radiusFactor = 0.219});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter(radiusFactor)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final double radiusFactor;

  const _LogoPainter(this.radiusFactor);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 128.0);

    // Düz zemin
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 128, 128),
        Radius.circular(128 * radiusFactor),
      ),
      Paint()..color = const Color(0xFF0E1015),
    );

    // Ok: gövde + uç
    final arrow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFFFFFFF);
    canvas.drawPath(
      Path()
        ..moveTo(64, 88)
        ..lineTo(64, 32),
      arrow,
    );
    canvas.drawPath(
      Path()
        ..moveTo(46, 50)
        ..lineTo(64, 32)
        ..lineTo(82, 50),
      arrow,
    );

    // Commit düğümü: okun çıktığı nokta (zemin renginde ince halka ile ayrılır)
    const node = Offset(64, 92);
    canvas.drawCircle(node, 11, Paint()..color = const Color(0xFF8C9BFF));
    canvas.drawCircle(
      node,
      11,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFF0E1015),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) => oldDelegate.radiusFactor != radiusFactor;
}
