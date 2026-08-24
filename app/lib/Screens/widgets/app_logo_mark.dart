import 'package:flutter/material.dart';
import '../theme.dart';

/// The Scan4Disease brandmark, drawn as a clean, frameless vector — the reticle
/// + medical-cross + aperture motif, in the glowing teal brand color.
///
/// Features a luminous neon halo glow and dark central aperture well.
class AppLogoMark extends StatelessWidget {
  final double size;
  final Color? color;

  /// Fill for the central aperture (the small inner disc). Defaults to dark well
  /// so the glowing cross reads with a high-contrast center.
  final Color? holeColor;

  /// Whether to render the vibrant neon specular glow.
  final bool glow;

  const AppLogoMark({
    super.key,
    this.size = 48,
    this.color,
    this.holeColor,
    this.glow = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Themes.tealGlow;
    final effectiveHoleColor = holeColor ?? const Color(0xFF0F172A);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _EmblemPainter(
          color: effectiveColor,
          holeColor: effectiveHoleColor,
          glow: glow,
        ),
      ),
    );
  }
}

class _EmblemPainter extends CustomPainter {
  final Color color;
  final Color holeColor;
  final bool glow;

  _EmblemPainter({
    required this.color,
    required this.holeColor,
    this.glow = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Author against the 48x48 canvas, then scale.
    final s = size.width / 48.0;
    canvas.save();
    canvas.scale(s);

    const c = Offset(24, 24);

    void drawGeometry(Canvas canvas, Paint stroke, Paint cross, Paint triPaint) {
      // Outer ring
      canvas.drawCircle(c, 16.5, stroke..strokeWidth = 2.4);

      // N / S / E / W reticle ticks
      canvas.drawLine(const Offset(24, 3.5), const Offset(24, 9.5), stroke);
      canvas.drawLine(const Offset(24, 38.5), const Offset(24, 44.5), stroke);
      canvas.drawLine(const Offset(3.5, 24), const Offset(9.5, 24), stroke);
      canvas.drawLine(const Offset(38.5, 24), const Offset(44.5, 24), stroke);

      // Thick cross
      canvas.drawLine(const Offset(24, 12.5), const Offset(24, 35.5), cross);
      canvas.drawLine(const Offset(12.5, 24), const Offset(35.5, 24), cross);

      // Central aperture ring
      canvas.drawCircle(c, 6, stroke..strokeWidth = 2.4);

      // Direction arrowhead inside the aperture
      final tri = Path()
        ..moveTo(24, 20.5)
        ..lineTo(26.6, 25)
        ..lineTo(21.4, 25)
        ..close();
      canvas.drawPath(tri, triPaint);
    }

    if (glow) {
      // Neon halo glow pass
      final glowStroke = Paint()
        ..style = PaintingStyle.stroke
        ..color = color.withValues(alpha: 0.65)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

      final glowCross = Paint()
        ..style = PaintingStyle.stroke
        ..color = color.withValues(alpha: 0.60)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);

      final glowTri = Paint()
        ..color = color.withValues(alpha: 0.70)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

      drawGeometry(canvas, glowStroke, glowCross, glowTri);
    }

    // Central aperture dark hole backing
    canvas.drawCircle(c, 6, Paint()..color = holeColor);

    // Crisp foreground pass
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cross = Paint()
      ..style = PaintingStyle.stroke
      ..color = color.withValues(alpha: 0.90)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.5;

    final triPaint = Paint()..color = color;

    drawGeometry(canvas, stroke, cross, triPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EmblemPainter old) =>
      old.color != color || old.holeColor != holeColor || old.glow != glow;
}
