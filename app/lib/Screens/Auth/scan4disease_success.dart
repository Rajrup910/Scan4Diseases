import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/app_logo_mark.dart';

/// Scan4Disease sign-in / sign-up success flourish.
///
/// A full-screen overlay played AFTER a successful [AuthService.login] or
/// [AuthService.register] returns. Three phases (jade → mint brand palette):
///
///   0 ─ 2200 ms  scan     — a jade reticle sweeps around the app logo, a soft
///                           glow pulses, "Scanning credentials…" pulses below.
///   2200 ─ 2600 ms morph  — the reticle contracts into a filled brand disc and
///                           a checkmark strokes on (400 ms cubic-easeOut).
///   2600 ─ 3400 ms burst  — a jade/mint particle ring bursts outward and fades.
///
/// Once the burst settles, the success card fades in with the user's name, email
/// and an optional short session token. Tapping "Launch AI Screening Portal"
/// dismisses the overlay — the [AuthGate] has already swapped the screen behind
/// it to the home shell, so the user lands directly on the app.
///
/// Push via a root navigator so the overlay survives the AuthGate rebuild:
///
///     Navigator.of(context, rootNavigator: true).push(
///       Scan4DiseaseSuccess.route(name: name, email: email),
///     );
class Scan4DiseaseSuccess extends StatefulWidget {
  const Scan4DiseaseSuccess({
    super.key,
    required this.name,
    required this.email,
    this.clinicalToken,
    this.onLaunch,
  });

  /// Display name (falls back to the local-part of [email] if blank).
  final String? name;
  final String email;

  /// Optional short token / masked session identifier — a nod to the "clinical
  /// token" ask; shown as a monospace pill if provided.
  final String? clinicalToken;

  /// Called when the user taps the launch button. Defaults to popping the
  /// overlay via the root navigator.
  final VoidCallback? onLaunch;

  /// Convenience: a full-screen, opaque scrim route. Kept opaque so the login
  /// form doesn't flash behind the overlay during the auth-gate swap.
  static PageRoute<void> route({
    required String email,
    String? name,
    String? clinicalToken,
    VoidCallback? onLaunch,
  }) =>
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => Scan4DiseaseSuccess(
          name: name,
          email: email,
          clinicalToken: clinicalToken,
          onLaunch: onLaunch,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      );

  @override
  State<Scan4DiseaseSuccess> createState() => _Scan4DiseaseSuccessState();
}

