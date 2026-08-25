import 'package:flutter/material.dart';

import '../theme.dart';

/// A rich, self-contained Markdown renderer that supports:
/// - GFM Markdown Tables (`| Col 1 | Col 2 |`) with styled cells, headers, and horizontal scroll
/// - Numbered ordered lists (`1. Item`) with circular index badges
/// - Unordered bullet lists (`* Item`, `- Item`) with emerald bullets
/// - Headings (`#`, `##`, `###`) with distinct hierarchy
/// - Inline bold (`**text**`), italic (`*text*`), and inline code (`` `code` ``)
class MarkdownText extends StatelessWidget {
  const MarkdownText(
    this.data, {
    super.key,
    this.color,
    this.fontSize,
  });

  final String data;
  final Color? color;
  final double? fontSize;

  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _bullet = RegExp(r'^\s*[-*]\s+(.*)$');
  static final _numbered = RegExp(r'^\s*(\d+)\.\s+(.*)$');
  static final _tableSep = RegExp(r'^\s*\|?\s*[-:]+\s*\|[-|\s:]*\|$');
  static final _hr = RegExp(r'^\s*[-*_]{2,}\s*$');
  static final _standaloneBold = RegExp(r'^\*\*(.+?)\*\*$');

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? Themes.tealLight : Themes.brand;
    final primaryAccent = dark ? Themes.tealGlow : Themes.primary;

    final baseStyle = TextStyle(
      height: 1.48,
      fontSize: fontSize ?? 14.0,
      color: color ?? (dark ? Themes.darkInk : Themes.ink),
    );

    final blocks = <Widget>[];
    final lines = data.replaceAll('\r\n', '\n').split('\n');
    final paraBuffer = <String>[];
    final tableRows = <List<String>>[];

    void flushPara() {
      if (paraBuffer.isEmpty) return;
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _renderInline(paraBuffer.join(' '), baseStyle, dark),
      ));
      paraBuffer.clear();
    }

    void flushTable() {
      if (tableRows.isEmpty) return;
      blocks.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _renderTable(tableRows, baseStyle, dark),
      ));
      tableRows.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final line = raw.trim();

      // Check if line is a table row: | col | col |
      if (line.startsWith('|') && line.endsWith('|')) {
        flushPara();
        if (_tableSep.hasMatch(line)) {
          // Separator row like |---|---|
          continue;
        }
        final cells = line
            .substring(1, line.length - 1)
            .split('|')
            .map((c) => c.trim())
            .toList();
        tableRows.add(cells);
        continue;
      } else if (tableRows.isNotEmpty) {
        flushTable();
      }

      if (line.isEmpty) {
        flushPara();
        continue;
      }

      // Check horizontal rule divider lines (---, --, ***, ___) -> omit clutter
      if (_hr.hasMatch(line)) {
        flushPara();
        continue;
      }

      final h = _heading.firstMatch(line);
      final b = _bullet.firstMatch(line);
      final n = _numbered.firstMatch(line);
      final boldHead = _standaloneBold.firstMatch(line);

      if (h != null) {
        flushPara();
        final level = h.group(1)!.length;
        final size = level <= 1 ? 18.0 : (level == 2 ? 16.0 : 14.5);
        blocks.add(Padding(
          padding: EdgeInsets.only(top: blocks.isEmpty ? 2 : 12, bottom: 6),
          child: _renderInline(
            h.group(2)!,
            baseStyle.copyWith(
              fontSize: size,
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: -0.2,
            ),
            dark,
          ),
        ));
      } else if (boldHead != null) {
        flushPara();
        blocks.add(Padding(
          padding: EdgeInsets.only(top: blocks.isEmpty ? 2 : 10, bottom: 4),
          child: _renderInline(
            boldHead.group(1)!,
            baseStyle.copyWith(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: -0.1,
            ),
            dark,
          ),
        ));
      } else if (n != null) {
        flushPara();
        final numStr = n.group(1)!;
        final itemText = n.group(2)!;
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2, right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: primaryAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  numStr,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: dark ? Themes.tealLight : Themes.primary,
                  ),
                ),
              ),
              Expanded(child: _renderInline(itemText, baseStyle, dark)),
            ],
          ),
        ));
      } else if (b != null) {
        flushPara();
        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 6, right: 8, left: 2),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryAccent,
                ),
              ),
              Expanded(child: _renderInline(b.group(1)!, baseStyle, dark)),
            ],
          ),
        ));
      } else {
        paraBuffer.add(line);
      }
    }

    flushPara();
    flushTable();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }

  Widget _renderTable(List<List<String>> rows, TextStyle baseStyle, bool dark) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final header = rows.first;
    final dataRows = rows.length > 1 ? rows.sublist(1) : <List<String>>[];
    final borderColor = dark ? Themes.darkBorder : Themes.border;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1E2430) : Colors.white.withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.20 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: DataTable(
            headingRowHeight: 38,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 80,
            columnSpacing: 14,
            horizontalMargin: 12,
            headingRowColor: WidgetStateProperty.all(
              dark ? Themes.darkBrandTint : Themes.brandTint.withValues(alpha: 0.8),
            ),
            border: TableBorder(
              horizontalInside: BorderSide(
                color: borderColor.withValues(alpha: 0.7),
                width: 1,
              ),
              verticalInside: BorderSide(
                color: borderColor.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            columns: [
              for (final h in header)
                DataColumn(
                  label: _renderInline(
                    h,
                    baseStyle.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: dark ? Themes.tealLight : Themes.brand,
                    ),
                    dark,
                  ),
                ),
            ],
            rows: [
              for (var i = 0; i < dataRows.length; i++)
                DataRow(
                  color: WidgetStateProperty.all(
                    i.isEven
                        ? Colors.transparent
                        : (dark ? const Color(0x33232A36) : Themes.brandTint.withValues(alpha: 0.25)),
                  ),
                  cells: [
                    for (final cell in dataRows[i])
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: _renderInline(
                              cell,
                              baseStyle.copyWith(fontSize: 12.5),
                              dark,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _renderInline(String text, TextStyle base, bool dark) {
    final spans = <InlineSpan>[];
    // Inline regex for **bold**, *italic*, `code`
    final inlineRegex = RegExp(r'(\*\*(.+?)\*\*|\*([^*]+?)\*|`([^`]+?)`)');
    var lastIndex = 0;

    for (final match in inlineRegex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }
      final matchedStr = match.group(0)!;
      if (matchedStr.startsWith('**') && matchedStr.endsWith('**')) {
        spans.add(TextSpan(
          text: match.group(2),
          style: base.copyWith(
            fontWeight: FontWeight.w800,
            color: dark ? Themes.tealLight : Themes.brand,
          ),
        ));
      } else if (matchedStr.startsWith('*') && matchedStr.endsWith('*')) {
        spans.add(TextSpan(
          text: match.group(3),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (matchedStr.startsWith('`') && matchedStr.endsWith('`')) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: dark ? Themes.darkBorder : Themes.border.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              match.group(4)!,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: (base.fontSize ?? 14.0) * 0.9,
                fontWeight: FontWeight.w600,
                color: dark ? Themes.darkInk : Themes.ink,
              ),
            ),
          ),
        ));
      }
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex)));
    }

    return RichText(
      text: TextSpan(
        style: base,
        children: spans.isEmpty ? [TextSpan(text: text)] : spans,
      ),
    );
  }
}
