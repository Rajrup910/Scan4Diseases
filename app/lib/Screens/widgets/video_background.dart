import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'neuro_background.dart';

/// A live, looping video backdrop for the app shell.
///
/// Plays `assets/bg_ambient.mp4` muted, looping, cover-fitted behind [child],
/// with a translucent veil on top so the light UI (dark text, white cards) stays
/// legible over the motion. If the clip can't initialise (asset missing, codec,
/// plugin not yet `pub get`-ed) it falls back to the painted [NeuroBackground],
/// so the app never loses its background.
class VideoBackground extends StatefulWidget {
  final Widget child;
  const VideoBackground({super.key, required this.child});
  const VideoBackground.ambient({super.key, this.child = const SizedBox.shrink()});

  @override
  State<VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<VideoBackground> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.asset('assets/bg_ambient.mp4');
      _controller = c;
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0); // ambient only — never audio
      await c.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fallback: the painted blueprint background if the clip can't play.
    if (_failed) return NeuroBackground(child: widget.child);

    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF0F1117) : const Color(0xFFF1F3F6);
    final c = _controller;

    return Stack(
      children: [
        // The clip, cover-fitted to fill the screen at its native aspect ratio.
        Positioned.fill(
          child: (_ready && c != null && c.value.isInitialized)
              ? FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: c.value.size.width,
                    height: c.value.size.height,
                    child: VideoPlayer(c),
                  ),
                )
              : ColoredBox(color: base),
        ),
        // Legibility veil — keeps dark text / white cards readable over the motion.
        // Tune the alpha here if you want the clip more (lower) or less (higher) visible.
        Positioned.fill(
          child: ColoredBox(
            color: (dark ? const Color(0xFF0F1117) : const Color(0xFFF4F6F9))
                .withValues(alpha: dark ? 0.52 : 0.46),
          ),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}
