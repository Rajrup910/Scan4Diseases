import 'dart:math' as math;
import 'package:flutter/material.dart';

/// An elegant, living surface for clinical green panels and buttons that displays
/// smooth, organic undulating sine waves of bright emerald, mint, and deep dark green.
/// Supports [reverse] to run waves in opposite directions across adjacent widgets.
class EmeraldWaves extends StatefulWidget {
  final Widget? child;
  final BorderRadius borderRadius;
  final Border? border;
  final double? height;
  final double? width;
  final bool reverse;
  final double speedMultiplier;

  const EmeraldWaves({
    super.key,
    this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.border,
    this.height,
    this.width,
    this.reverse = false,
    this.speedMultiplier = 1.0,
  });

  @override
  State<EmeraldWaves> createState() => _EmeraldWavesState();
}

class _EmeraldWavesState extends State<EmeraldWaves>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    final durationMs = (6000 / widget.speedMultiplier).round().clamp(1000, 20000);
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: CustomPaint(
            painter: EmeraldWavesPainter(
              progress: _ctrl.value,
              borderRadius: widget.borderRadius,
              border: widget.border,
              reverse: widget.reverse,
            ),
            child: Container(
              height: widget.height,
              width: widget.width,
              alignment: Alignment.center,
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

/// CustomPainter rendering multi-phase organic sine wave curves and gradients.
class EmeraldWavesPainter extends CustomPainter {
  final double progress;
  final BorderRadius borderRadius;
  final Border? border;
  final bool reverse;

  EmeraldWavesPainter({
    required this.progress,
    required this.borderRadius,
    this.border,
    this.reverse = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // Direct wave phase angle: if reverse is true, invert direction
    final t = (reverse ? (1.0 - progress) : progress) * 2 * math.pi;

    // 1. Deep clinical base gradient
    final basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF0F766E),
          Color(0xFF0D544E),
          Color(0xFF064E3B),
          Color(0xFF033327),
        ],
        stops: [0.0, 0.40, 0.78, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, basePaint);

    // 2. Wave 1: Primary Undulating Sine Wave Layer (Bright Emerald Crest)
    final wave1Path = Path();
    final wave1BaseY = h * 0.55;
    final wave1Amp = h * 0.18;
    final wave1Freq = 2 * math.pi / w;

    wave1Path.moveTo(0, h);
    wave1Path.lineTo(0, wave1BaseY + wave1Amp * math.sin(t));
    for (double x = 0; x <= w; x += 3.0) {
      final y = wave1BaseY + wave1Amp * math.sin(wave1Freq * x + t);
      wave1Path.lineTo(x, y);
    }
    wave1Path.lineTo(w, h);
    wave1Path.close();

    final wave1Paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF2DD4BF).withValues(alpha: 0.45),
          const Color(0xFF14B8A6).withValues(alpha: 0.20),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawPath(wave1Path, wave1Paint);

    // 3. Wave 2: Secondary Harmonic Sine Wave Layer (Mint/Sea-Green Counter Ripple)
    final wave2Path = Path();
    final wave2BaseY = h * 0.65;
    final wave2Amp = h * 0.14;
    final wave2Freq = 3 * math.pi / w;

    wave2Path.moveTo(0, h);
    wave2Path.lineTo(0, wave2BaseY + wave2Amp * math.cos(t * 1.3));
    for (double x = 0; x <= w; x += 3.0) {
      final y = wave2BaseY + wave2Amp * math.cos(wave2Freq * x + t * 1.3 + 1.2);
      wave2Path.lineTo(x, y);
    }
    wave2Path.lineTo(w, h);
    wave2Path.close();

    final wave2Paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF6FE0CD).withValues(alpha: 0.35),
          const Color(0xFF0F766E).withValues(alpha: 0.15),
          Colors.transparent,
        ],
        stops: const [0.0, 0.50, 1.0],
      ).createShader(rect);
    canvas.drawPath(wave2Path, wave2Paint);

    // 4. Moving Radial Glow along the wave crest
    final glowX = w * (0.35 + 0.35 * math.sin(t));
    final glowY = h * (0.45 + 0.25 * math.cos(t));
    final glowRadius = math.max(w, h) * 0.55;

    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          (glowX / w) * 2 - 1,
          (glowY / h) * 2 - 1,
        ),
        radius: glowRadius / w,
        colors: [
          const Color(0xFF38E1C2).withValues(alpha: 0.28),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, glowPaint);

    // 5. Top glossy specular glass sheen
    final glossRect = Rect.fromLTWH(0, 0, w, h * 0.45);
    final glossPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.22),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(glossRect);
    canvas.drawRRect(rrect, glossPaint);

    // 6. Subtle glass specular border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.40);
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant EmeraldWavesPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.reverse != reverse;
}