class _Scan4DiseaseSuccessState extends State<Scan4DiseaseSuccess>
    with SingleTickerProviderStateMixin {
  // Whole sequence = scan + morph + burst + a small tail so the card lands calmly.
  static const Duration _total = Duration(milliseconds: 3400);
  static const double _scanEnd = 2200 / 3400;
  static const double _morphEnd = 2600 / 3400;
  static const double _burstEnd = 1.0;

  late final AnimationController _c;
  late final List<_Particle> _particles;
  bool _cardShown = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _total)..forward();
    // Deterministic particle spread so hot-reload doesn't jitter, per-instance
    // seed so two openings in one session look natural.
    final rng = math.Random(DateTime.now().microsecondsSinceEpoch & 0xFFFF);
    _particles = List.generate(22, (i) {
      final baseAngle = (i / 22) * math.pi * 2;
      return _Particle(
        angle: baseAngle + rng.nextDouble() * 0.25 - 0.125,
        distance: 90 + rng.nextDouble() * 60,
        size: 3.5 + rng.nextDouble() * 3.5,
        // Mix of brand jade and lighter mint.
        color: rng.nextBool() ? Themes.brand : Themes.mint,
        delay: rng.nextDouble() * 0.12,
      );
    });
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _cardShown = true);
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _greetingName {
    final n = (widget.name ?? '').trim();
    if (n.isNotEmpty) return n;
    final local = widget.email.split('@').first;
    if (local.isEmpty) return 'there';
    return local[0].toUpperCase() + local.substring(1);
  }

  void _launch() {
    if (widget.onLaunch != null) {
      widget.onLaunch!();
    } else {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.canvas,
        color: Themes.canvas,
        child: SafeArea(
          child: Stack(
            children: [
              // Soft radial jade glow behind everything.
              const Positioned.fill(child: _BrandBackdrop()),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (_, __) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 220,
                          height: 220,
                          child: CustomPaint(
                            painter: _ScanCheckPainter(
                              progress: _c.value,
                              scanEnd: _scanEnd,
                              morphEnd: _morphEnd,
                              burstEnd: _burstEnd,
                              particles: _particles,
                            ),
                            child: Center(
                              child: _CenterMark(progress: _c.value),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _PhaseLabel(progress: _c.value, scanEnd: _scanEnd),
                        const SizedBox(height: 28),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          switchInCurve: Curves.easeOutCubic,
                          transitionBuilder: (child, a) => FadeTransition(
                            opacity: a,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.08),
                                end: Offset.zero,
                              ).animate(a),
                              child: child,
                            ),
                          ),
                          child: _cardShown
                              ? _SuccessCard(
                                  key: const ValueKey('card'),
                                  greetingName: _greetingName,
                                  email: widget.email,
                                  clinicalToken: widget.clinicalToken,
                                  onLaunch: _launch,
                                )
                              : const SizedBox(
                                  key: ValueKey('spacer'),
                                  height: 0,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/* ─────────────────────────────────────────────────────────────────────────── */

class _BrandBackdrop extends StatelessWidget {
  const _BrandBackdrop();
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          // Gentle veil — subtle brand tint, not a green explosion.
          gradient: RadialGradient(
            center: const Alignment(0, -0.25),
            radius: 1.1,
            colors: [
              Themes.mint.withOpacity(0.06),
              Themes.canvas,
            ],
            stops: const [0.0, 0.78],
          ),
        ),
      );
}

/// The always-visible center: the app logo (during scan) fades into a filled
/// brand disc (during morph/burst). Kept as a Widget so it composites cleanly
/// under the reticle/check strokes painted above.
class _CenterMark extends StatelessWidget {
  const _CenterMark({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    // Fade from logo → filled disc over the last third of the scan phase.
    final morphIn = ((progress - 0.55) / (0.78 - 0.55)).clamp(0.0, 1.0);
    final discOpacity = Curves.easeOutCubic.transform(morphIn);
    final logoOpacity = 1.0 - discOpacity;

    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Filled brand disc (revealed during morph so the check sits on it).
          Opacity(
            opacity: discOpacity,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Themes.brand,
                boxShadow: [
                  BoxShadow(
                    color: Themes.brand.withOpacity(0.4),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          // App logo — clean frameless vector emblem, gently pulses during scanning.
          Opacity(
            opacity: logoOpacity,
            child: Transform.scale(
              scale: 0.98 + 0.04 * math.sin(progress * math.pi * 6),
              child: const AppLogoMark(size: 96),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseLabel extends StatelessWidget {
  const _PhaseLabel({required this.progress, required this.scanEnd});
  final double progress;
  final double scanEnd;

  @override
  Widget build(BuildContext context) {
    final scanning = progress < scanEnd;
    // Subtle 3-dot pulse while scanning; steady after.
    final dotsPhase = ((progress * 3400) / 400).floor() % 4;
    final dots = scanning ? '.' * dotsPhase : '';
    final text = scanning ? 'Scanning credentials$dots' : 'Verified';
    final color = scanning ? Themes.inkSoft : Themes.brand;
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 180),
      style: TextStyle(
        color: color,
        fontSize: 13,
        letterSpacing: 0.14,
        fontWeight: scanning ? FontWeight.w500 : FontWeight.w700,
      ),
      child: Text(text.toUpperCase()),
    );
  }
}

/* ─── painter: reticle + checkmark + particle burst ──────────────────────── */

class _Particle {
  const _Particle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.color,
    required this.delay,
  });
  final double angle;
  final double distance; // px from center at full expansion
  final double size;
  final Color color;
  final double delay; // 0..0.2 of burst phase
}

class _ScanCheckPainter extends CustomPainter {
  _ScanCheckPainter({
    required this.progress,
    required this.scanEnd,
    required this.morphEnd,
    required this.burstEnd,
    required this.particles,
  });
  final double progress;
  final double scanEnd;
  final double morphEnd;
  final double burstEnd;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringR = math.min(size.width, size.height) / 2 - 8;

    // A calm base ring, always visible — the brand's "reticle" reads as one
    // coherent element across all three phases.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Themes.brand.withOpacity(0.18);
    canvas.drawCircle(center, ringR, ring);

    if (progress < scanEnd) {
      _paintScan(canvas, center, ringR);
    } else if (progress < morphEnd) {
      _paintMorph(canvas, center, ringR);
    } else {
      _paintCheckAndBurst(canvas, center, ringR);
    }
  }

  void _paintScan(Canvas canvas, Offset center, double r) {
    final t = progress / scanEnd;
    // Rotating jade sweep — one bright arc that goes twice around during scan.
    final sweep = math.pi * 0.55;
    final startAngle = -math.pi / 2 + t * math.pi * 4;
    final rect = Rect.fromCircle(center: center, radius: r);
    final grad = SweepGradient(
      startAngle: startAngle,
      endAngle: startAngle + sweep,
      colors: const [Colors.transparent, Themes.brand, Themes.mint],
      stops: const [0.0, 0.6, 1.0],
    );
    final arc = Paint()
      ..shader = grad.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    canvas.drawArc(rect, startAngle, sweep, false, arc);

    // Four small brand ticks at the cardinal points — nods to the horizontal
    // brandmark's reticle without duplicating it.
    final tick = Paint()
      ..color = Themes.brand.withOpacity(0.55)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final p1 = center + Offset(math.cos(a), math.sin(a)) * (r + 2);
      final p2 = center + Offset(math.cos(a), math.sin(a)) * (r - 8);
      canvas.drawLine(p1, p2, tick);
    }
  }

  void _paintMorph(Canvas canvas, Offset center, double r) {
    // Contract the sweep into a bright rim + start stroking the check.
    final t = ((progress - scanEnd) / (morphEnd - scanEnd)).clamp(0.0, 1.0);
    final rim = Paint()
      ..color = Color.lerp(Themes.brand, Themes.mint, t)!.withOpacity(0.85)
      ..strokeWidth = 3 + 2 * (1 - t)
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, r, rim);
    _paintCheck(canvas, center, Curves.easeOutCubic.transform(t));
  }

  void _paintCheckAndBurst(Canvas canvas, Offset center, double r) {
    // Steady rim.
    final rim = Paint()
      ..color = Themes.brand.withOpacity(0.55)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, r, rim);
    _paintCheck(canvas, center, 1.0);
    _paintBurst(canvas, center);
  }

  /// Two-segment checkmark, stroked in with a length-along-path clip.
  /// [t] in [0,1] draws 0..full length.
  void _paintCheck(Canvas canvas, Offset center, double t) {
    if (t <= 0) return;
    // Points scaled around the 96px filled disc.
    final p1 = center + const Offset(-20, 0);
    final p2 = center + const Offset(-4, 16);
    final p3 = center + const Offset(24, -14);
    final seg1 = (p2 - p1).distance;
    final seg2 = (p3 - p2).distance;
    final totalLen = seg1 + seg2;
    final drawn = t * totalLen;

    final paint = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;

    final path = Path()..moveTo(p1.dx, p1.dy);
    if (drawn <= seg1) {
      final k = drawn / seg1;
      final p = Offset.lerp(p1, p2, k)!;
      path.lineTo(p.dx, p.dy);
    } else {
      path.lineTo(p2.dx, p2.dy);
      final k = ((drawn - seg1) / seg2).clamp(0.0, 1.0);
      final p = Offset.lerp(p2, p3, k)!;
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }

  void _paintBurst(Canvas canvas, Offset center) {
    final tGlobal =
        ((progress - morphEnd) / (burstEnd - morphEnd)).clamp(0.0, 1.0);
    for (final p in particles) {
      final local = ((tGlobal - p.delay) / (1.0 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final ease = Curves.easeOutCubic.transform(local);
      final pos = center +
          Offset(math.cos(p.angle), math.sin(p.angle)) * (p.distance * ease);
      final fade = (1.0 - local).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = p.color.withOpacity(0.9 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawCircle(pos, p.size * (0.6 + 0.4 * fade), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanCheckPainter old) =>
      old.progress != progress;
}

/* ─── success card ────────────────────────────────────────────────────────── */

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({
    super.key,
    required this.greetingName,
    required this.email,
    required this.onLaunch,
    this.clinicalToken,
  });
  final String greetingName;
  final String email;
  final String? clinicalToken;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: Themes.liquidGlassDecoration(radius: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Welcome, $greetingName',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Themes.ink,
                  letterSpacing: -0.01,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your Scan4Disease session is ready.',
                style: TextStyle(
                  color: Themes.inkSoft,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              _MetaRow(icon: Icons.mail_outline, label: email),
              if (clinicalToken != null && clinicalToken!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _MetaRow(
                  icon: Icons.qr_code_2_rounded,
                  label: clinicalToken!,
                  mono: true,
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: onLaunch,
                  icon: const Icon(Icons.rocket_launch_rounded, size: 20),
                  label: const Text(
                    'Launch AI Screening Portal',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.label, this.mono = false});
  final IconData icon;
  final String label;
  final bool mono;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: Themes.inkSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Themes.inkSoft,
                fontSize: 13,
                fontFamily: mono ? 'monospace' : null,
                letterSpacing: mono ? 0.02 : 0,
              ),
            ),
          ),
        ],
      );
}
