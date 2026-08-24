import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme.dart';
import 'expanding_orbs_painter.dart';
import 'emerald_waves.dart';

export 'expanding_orbs_painter.dart';

/// A "slide-to-start" action — a green track with a draggable thumb.
///
/// When the user drags the thumb to the far right the widget commits: it flashes
/// a full-viewport green wash on top of everything and, once the wash reaches
/// full opacity, calls [onComplete] so the parent can switch screens. If the
/// user releases early, the thumb springs back and nothing fires.
///
/// Designed for the Home hero "Start screening" action — the wash is the visual
/// bridge from the marketing hero into the clinical screening flow.
class SlideToStart extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onComplete;

  const SlideToStart({
    super.key,
    required this.label,
    required this.onComplete,
    this.icon = Icons.arrow_forward_rounded,
  });

  @override
  State<SlideToStart> createState() => _SlideToStartState();
}

class _SlideToStartState extends State<SlideToStart> {
  double _dragX = 0;
  double _maxX = 0;
  bool _completing = false;

  static const double _thumb = 52;
  static const double _height = 56;

  void _snapBack() {
    setState(() => _dragX = 0);
  }

  void _commit() {
    if (_completing) return;
    setState(() {
      _completing = true;
      _dragX = _maxX;
    });
    // The full-screen wash + tab switch is owned by the shell — see
    // MyLandingPage._triggerStartScreeningTransition. We just report completion.
    widget.onComplete();
    // Reset after the wash transition finishes so the slider is back at its
    // starting position when the user navigates back to the Home tab.
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _completing = false;
        _dragX = 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(_height / 2);

    return LayoutBuilder(builder: (context, box) {
      _maxX = (box.maxWidth - _thumb).clamp(0.0, double.infinity);
      final progress = _maxX == 0 ? 0.0 : (_dragX / _maxX).clamp(0.0, 1.0);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _completing ? null : _commit,
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: [
              // Subtle, gentle depth shadow
              BoxShadow(
                color: Themes.brand.withValues(alpha: 0.20),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: Stack(
              children: [
                // Base track with dynamic organic waves of bright and dark green
                EmeraldWaves(
                  height: _height,
                  borderRadius: borderRadius,
                ),
                // Filled portion behind the thumb — grows with drag/commit.
                AnimatedPositioned(
                  duration: _completing
                      ? const Duration(milliseconds: 220)
                      : (_dragX > 0
                          ? Duration.zero
                          : const Duration(milliseconds: 260)),
                  curve: Curves.easeOutCubic,
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: (_dragX + _thumb).clamp(_thumb, double.infinity),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Themes.mint, Themes.brand],
                      ),
                      borderRadius: borderRadius,
                      boxShadow: [
                        BoxShadow(
                          color: Themes.brand.withValues(alpha: 0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                // Centered label — fades as the thumb reaches it.
                Center(
                  child: Opacity(
                    opacity: (1 - progress * 1.4).clamp(0.0, 1.0),
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        letterSpacing: 0.2,
                        shadows: [
                          Shadow(
                            color: Color(0x60000000),
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Draggable & tappable thumb.
                AnimatedPositioned(
                  duration: _completing
                      ? const Duration(milliseconds: 220)
                      : (_dragX > 0
                          ? Duration.zero
                          : const Duration(milliseconds: 260)),
                  curve: Curves.easeOutCubic,
                  left: _dragX + 2,
                  top: 2,
                  bottom: 2,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _completing ? null : _commit,
                    onHorizontalDragUpdate: _completing
                        ? null
                        : (d) => setState(() {
                              _dragX = (_dragX + d.delta.dx).clamp(0.0, _maxX);
                            }),
                    onHorizontalDragEnd: _completing
                        ? null
                        : (_) {
                            if (_dragX >= _maxX * 0.70) {
                              _commit();
                            } else {
                              _snapBack();
                            }
                          },
                    child: Container(
                      width: _thumb - 4,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(widget.icon, color: Themes.brandDark, size: 22),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Gentle green transition overlay for the slide-to-start hand-off.
///
/// Gentle brand-tint transition veil for the screening hand-off.
///
/// A smooth clinical flourish that:
///   * fades in over ~380ms to a rich emerald-tinted peak veil with backdrop blur;
///   * holds briefly while the parent swaps tabs behind the veil;
///   * breathes and dissolves smoothly back out.
class ScreenWash extends StatefulWidget {
  final bool active;

  /// Called at the crest of the fade-in — the parent should swap the underlying
  /// tab here so the change is hidden behind the veil.
  final VoidCallback? onWashPeak;

  /// Called when the entire wash cycle has completed dissolving.
  final VoidCallback? onWashComplete;

  const ScreenWash({
    super.key,
    required this.active,
    this.onWashPeak,
    this.onWashComplete,
  });

  @override
  State<ScreenWash> createState() => _ScreenWashState();
}

class _ScreenWashState extends State<ScreenWash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _peakedThisCycle = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1850),
    )
      ..addListener(() {
        if (!_peakedThisCycle &&
            _c.value >= 0.36 &&
            _c.status == AnimationStatus.forward) {
          _peakedThisCycle = true;
          widget.onWashPeak?.call();
        }
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onWashComplete?.call();
        }
      });
    if (widget.active) _c.forward();
  }

  @override
  void didUpdateWidget(covariant ScreenWash old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _peakedThisCycle = false;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _veil(double t) {
    const peak = 1.0;
    if (t <= 0.36) {
      return Curves.easeOutCubic.transform((t / 0.36).clamp(0.0, 1.0)) * peak;
    }
    if (t <= 0.46) {
      return peak;
    }
    return peak *
        (1.0 -
            Curves.easeOutCubic
                .transform(((t - 0.46) / 0.54).clamp(0.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active && _c.value == 0) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      ignoring: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final opacity = _veil(_c.value).clamp(0.0, 1.0);
          if (opacity <= 0.001) return const SizedBox.shrink();
          return Opacity(
            opacity: opacity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: 20 * opacity,
                    sigmaY: 20 * opacity,
                  ),
                  child: const SizedBox.expand(),
                ),
                CustomPaint(
                  painter: ExpandingOrbsPainter(
                    progress: _c.value,
                    opacity: opacity,
                  ),
                  child: const SizedBox.expand(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
