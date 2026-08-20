import 'package:flutter/material.dart';

/// A tiny, dependency-free Markdown renderer for the subset the LLM actually emits:
/// `#`/`##`/`###` headings, `**bold**` inline, `-`/`*` bullet lines, and blank-line
/// paragraphs. Anything else renders as plain text. Kept deliberately small so it themes
/// cleanly and carries no package-version risk.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.data, {super.key, this.color, this.fontSize});

  final String data;
  final Color? color;
  final double? fontSize;

  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _bullet = RegExp(r'^\s*[-*]\s+(.*)$');
  static final _bold = RegExp(r'\*\*(.+?)\*\*');

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      height: 1.45,
      fontSize: fontSize ?? 14.5,
      color: color ?? DefaultTextStyle.of(context).style.color,
    );

    final blocks = <Widget>[];
    final para = <String>[];

    void flushPara() {
      if (para.isEmpty) return;
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _inline(para.join(' '), base),
      ));
      para.clear();
    }

    for (final raw in data.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        flushPara();
        continue;
      }
      final h = _heading.firstMatch(line);
      final b = _bullet.firstMatch(line);
      if (h != null) {
        flushPara();
        final level = h.group(1)!.length;
        final size = level <= 1 ? 19.0 : (level == 2 ? 16.5 : 15.0);
        blocks.add(Padding(
          padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 12, bottom: 6),
          child: _inline(h.group(2)!, base.copyWith(fontSize: size, fontWeight: FontWeight.w800)),
        ));
      } else if (b != null) {
        flushPara();
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('•  ', style: base),
            Expanded(child: _inline(b.group(1)!, base)),
          ]),
        ));
      } else {
        para.add(line);
      }
    }
    flushPara();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }

  Widget _inline(String text, TextStyle base) {
    final spans = <TextSpan>[];
    var i = 0;
    for (final m in _bold.allMatches(text)) {
      if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      i = m.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
    return RichText(
      text: TextSpan(style: base, children: spans.isEmpty ? [TextSpan(text: text)] : spans),
    );
  }
}
