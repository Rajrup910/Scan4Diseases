import 'dart:math' as math;
import 'package:flutter/material.dart';

/// An elegant, living surface for clinical green buttons that displays
/// smooth, organic undulating waves of bright emerald and deep dark green.
/// Contained within the button surface with subtle glass specular sheen.
class EmeraldWaves extends StatefulWidget {
  final Widget? child;
  final BorderRadius borderRadius;
  final Border? border;
  final double height;
  final double? width;

  const EmeraldWaves({
    super.key,
    this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.border,
    this.height = 52,
    this.width,
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
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
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

/// CustomPainter rendering multi-phase organic bright and dark green waves.
class EmeraldWavesPainter extends CustomPainter {
  final double progress;
  final BorderRadius borderRadius;
  final Border? border;

  EmeraldWavesPainter({
    required this.progress,
    required this.borderRadius,
    this.border,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);
    final t = progress * 2 * math.pi;

    // 1. Deep clinical base gradient
    final basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF15B79E),
          Color(0xFF0F766E),
          Color(0xFF0D544E),
          Color(0xFF064E3B),
        ],
        stops: [0.0, 0.38, 0.72, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, basePaint);

    // 2. Wave 1: Primary bright emerald/mint undulating pulse (harmonic 1)
    final wave1X = size.width * (0.35 + 0.30 * math.sin(t));
    final wave1Y = size.height * (0.50 + 0.35 * math.cos(t));
    final wave1Radius = math.max(size.width, size.height) * (0.60 + 0.15 * math.sin(t));

    final wave1Paint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          (wave1X / size.width) * 2 - 1,
          (wave1Y / size.height) * 2 - 1,
        ),
        radius: wave1Radius / (size.width > 0 ? size.width : 1),
        colors: [
          const Color(0xFF2DD4BF).withValues(alpha: 0.52),
          const Color(0xFF38E1C2).withValues(alpha: 0.22),
          Colors.transparent,
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, wave1Paint);

    // 3. Wave 2: Deep dark green counter-wave pulse (harmonic 1 with phase offset)
    final wave2X = size.width * (0.65 + 0.25 * math.cos(t + 1.2));
    final wave2Y = size.height * (0.50 + 0.30 * math.sin(t + 0.8));
    final wave2Radius = math.max(size.width, size.height) * (0.65 + 0.15 * math.cos(t));

    final wave2Paint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          (wave2X / size.width) * 2 - 1,
          (wave2Y / size.height) * 2 - 1,
        ),
        radius: wave2Radius / (size.width > 0 ? size.width : 1),
        colors: [
          const Color(0xFF042F2C).withValues(alpha: 0.58),
          const Color(0xFF0D544E).withValues(alpha: 0.20),
          Colors.transparent,
        ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, wave2Paint);

    // 4. Wave 3: Secondary bright sea-green ripple (harmonic 2)
    final wave3X = size.width * (0.20 + 0.20 * math.cos(2 * t + 2.0));
    final wave3Y = size.height * (0.70 + 0.20 * math.sin(2 * t + 1.0));
    final wave3Radius = math.max(size.width, size.height) * (0.50 + 0.10 * math.sin(t));

    final wave3Paint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          (wave3X / size.width) * 2 - 1,
          (wave3Y / size.height) * 2 - 1,
        ),
        radius: wave3Radius / (size.width > 0 ? size.width : 1),
        colors: [
          const Color(0xFF6FE0CD).withValues(alpha: 0.32),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, wave3Paint);

    // 5. Top glossy specular glass sheen
    final glossRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.50);
    final glossPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.25),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(glossRect);
    canvas.drawRRect(rrect, glossPaint);

    // 6. Subtle glass specular border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.50);
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant EmeraldWavesPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.borderRadius != borderRadius;
}
