import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/chat_service.dart';
import '../../services/language_service.dart';
import '../../services/sound_service.dart';
import '../theme.dart';
import '../widgets/app_logo_mark.dart';
import '../widgets/markdown_text.dart';
import '../widgets/video_background.dart';

/// A conversation space where the patient can ask follow-up questions about a screening
/// result. The prediction context is passed in and echoed to the (stateless) backend on
/// every turn; the deterministic triage is already fixed, so the assistant only explains —
/// it cannot diagnose or change urgency (enforced server-side).
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.prediction,
    this.questionnaire,
    this.conditionName,
  });

  /// {predicted_class, confidence, triage_category, low_confidence, gradcam_focus}
  final Map<String, dynamic>? prediction;
  final Map<String, dynamic>? questionnaire;
  final String? conditionName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _Msg {
  _Msg(this.role, this.content, {this.system = false});
  final String role; // 'user' | 'assistant'
  final String content;
  final bool system; // offline/error notice, not real assistant content
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  bool _loading = false;
  String _disclaimer = '';

  static const _suggestions = [
    'What does this result mean?',
    'How urgent is this?',
    'What should I do next?',
    'What should I watch for?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final message = text.trim();
    if (message.isEmpty || _loading) return;
    SoundService.instance.send();
    setState(() {
      _messages.add(_Msg('user', message));
      _loading = true;
      _input.clear();
    });
    _scrollToBottom();

    // Only real user/assistant turns become history; cap to the backend's window.
    final history = <Map<String, String>>[
      for (final m in _messages)
        if (!m.system) {'role': m.role, 'content': m.content},
    ];
    // Drop the just-added user message from history (it is sent as `message`).
    if (history.isNotEmpty) history.removeLast();

    final result = await ChatService.send(
      message: message,
      history: history.length > 20 ? history.sublist(history.length - 20) : history,
      prediction: widget.prediction,
      questionnaire: widget.questionnaire,
      language: LanguageService.instance.code.value,
    );

    if (!mounted) return;
    setState(() {
      _messages.add(_Msg('assistant', result.text, system: !result.available));
      if (result.disclaimer.isNotEmpty) _disclaimer = result.disclaimer;
      _loading = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;

    final subtitle = widget.conditionName == null || widget.conditionName!.isEmpty
        ? 'Ask about your screening result'
        : 'About: ${widget.conditionName}';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: dark
            ? const Color(0xFF161920).withValues(alpha: 0.72)
            : Colors.white.withValues(alpha: 0.85),
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text('Ask about your result'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(subtitle,
                  style: TextStyle(color: inkSoft, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dynamic ambient video backdrop
          const VideoBackground.ambient(),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: _messages.isEmpty ? _empty(dark) : _list(dark),
                ),
                if (_disclaimer.isNotEmpty) _disclaimerStrip(dark),
                _composer(dark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(bool dark) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: Themes.liquidGlassDecoration(radius: 24, dark: dark),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogoMark(size: 56, glow: true),
                const SizedBox(height: 14),
                Text(
                  'Questions about your result?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: dark ? Themes.darkInk : Themes.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  'This assistant explains your preliminary screening result. It is not a doctor '
                  'and cannot diagnose. Try a question:',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: dark ? Themes.darkInkSoft : Themes.inkSoft, height: 1.4, fontSize: 13),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final s in _suggestions)
                      ActionChip(
                        backgroundColor: dark ? Themes.darkBrandTint : const Color(0x66FFFFFF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: dark ? Themes.tealGlow.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.85),
                            width: 1.2,
                          ),
                        ),
                        label: Text(s,
                            style: TextStyle(
                              color: dark ? Themes.tealLight : Themes.brand,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            )),
                        onPressed: () => _send(s),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  Widget _list(bool dark) => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        itemCount: _messages.length + (_loading ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _messages.length && _loading) {
            return const AnalyzingResultBubble(label: 'Analyzing Results…');
          }
          return _bubble(_messages[i], dark);
        },
      );

  Widget _bubble(_Msg m, bool dark) {
    final isUser = m.role == 'user';
    Widget wrap(Widget child) => _BubbleEnter(fromRight: isUser, child: child);
    if (m.system) {
      return wrap(Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF261E10) : Themes.warningTint.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: dark ? const Color(0xFF5A4418) : Colors.white.withValues(alpha: 0.85)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 18, color: Themes.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(m.content, style: TextStyle(height: 1.35, color: dark ? Themes.darkInk : Themes.ink, fontSize: 13))),
        ]),
      ));
    }
    return wrap(Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
        decoration: isUser
            ? BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF15B79E), Color(0xFF0F766E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18).copyWith(bottomRight: const Radius.circular(4)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.40), width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF15B79E).withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              )
            : Themes.liquidGlassDecoration(
                radius: 18,
                dark: dark,
                borderRadius: BorderRadius.circular(18).copyWith(bottomLeft: const Radius.circular(4)),
                topAlpha: dark ? 0.95 : 0.88,
                bottomAlpha: dark ? 0.85 : 0.72,
              ),
        child: isUser
            ? Text(
                m.content,
                style: const TextStyle(color: Colors.white, height: 1.4, fontSize: 14.5, fontWeight: FontWeight.w500),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppLogoMark(size: 16, glow: false),
                      const SizedBox(width: 6),
                      Text('Assistant',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: dark ? Themes.tealLight : Themes.brand,
                          )),
                    ],
                  ),
                  const SizedBox(height: 6),
                  MarkdownText(m.content, color: dark ? Themes.darkInk : Themes.ink),
                ],
              ),
      ),
    ));
  }

  Widget _disclaimerStrip(bool dark) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF261E10) : Themes.warningTint.withValues(alpha: 0.80),
          border: Border(top: BorderSide(color: dark ? const Color(0xFF5A4418) : Colors.white.withValues(alpha: 0.85))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          _disclaimer.replaceAll('\n\n', ' '),
          style: TextStyle(
            fontSize: 11,
            color: dark ? Themes.tealLight : const Color(0xFF7A6318),
            height: 1.3,
          ),
        ),
      );

  Widget _composer(bool dark) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: Themes.liquidGlassDecoration(
            radius: 28,
            dark: dark,
            topAlpha: dark ? 0.95 : 0.88,
            bottomAlpha: dark ? 0.85 : 0.72,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  style: TextStyle(color: dark ? Themes.darkInk : Themes.ink),
                  decoration: InputDecoration(
                    hintText: 'Ask a question…',
                    hintStyle: TextStyle(color: dark ? Themes.darkInkSoft : Themes.inkMuted),
                    filled: true,
                    fillColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF15B79E), Color(0xFF0F766E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.50), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2DD4BF).withValues(alpha: 0.40),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: _loading ? null : () => _send(_input.text),
                  icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      );
}

