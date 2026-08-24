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

    // Solid base background that fades in ensuring full opaque cover at peak
    final baseColor = isError ? const Color(0xFF250606) : const Color(0xFF08332C);
    final basePaint = Paint()
      ..color = baseColor.withValues(alpha: (opacity * 0.98).clamp(0.0, 1.0));
    canvas.drawRect(Offset.zero & size, basePaint);

    final orbs = isError
        ? [
            OrbSpec(
              centerOffset: const Offset(0, 0),
              delay: 0.0,
              speed: 1.0,
              colorStart: const Color(0xFFEF4444), // Vibrant crimson
              colorMid: const Color(0xFFB3261E),   // Deep clinical red
              colorEnd: const Color(0xFF7F1D1D),   // Dark ruby
            ),
            OrbSpec(
              centerOffset: Offset(-size.width * 0.08, -size.height * 0.06),
              delay: 0.05,
              speed: 1.15,
              colorStart: const Color(0xFFF87171), // Luminous rose
              colorMid: const Color(0xFFDC2626),   // Red
              colorEnd: const Color(0xFF991B1B),   // Dark crimson
            ),
            OrbSpec(
              centerOffset: Offset(size.width * 0.10, size.height * 0.07),
              delay: 0.10,
              speed: 1.3,
              colorStart: const Color(0xFFFCA5A5), // Coral highlight
              colorMid: const Color(0xFFB91C1C),   // Pure red
              colorEnd: const Color(0xFF450A0A),   // Deep maroon
            ),
            OrbSpec(
              centerOffset: Offset(-size.width * 0.06, size.height * 0.08),
              delay: 0.16,
              speed: 1.45,
              colorStart: const Color(0xFFEF4444),
              colorMid: const Color(0xFF991B1B),
              colorEnd: const Color(0xFF500724),
            ),
            OrbSpec(
              centerOffset: Offset(size.width * 0.05, -size.height * 0.09),
              delay: 0.22,
              speed: 1.6,
              colorStart: const Color(0xFFDC2626),
              colorMid: const Color(0xFFEF4444),
              colorEnd: const Color(0xFF250606),
            ),
          ]
        : [
            OrbSpec(
              centerOffset: const Offset(0, 0),
              delay: 0.0,
              speed: 1.0,
              colorStart: const Color(0xFF15B79E), // Vibrant mint emerald
              colorMid: const Color(0xFF12695A),   // Clinical jade
              colorEnd: const Color(0xFF0D4F44),   // Deep teal
            ),
            OrbSpec(
              centerOffset: Offset(-size.width * 0.08, -size.height * 0.06),
              delay: 0.05,
              speed: 1.15,
              colorStart: const Color(0xFF3EA893), // Luminous mint
              colorMid: const Color(0xFF15B79E),   // Emerald
              colorEnd: const Color(0xFF12695A),   // Jade
            ),
            OrbSpec(
              centerOffset: Offset(size.width * 0.10, size.height * 0.07),
              delay: 0.10,
              speed: 1.3,
              colorStart: const Color(0xFF6FE0CD), // Bright aqua/emerald
              colorMid: const Color(0xFF0F5D4F),   // Dark jade
              colorEnd: const Color(0xFF08332C),   // Deep pine
            ),
            OrbSpec(
              centerOffset: Offset(-size.width * 0.06, size.height * 0.08),
              delay: 0.16,
              speed: 1.45,
              colorStart: const Color(0xFF2F8A78),
              colorMid: const Color(0xFF12695A),
              colorEnd: const Color(0xFF0D4F44),
            ),
            OrbSpec(
              centerOffset: Offset(size.width * 0.05, -size.height * 0.09),
              delay: 0.22,
              speed: 1.6,
              colorStart: const Color(0xFF15B79E),
              colorMid: const Color(0xFF3EA893),
              colorEnd: const Color(0xFF08332C),
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
