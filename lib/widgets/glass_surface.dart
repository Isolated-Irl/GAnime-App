// Glass surface ported from REX-Player's Modifier.glassSurface (Compose).
// No backdrop blur: a near-transparent fill + inner highlight (top-left)
// + inner shadow (bottom-right) + hairline border.
import 'package:flutter/material.dart';

class GlassSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final Color fill;
  final Color border;
  final Color highlight;
  final Color shadow;
  final double blur;
  final Offset offset;

  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 12,
    this.fill = const Color(0x0DFFFFFF), // white 5%
    this.border = const Color(0x26FFFFFF), // white 15%
    this.highlight = const Color(0x59FFFFFF), // white 35%
    this.shadow = const Color(0x59000000), // black 35%
    this.blur = 5,
    this.offset = const Offset(-2, -2),
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _GlassPainter(radius, fill, highlight, shadow, blur, offset),
        foregroundPainter: _BorderPainter(radius, border),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: child,
        ),
      ),
    );
  }
}

class GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool circle;
  final bool active;

  const GlassButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.iconSize = 22,
    this.circle = false,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = circle ? size / 2 : 12.0;
    final primary = Theme.of(context).colorScheme.primary;
    return GlassSurface(
      radius: r,
      fill: active ? primary.withValues(alpha: 0.25) : const Color(0x0DFFFFFF),
      border: active ? primary.withValues(alpha: 0.35) : const Color(0x26FFFFFF),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              color: Colors.white,
              size: iconSize,
              shadows: const [
                Shadow(color: Color(0x66000000), blurRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassPainter extends CustomPainter {
  final double r, blur;
  final Color fill, hi, sh;
  final Offset off;
  _GlassPainter(this.r, this.fill, this.hi, this.sh, this.blur, this.off);

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(r));
    canvas.drawRRect(rrect, Paint()..color = fill);

    // Smooth glass edge: stroke the FULL rounded rect so the highlight
    // flows continuously around corners with no seams or chips.
    // Still cheaper than blur — flat gradient strokes, ~zero GPU per frame.
    canvas.save();
    canvas.clipRRect(rrect);
    // Highlight: bright at top-left, fading toward center.
    final hiPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.center,
        colors: [hi, hi.withValues(alpha: 0.0)],
      ).createShader(rect);
    canvas.drawRRect(rrect, hiPaint);
    // Shadow: dark at bottom-right, fading toward center.
    final shPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = LinearGradient(
        begin: Alignment.bottomRight,
        end: Alignment.center,
        colors: [sh, sh.withValues(alpha: 0.0)],
      ).createShader(rect);
    canvas.drawRRect(rrect, shPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassPainter o) =>
      o.r != r || o.fill != fill || o.hi != hi || o.sh != sh || o.blur != blur || o.off != off;
}

class _BorderPainter extends CustomPainter {
  final double r;
  final Color c;
  _BorderPainter(this.r, this.c);

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(r)).deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = c,
    );
  }

  @override
  bool shouldRepaint(_BorderPainter o) => o.c != c || o.r != r;
}