/// "Analyzing Results…" loader bubble containing the 3×3 snake matrix animation
/// and clinical status label — identical to the website portal's `.ai-analyzing`.
class AnalyzingResultBubble extends StatelessWidget {
  final String label;

  const AnalyzingResultBubble({
    super.key,
    this.label = 'Analyzing Results…',
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: Themes.liquidGlassDecoration(
          radius: 18,
          borderRadius: BorderRadius.circular(18).copyWith(bottomLeft: const Radius.circular(4)),
          topAlpha: 0.88,
          bottomAlpha: 0.72,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SnakeLoader3x3(size: 28),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: Themes.ink,
                letterSpacing: -0.01,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 3×3 matrix "snake" loader — matches the website portal's `.ai-snake` animation.
/// 8 perimeter cells light up in a rotating cycle so 3 are always lit in a snake sequence.
class SnakeLoader3x3 extends StatefulWidget {
  final double size;
  final Color? activeColor;
  final Color? baseColor;

  const SnakeLoader3x3({
    super.key,
    this.size = 30.0,
    this.activeColor,
    this.baseColor,
  });

  @override
  State<SnakeLoader3x3> createState() => _SnakeLoader3x3State();
}

class _SnakeLoader3x3State extends State<SnakeLoader3x3>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.activeColor ?? Themes.brand;
    final base = widget.baseColor ?? Themes.ink.withValues(alpha: 0.12);

    return Container(
      width: widget.size,
      height: widget.size,
      padding: EdgeInsets.all(widget.size * 0.12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(widget.size * 0.25),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.85),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: active.withValues(alpha: 0.25),
            blurRadius: 6,
            spreadRadius: 0.5,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final step = (_ctrl.value * 8).floor() % 8;
          final head = (step + 2) % 8;
          final body = (step + 1) % 8;
          final tail = step % 8;

          // 8 perimeter cell coordinates in clockwise order:
          // 0:(0,0), 1:(0,1), 2:(0,2), 3:(1,2), 4:(2,2), 5:(2,1), 6:(2,0), 7:(1,0)
          const perimeter = [
            math.Point(0, 0),
            math.Point(0, 1),
            math.Point(0, 2),
            math.Point(1, 2),
            math.Point(2, 2),
            math.Point(2, 1),
            math.Point(2, 0),
            math.Point(1, 0),
          ];

          final cellSize = (widget.size * 0.76 - 4.0) / 3;

          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (r) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(3, (c) {
                  final pIdx = perimeter.indexWhere((p) => p.x == r && p.y == c);

                  Color cellColor;
                  if (pIdx == head) {
                    cellColor = active;
                  } else if (pIdx == body) {
                    cellColor = active.withValues(alpha: 0.80);
                  } else if (pIdx == tail) {
                    cellColor = active.withValues(alpha: 0.55);
                  } else {
                    cellColor = base;
                  }

                  return Container(
                    width: cellSize,
                    height: cellSize,
                    decoration: BoxDecoration(
                      color: cellColor,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  );
                }),
              );
            }),
          );
        },
      ),
    );
  }
}

/// One-shot fade + horizontal glide for a chat bubble the first time it
/// mounts. User bubbles glide in from the right, assistant bubbles from the
/// left — same feel the portal chat now uses. State is retained after the
/// forward pass so scrolling / rebuilds don't retrigger it.
class _BubbleEnter extends StatefulWidget {
  const _BubbleEnter({required this.fromRight, required this.child});
  final bool fromRight;
  final Widget child;
  @override
  State<_BubbleEnter> createState() => _BubbleEnterState();
}

class _BubbleEnterState extends State<_BubbleEnter> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = Curves.easeOutCubic.transform(_c.value);
          final dx = (widget.fromRight ? 8.0 : -8.0) * (1 - t);
          return Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(dx, 4 * (1 - t)), child: child),
          );
        },
        child: widget.child,
      );
}
