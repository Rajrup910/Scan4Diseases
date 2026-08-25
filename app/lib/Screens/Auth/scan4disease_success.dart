import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/app_logo_mark.dart';

/// Scan4Disease sign-in / sign-up success flourish.
///
/// A full-screen overlay played AFTER a successful [AuthService.login] or
/// [AuthService.register] returns. Three phases (jade → mint brand palette):
///
///   0 ─ 1400 ms  scan     — a jade reticle sweeps ONCE around the app logo,
///                           "Scanning credentials…" pulses below.
///   1400 ─ 1750 ms morph  — the reticle contracts into a filled brand disc and
///                           a checkmark strokes on (350 ms cubic-easeOut).
///   1750 ─ 2200 ms settle — a single soft rim pulse ripples outward and fades.
///
/// Once the settle finishes, the success card fades in. Redesigned from the
/// original 3.4s theatrical version: single revolution instead of two, one rim
/// pulse instead of a 22-particle burst, calmer logo breath — matches the
/// app's restrained motion language.
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
  // Whole sequence = scan + morph + settle. Cut from 3.4s to 2.2s and the
  // 22-particle burst removed so the moment reads as calm confirmation, not
  // fireworks.
  static const Duration _total = Duration(milliseconds: 2200);
  static const double _scanEnd = 1400 / 2200;
  static const double _morphEnd = 1750 / 2200;
  static const double _settleEnd = 1.0;

  late final AnimationController _c;
  bool _cardShown = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _total)..forward();
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
                              settleEnd: _settleEnd,
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
              Themes.mint.withValues(alpha: 0.06),
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
                // Restrained ambient shadow, not a spread-radius bloom.
                boxShadow: [
                  BoxShadow(
                    color: Themes.brand.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),
          ),
          // App logo — one gentle breath while scanning, not a 6-cycle pulse.
          Opacity(
            opacity: logoOpacity,
            child: Transform.scale(
              scale: 0.98 + 0.02 * math.sin(progress * math.pi * 2),
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

/* ─── painter: reticle + checkmark + rim pulse ──────────────────────────── */

class _ScanCheckPainter extends CustomPainter {
  _ScanCheckPainter({
    required this.progress,
    required this.scanEnd,
    required this.morphEnd,
    required this.settleEnd,
  });
  final double progress;
  final double scanEnd;
  final double morphEnd;
  final double settleEnd;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringR = math.min(size.width, size.height) / 2 - 8;

    // A calm base ring, always visible — the brand's "reticle" reads as one
    // coherent element across all three phases.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Themes.brand.withValues(alpha: 0.18);
    canvas.drawCircle(center, ringR, ring);

    if (progress < scanEnd) {
      _paintScan(canvas, center, ringR);
    } else if (progress < morphEnd) {
      _paintMorph(canvas, center, ringR);
    } else {
      _paintCheckAndSettle(canvas, center, ringR);
    }
  }

  void _paintScan(Canvas canvas, Offset center, double r) {
    final t = progress / scanEnd;
    // Rotating jade sweep — a single revolution during scan, not two. The
    // previous 2× rotation felt too eager for the "calm confirmation" tone.
    final sweep = math.pi * 0.55;
    final startAngle = -math.pi / 2 + t * math.pi * 2;
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
      ..strokeWidth = 3.2;
    canvas.drawArc(rect, startAngle, sweep, false, arc);

    // Four small brand ticks at the cardinal points — nods to the horizontal
    // brandmark's reticle without duplicating it.
    final tick = Paint()
      ..color = Themes.brand.withValues(alpha: 0.55)
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
      ..color = Color.lerp(Themes.brand, Themes.mint, t)!.withValues(alpha: 0.85)
      ..strokeWidth = 3 + 2 * (1 - t)
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, r, rim);
    _paintCheck(canvas, center, Curves.easeOutCubic.transform(t));
  }

  void _paintCheckAndSettle(Canvas canvas, Offset center, double r) {
    // Steady rim.
    final rim = Paint()
      ..color = Themes.brand.withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, r, rim);
    _paintCheck(canvas, center, 1.0);
    _paintRimPulse(canvas, center, r);
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

  /// A single soft rim pulse — one expanding ring that fades — replacing the
  /// 22-particle burst. Same visual beat "something just resolved," calmer.
  void _paintRimPulse(Canvas canvas, Offset center, double baseR) {
    final t = ((progress - morphEnd) / (settleEnd - morphEnd)).clamp(0.0, 1.0);
    final ease = Curves.easeOutCubic.transform(t);
    // Ring travels outward from the base rim by ~14px and fades to zero.
    final radius = baseR + 14 * ease;
    final alpha = (1.0 - ease) * 0.5;
    final pulse = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Themes.mint.withValues(alpha: alpha);
    canvas.drawCircle(center, radius, pulse);
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
