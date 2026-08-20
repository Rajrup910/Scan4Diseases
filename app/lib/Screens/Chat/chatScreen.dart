import 'package:flutter/material.dart';

import '../../services/chat_service.dart';
import '../../services/language_service.dart';
import '../theme.dart';
import '../widgets/markdown_text.dart';

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
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.conditionName == null || widget.conditionName!.isEmpty
        ? 'Ask about your screening result'
        : 'About: ${widget.conditionName}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask about your result'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(subtitle,
                  style: const TextStyle(color: Themes.muted, fontSize: 12)),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty ? _empty() : _list(),
          ),
          if (_loading) const _TypingIndicator(),
          if (_disclaimer.isNotEmpty) _disclaimerStrip(),
          _composer(),
        ],
      ),
    );
  }

  Widget _empty() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 8),
        children: [
          const Icon(Icons.forum_outlined, size: 48, color: Themes.primary),
          const SizedBox(height: 12),
          const Text('Questions about your result?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            'This assistant explains your preliminary screening result. It is not a doctor '
            'and cannot diagnose. Try a question:',
            textAlign: TextAlign.center,
            style: TextStyle(color: Themes.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final s in _suggestions)
                ActionChip(
                  label: Text(s),
                  onPressed: () => _send(s),
                ),
            ],
          ),
        ],
      );

  Widget _list() => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        itemCount: _messages.length,
        itemBuilder: (_, i) => _bubble(_messages[i]),
      );

  Widget _bubble(_Msg m) {
    final isUser = m.role == 'user';
    if (m.system) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Themes.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Themes.warning.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 18, color: Themes.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(m.content, style: const TextStyle(height: 1.35))),
        ]),
      );
    }
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser ? Themes.primary : Themes.surface,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : null,
            bottomLeft: isUser ? null : const Radius.circular(4),
          ),
          border: isUser ? null : Border.all(color: Themes.border),
        ),
        child: isUser
            ? Text(m.content, style: const TextStyle(color: Colors.white, height: 1.4))
            : MarkdownText(m.content, color: Themes.ink),
      ),
    );
  }

  Widget _disclaimerStrip() => Container(
        width: double.infinity,
        color: const Color(0xFFFFF8E8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          _disclaimer.replaceAll('\n\n', ' '),
          style: const TextStyle(fontSize: 11, color: Color(0xFF7A6318), height: 1.3),
        ),
      );

  Widget _composer() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: InputDecoration(
                    hintText: 'Ask a question…',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton.small(
                onPressed: _loading ? null : () => _send(_input.text),
                elevation: 0,
                child: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      );
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 6),
        child: Row(children: [
          SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Assistant is typing…', style: TextStyle(color: Themes.muted, fontSize: 13)),
        ]),
      );
}
