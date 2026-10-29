// GAnime logo mark, drawn (no asset, no SVG package): the folded-G path
// from the web top bar, gradient #064E3B → #059669 → #10B981 → #A3E635.
// Used with the text "nime" beside it, exactly like the web brand.
import 'package:flutter/material.dart';

class LogoMark extends StatelessWidget {
  final double size;
  const LogoMark({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoMarkPainter()),
    );
  }
}

class _LogoMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 512;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 50 * s
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          Color(0xFF064E3B),
          Color(0xFF059669),
          Color(0xFF10B981),
          Color(0xFFA3E635),
        ],
        stops: [0.0, 0.45, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final path = Path()
      ..moveTo(300 * s, 300 * s)
      ..lineTo(105 * s, 430 * s)
      ..lineTo(265 * s, 95 * s)
      ..lineTo(415 * s, 415 * s);
    canvas.drawPath(path, paint);
    final diamond = Path()
      ..moveTo(448 * s, 398 * s)
      ..lineTo(465 * s, 415 * s)
      ..moveTo(448 * s, 432 * s)
      ..lineTo(431 * s, 415 * s)
      ..close();
    canvas.drawPath(
        diamond,
        Paint()
          ..style = PaintingStyle.fill
          ..shader = paint.shader);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
