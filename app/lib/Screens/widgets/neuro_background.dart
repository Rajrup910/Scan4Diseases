import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A live "blueprint" backdrop — a faint construction grid, a slow circular
/// guide and drifting red alignment ticks — echoing the Neurotrace web theme so
/// the visual language flows from the clinician portal into the mobile app.
///
/// It paints *behind* whatever [child] you give it and never intercepts input.
class NeuroBackground extends StatefulWidget {
  final Widget child;
  const NeuroBackground({super.key, required this.child});

  @override
  State<NeuroBackground> createState() => _NeuroBackgroundState();
}

class _NeuroBackgroundState extends State<NeuroBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // One slow loop — motion is ambient, never attention-grabbing.
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 48))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => CustomPaint(
                painter: _BlueprintPainter(_c.value, dark),
                isComplex: true,
                willChange: true,
              ),
            ),
          ),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

class _BlueprintPainter extends CustomPainter {
  final double t; // 0..1
  final bool dark;
  _BlueprintPainter(this.t, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;

    // --- base wash ---
    canvas.drawRect(
      rect,
      Paint()..color = dark ? const Color(0xFF0F1117) : const Color(0xFFF1F3F6),
    );

    // --- construction grid ---
    const gap = 56.0;
    final grid = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: dark ? 0.04 : 0.05)
      ..strokeWidth = 1;
    for (double x = 0; x <= w; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
    }
    for (double y = 0; y <= h; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }

    // Brand teal accent — replaces the old red, so the blueprint pattern flows
    // with the clinical green theme instead of jarring against it.
    const accent = Color(0xFF12695A); // == Themes.brand
    final cx = w * 0.5, cy = h * 0.42;

    // --- large circular guide, gently breathing ---
    final breathe = 1 + 0.015 * math.sin(2 * math.pi * t);
    final r = math.min(w, h) * 0.62 * breathe;
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: dark ? 0.14 : 0.10),
    );

    // --- cross-hair alignment lines (teal, subtle) ---
    final line = Paint()..strokeWidth = 1.2;
    canvas.drawLine(Offset(0, cy), Offset(w, cy),
        line..color = accent.withValues(alpha: dark ? 0.20 : 0.15));
    canvas.drawLine(Offset(cx, 0), Offset(cx, h),
        line..color = accent.withValues(alpha: dark ? 0.10 : 0.08));

    // --- drifting teal end ticks on the horizontal guide ---
    final drift = (t * 2 - 1); // -1..1 sweep
    final tick = Paint()..color = accent.withValues(alpha: 0.55);
    void rTick(double x) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, cy), width: 10, height: 22),
          const Radius.circular(2),
        ),
        tick,
      );
    }
    rTick(6);
    rTick(w - 6);
    // two inner sliding ticks
    rTick(w * (0.30 + 0.02 * drift));
    rTick(w * (0.70 - 0.02 * drift));

    // --- a couple of numbered blueprint tags ---
    _tag(canvas, Offset(w * 0.30 + w * 0.02 * drift - 20, cy - 44), '01');
    _tag(canvas, Offset(w * 0.70 - w * 0.02 * drift + 8, cy - 44), '02');
  }

  void _tag(Canvas canvas, Offset at, String label) {
    // Tag background: brand-dark teal to match the accent theme.
    final box = RRect.fromRectAndRadius(
      Rect.fromLTWH(at.dx, at.dy, 26, 18), const Radius.circular(3));
    canvas.drawRRect(box, Paint()..color = const Color(0xFF0D4F44).withValues(alpha: 0.85));
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFEDEDED),
          fontSize: 10,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at + Offset((26 - tp.width) / 2, (18 - tp.height) / 2));
  }

  @override
  bool shouldRepaint(covariant _BlueprintPainter old) =>
      old.t != t || old.dark != dark;
}
