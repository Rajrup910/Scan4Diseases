import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Renders expanding radial orbs and concentric echo rings.
/// - When `isError == false`: Clinical Emerald / Mint / Jade palette
/// - When `isError == true`: Clinical Crimson / Ruby / Wine palette
class ExpandingOrbsPainter extends CustomPainter {
  final double progress; // 0.0 -> 1.0
  final double opacity;  // 0.0 -> 1.0
  final bool isError;

  ExpandingOrbsPainter({
    required this.progress,
    required this.opacity,
    this.isError = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.001) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.longestSide * 1.55;

    // Base background with increasing darkness on escalation and soft wash on de-escalation
    final baseColor = isError ? const Color(0xFF250606) : const Color(0xFF022C22);
    final basePaint = Paint()
      ..color = baseColor.withValues(alpha: (opacity * 0.98).clamp(0.0, 1.0));
    canvas.drawRect(Offset.zero & size, basePaint);

    final orbs = isError
        ? [
            // Shade 1: Soft Rose / Coral (Lightest)
            OrbSpec(
              centerOffset: const Offset(0, 0),
              delay: 0.0,
              speed: 1.0,
              colorStart: const Color(0xFFFDA4AF),
              colorMid: const Color(0xFFF87171),
              colorEnd: const Color(0xFFEF4444),
            ),
            // Shade 2: Vivid Ruby / Scarlet (Medium)
            OrbSpec(
              centerOffset: Offset(-size.width * 0.07, -size.height * 0.05),
              delay: 0.06,
              speed: 1.2,
              colorStart: const Color(0xFFEF4444),
              colorMid: const Color(0xFFE11D48),
              colorEnd: const Color(0xFFDC2626),
            ),
            // Shade 3: Deep Crimson / Burgundy (Dark)
            OrbSpec(
              centerOffset: Offset(size.width * 0.09, size.height * 0.06),
              delay: 0.12,
              speed: 1.4,
              colorStart: const Color(0xFFB91C1C),
              colorMid: const Color(0xFF991B1B),
              colorEnd: const Color(0xFF7F1D1D),
            ),
            // Shade 4: Dark Wine / Maroon Abyss (Darkest covering screen)
            OrbSpec(
              centerOffset: Offset(-size.width * 0.05, size.height * 0.07),
              delay: 0.18,
              speed: 1.65,
              colorStart: const Color(0xFF7F1D1D),
              colorMid: const Color(0xFF4C0519),
              colorEnd: const Color(0xFF450A0A),
            ),
          ]
        : [
            // Shade 1: Light Mint / Cyan / Spring (Lightest)
            OrbSpec(
              centerOffset: const Offset(0, 0),
              delay: 0.0,
              speed: 1.0,
              colorStart: const Color(0xFFA7F3D0),
              colorMid: const Color(0xFF6EE7B7),
              colorEnd: const Color(0xFF2DD4BF),
            ),
            // Shade 2: Electric Emerald / Teal (Medium)
            OrbSpec(
              centerOffset: Offset(-size.width * 0.07, -size.height * 0.05),
              delay: 0.06,
              speed: 1.2,
              colorStart: const Color(0xFF10B981),
              colorMid: const Color(0xFF14B8A6),
              colorEnd: const Color(0xFF0D9488),
            ),
            // Shade 3: Deep Jade / Forest (Dark)
            OrbSpec(
              centerOffset: Offset(size.width * 0.09, size.height * 0.06),
              delay: 0.12,
              speed: 1.4,
              colorStart: const Color(0xFF059669),
              colorMid: const Color(0xFF0F766E),
              colorEnd: const Color(0xFF047857),
            ),
            // Shade 4: Ultra Deep Emerald Abyss (Darkest covering screen)
            OrbSpec(
              centerOffset: Offset(-size.width * 0.05, size.height * 0.07),
              delay: 0.18,
              speed: 1.65,
              colorStart: const Color(0xFF064E3B),
              colorMid: const Color(0xFF134E4A),
              colorEnd: const Color(0xFF022C22),
            ),
          ];

    for (final orb in orbs) {
      final orbProgress = ((progress - orb.delay) / (1.0 - orb.delay)).clamp(0.0, 1.0);
      if (orbProgress <= 0.0) continue;

      final currentRadius = Curves.easeOutCubic.transform(orbProgress) * maxRadius * orb.speed;
      final orbCenter = center + orb.centerOffset;

      final Color currentCenterColor;
      final Color currentOuterColor;
      final Color endBaseColor = isError ? const Color(0xFF250606) : const Color(0xFF08332C);
      if (orbProgress < 0.45) {
        final t = orbProgress / 0.45;
        currentCenterColor = Color.lerp(orb.colorStart, orb.colorMid, t)!;
        currentOuterColor = Color.lerp(orb.colorMid, orb.colorEnd, t)!;
      } else {
        final t = (orbProgress - 0.45) / 0.55;
        currentCenterColor = Color.lerp(orb.colorMid, orb.colorEnd, t)!;
        currentOuterColor = Color.lerp(orb.colorEnd, endBaseColor, t)!;
      }

      final orbPaint = Paint()
        ..shader = ui.Gradient.radial(
          orbCenter,
          currentRadius.clamp(1.0, double.infinity),
          [
            currentCenterColor.withValues(alpha: (opacity * 0.96).clamp(0.0, 1.0)),
            currentOuterColor.withValues(alpha: (opacity * 0.88).clamp(0.0, 1.0)),
            currentOuterColor.withValues(alpha: 0.0),
          ],
          [0.0, 0.70, 1.0],
        );

      canvas.drawCircle(orbCenter, currentRadius, orbPaint);
    }

    // Expanding glowing echo rings
    for (var i = 0; i < 4; i++) {
      final ringDelay = 0.06 * (i + 1);
      final ringProgress = ((progress - ringDelay) / (1.0 - ringDelay)).clamp(0.0, 1.0);
      if (ringProgress <= 0.0 || ringProgress >= 0.96) continue;

      final ringRadius = Curves.easeOutQuad.transform(ringProgress) * maxRadius * (1.05 + i * 0.18);
      final ringAlpha = (1.0 - ringProgress) * opacity * 0.50;

      final ringStartColor = isError ? const Color(0xFFFCA5A5) : const Color(0xFF6FE0CD);
      final ringEndColor = isError ? const Color(0xFFB3261E) : const Color(0xFF12695A);

      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 * (1.0 - ringProgress) + 1.0
        ..color = Color.lerp(
          ringStartColor,
          ringEndColor,
          ringProgress,
        )!.withValues(alpha: ringAlpha.clamp(0.0, 1.0));

      canvas.drawCircle(center, ringRadius, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ExpandingOrbsPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.opacity != opacity ||
      oldDelegate.isError != isError;
}

class OrbSpec {
  final Offset centerOffset;
  final double delay;
  final double speed;
  final Color colorStart;
  final Color colorMid;
  final Color colorEnd;

  const OrbSpec({
    required this.centerOffset,
    required this.delay,
    required this.speed,
    required this.colorStart,
    required this.colorMid,
    required this.colorEnd,
  });
}
