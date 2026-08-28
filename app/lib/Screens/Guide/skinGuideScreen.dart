import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../Doctors/nearbyDoctorsScreen.dart';
import '../../services/self_exam_reminder.dart';
import '../theme.dart';

/// Offline skin-health guide: photo technique, the ABCDE rule (with drawn illustrations),
/// red flags, sun protection, an interactive self-exam checklist, a condition explorer,
/// myth-busting, a searchable glossary and a full Fitzpatrick skin-type questionnaire.
///
/// Everything is static content plus local widget state — no backend, no API keys and no
/// image assets (illustrations are drawn with CustomPaint), so it works fully offline.
class SkinGuideScreen extends StatelessWidget {
  const SkinGuideScreen({super.key, this.focusResults = false});

  /// When true the "Understanding your result" section starts expanded. Used by the
  /// "Understand this result" bar on the screening result screen.
  final bool focusResults;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;

    return Scaffold(
      appBar: AppBar(title: const Text('Skin health guide')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          Text(
            'Evidence-based basics on spotting skin change early, protecting your skin, '
            'and reading an AI screening result correctly.',
            style: TextStyle(color: inkSoft, height: 1.4, fontSize: 14.5),
          ),
          const SizedBox(height: 16),
          const _Section(
            icon: Icons.photo_camera_outlined,
            title: 'Photograph a lesion properly',
            subtitle: 'Image quality is the biggest factor in screening accuracy.',
            initiallyExpanded: true,
            child: _PhotoChecklist(),
          ),
          const _Section(
            icon: Icons.rule_folder_outlined,
            title: 'The ABCDE rule',
            subtitle: 'Five features clinicians use to triage a pigmented lesion.',
            child: _AbcdeGuide(),
          ),
          const _Section(
            icon: Icons.priority_high_rounded,
            title: 'Red flags — seek care promptly',
            subtitle: 'Findings that warrant an in-person examination.',
            accent: Themes.danger,
            child: _RedFlags(),
          ),
          const _Section(
            icon: Icons.wb_sunny_outlined,
            title: 'Sun protection & UV',
            subtitle: 'UV exposure drives most preventable skin cancer.',
            accent: Themes.warning,
            child: _SunProtection(),
          ),
          const _Section(
            icon: Icons.event_repeat_outlined,
            title: 'Monthly self-examination',
            subtitle: 'A systematic head-to-toe check you can tick off.',
            accent: Themes.mint,
            child: _SelfExamChecklist(),
          ),
          _Section(
            icon: Icons.insights_outlined,
            title: 'Understanding your result',
            subtitle: 'What the score, triage band and heatmap actually mean.',
            initiallyExpanded: focusResults,
            child: const _UnderstandingResults(),
          ),
          const _Section(
            icon: Icons.grid_view_rounded,
            title: 'Common skin conditions',
            subtitle: 'What they look like and how urgent they are.',
            child: _ConditionExplorer(),
          ),
          const _Section(
            icon: Icons.psychology_alt_outlined,
            title: 'Myths vs. evidence',
            subtitle: 'Tap a claim to reveal what the evidence says.',
            child: _MythBuster(),
          ),
          const _Section(
            icon: Icons.menu_book_outlined,
            title: 'Glossary',
            subtitle: 'Search any term you meet in a report.',
            child: _Glossary(),
          ),
          const _Section(
            icon: Icons.colorize_outlined,
            title: 'Know your skin type',
            subtitle: 'Full Fitzpatrick questionnaire — tailored UV advice.',
            child: _FitzpatrickQuiz(),
          ),
          const SizedBox(height: 14),
          _footer(context),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Themes.darkInk : Themes.ink;
    final bg = dark ? const Color(0xFF231C10) : const Color(0xFFFFF8E8);
    final border = dark ? const Color(0xFF6E5621) : const Color(0xFFF1D18A);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline_rounded, color: Themes.warning),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'General information, not medical advice. No app — this one included — can '
              'rule out skin cancer. Anything that worries you deserves an in-person exam.',
              style: TextStyle(height: 1.4, color: ink, fontSize: 13),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const NearbyDoctorsScreen())),
              icon: const Icon(Icons.location_on_outlined, size: 18),
              label: const Text('Find a dermatologist'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: border),
                foregroundColor: dark ? Themes.tealLight : Themes.primary,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared building blocks
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.accent = Themes.primary,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Color accent;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = dark ? const Color(0xFF161A22) : Colors.white;
    final borderColor = dark ? Themes.darkBorder : Themes.border;
    final iconBorder = dark ? const Color(0xFF262C38) : Themes.borderSubtle;
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      color: cardColor,
      elevation: dark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: borderColor, width: 1.1),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          iconColor: inkSoft,
          collapsedIconColor: inkSoft,
          leading: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: dark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: iconBorder),
            ),
            child: Icon(icon, color: accent),
          ),
          title: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: ink),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: TextStyle(color: inkSoft, fontSize: 12.5, height: 1.3),
            ),
          ),
          children: [child],
        ),
      ),
    );
  }
}

/// Bulleted list. Explicitly left-aligned — a bare [Column] centres short rows.
class _Bullets extends StatelessWidget {
  const _Bullets({required this.items, this.color = Themes.primary});
  final List<String> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Themes.darkInk : Themes.ink;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t,
                      style: TextStyle(height: 1.45, color: ink, fontSize: 13.5),
                    ),
                  ),
                ]),
              ))
          .toList(),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote(this.text, {this.icon = Icons.lightbulb_outline_rounded, this.color = Themes.primary});
  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Themes.darkInk : Themes.ink;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: dark ? 0.35 : 0.22)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, height: 1.4, color: ink),
          ),
        ),
      ]),
    );
  }
}

/// A tappable checklist with a progress bar. State lasts for the session.
class _Checklist extends StatefulWidget {
  const _Checklist({required this.items, required this.color, this.doneLabel});
  final List<String> items;
  final Color color;
  final String? doneLabel;

  @override
  State<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends State<_Checklist> {
  final Set<int> _done = {};

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final total = widget.items.length;
    final complete = _done.length == total && total > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : _done.length / total,
              minHeight: 7,
              backgroundColor: dark ? const Color(0xFF262C38) : Themes.border,
              color: widget.color,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('${_done.length}/$total',
            style:
                TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: widget.color)),
      ]),
      const SizedBox(height: 8),
      for (var i = 0; i < total; i++) _row(i, dark),
      if (complete && widget.doneLabel != null) ...[
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.verified_rounded, size: 17, color: widget.color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(widget.doneLabel!,
                style: TextStyle(
                    color: widget.color, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ]),
      ],
      if (_done.isNotEmpty)
        TextButton.icon(
          onPressed: () => setState(_done.clear),
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero, minimumSize: const Size(0, 34)),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Reset', style: TextStyle(fontSize: 12.5)),
        ),
    ]);
  }

  Widget _row(int i, bool dark) {
    final checked = _done.contains(i);
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;
    final uncheckColor = dark ? Themes.darkInkSoft : Themes.border;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => checked ? _done.remove(i) : _done.add(i)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: checked ? widget.color : uncheckColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.items[i],
              style: TextStyle(
                height: 1.4,
                fontSize: 13.5,
                color: checked ? inkSoft.withValues(alpha: dark ? 0.55 : 0.8) : ink,
                decoration: checked ? TextDecoration.lineThrough : null,
                decorationColor: inkSoft,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1 — Photo technique
// ---------------------------------------------------------------------------

class _PhotoChecklist extends StatelessWidget {
  const _PhotoChecklist();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The model sees only what your camera captured. Work through this before you '
          'shoot — it takes about thirty seconds.',
          style: TextStyle(color: inkSoft, height: 1.4, fontSize: 13),
        ),
        const SizedBox(height: 12),
        const _Checklist(
          color: Themes.primary,
          doneLabel: 'Conditions look good — take the photo now.',
          items: [
            'Indirect daylight: face a window, no overhead spotlight, flash off.',
            'Lesion centred, filling roughly a third of the frame.',
            'Lens 10–15 cm away and parallel to the skin, not angled.',
            'Tap the screen on the lesion and wait for focus to lock.',
            'Place a ruler or coin beside it so size is readable.',
            'Clean the area — no makeup, cream, ink or overlying hair.',
            'Plain background; move off patterned bedding or clothing.',
            'Take two frames: one close-up, one wider showing body location.',
          ],
        ),
        const SizedBox(height: 12),
        const _InfoNote(
          'Retake rather than submit a blurred or shadowed image. A poor photo produces a '
          'confidently wrong result, which is more dangerous than no result at all.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 2 — ABCDE, with drawn illustrations
// ---------------------------------------------------------------------------

class _AbcdeGuide extends StatelessWidget {
  const _AbcdeGuide();

  static const _rows = <(String, String, String)>[
    ('A', 'Asymmetry', 'Draw a line through the middle: the two halves do not match.'),
    ('B', 'Border', 'Edges are notched, scalloped, or fade indistinctly into skin.'),
    ('C', 'Colour', 'More than one shade — brown, black, red, white or blue-grey.'),
    ('D', 'Diameter', 'Wider than about 6 mm, though melanoma can present smaller.'),
    ('E', 'Evolving', 'Any change in size, shape or colour, or new itch or bleeding.'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Left shows the reassuring pattern, right the concerning one. Evolution (E) is '
          'the strongest single predictor — change matters more than appearance.',
          style: TextStyle(color: inkSoft, height: 1.4, fontSize: 13),
        ),
        const SizedBox(height: 14),
        for (final r in _rows) _row(r.$1, r.$2, r.$3, dark),
        const _InfoNote(
          'Ugly duckling sign: a spot that simply looks unlike all your others deserves '
          'review even when it passes every ABCDE test.',
          icon: Icons.search_rounded,
          color: Themes.warning,
        ),
      ],
    );
  }

  Widget _row(String letter, String title, String text, bool dark) {
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _LesionMark(letter: letter, concerning: false, dark: dark),
          Icon(Icons.arrow_right_alt_rounded, size: 15, color: inkSoft),
          _LesionMark(letter: letter, concerning: true, dark: dark),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Themes.primary,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(letter,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: ink)),
            ]),
            const SizedBox(height: 4),
            Text(text,
                style: TextStyle(color: inkSoft, height: 1.35, fontSize: 12.8)),
          ]),
        ),
      ]),
    );
  }
}

/// A small drawn lesion illustrating one ABCDE feature (no image assets needed).
class _LesionMark extends StatelessWidget {
  const _LesionMark({required this.letter, required this.concerning, required this.dark});
  final String letter;
  final bool concerning;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF26201B) : const Color(0xFFF4E6DC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: (concerning ? Themes.danger : Themes.mint).withValues(alpha: dark ? 0.60 : 0.45),
          ),
        ),
        child: CustomPaint(painter: _LesionPainter(letter, concerning)),
      );
}

class _LesionPainter extends CustomPainter {
  _LesionPainter(this.letter, this.concerning);
  final String letter;
  final bool concerning;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final base = Paint()..color = const Color(0xFF8D6E63);

    switch (letter) {
      case 'A':
        concerning ? canvas.drawPath(_asymmetric(c), base) : canvas.drawCircle(c, 13, base);
      case 'B':
        concerning ? canvas.drawPath(_notched(c), base) : canvas.drawCircle(c, 13, base);
      case 'C':
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: 13)));
        if (concerning) {
          canvas.drawCircle(c, 13, Paint()..color = const Color(0xFF6D4C41));
          canvas.drawCircle(c.translate(-5, -4), 8, Paint()..color = const Color(0xFF2F2A26));
          canvas.drawCircle(c.translate(6, 5), 6, Paint()..color = const Color(0xFFD8A98B));
          canvas.drawCircle(c.translate(5, -6), 4, Paint()..color = const Color(0xFF9E4B42));
        } else {
          canvas.drawCircle(c, 13, base);
        }
        canvas.restore();
      case 'D':
        canvas.drawCircle(c, concerning ? 17 : 8, base);
      case 'E':
        canvas.drawCircle(c, concerning ? 17 : 11, base);
        if (concerning) {
          // Dashed-looking inner ring marks the smaller size it grew from.
          canvas.drawCircle(
            c,
            10,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.85)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6,
          );
        }
    }
  }

  Path _asymmetric(Offset c) => Path()
    ..moveTo(c.dx - 13, c.dy - 2)
    ..cubicTo(c.dx - 11, c.dy - 15, c.dx + 4, c.dy - 14, c.dx + 7, c.dy - 6)
    ..cubicTo(c.dx + 17, c.dy - 1, c.dx + 12, c.dy + 12, c.dx + 1, c.dy + 12)
    ..cubicTo(c.dx - 7, c.dy + 12, c.dx - 14, c.dy + 6, c.dx - 13, c.dy - 2)
    ..close();

  Path _notched(Offset c) {
    final p = Path();
    const points = 12;
    for (var i = 0; i <= points; i++) {
      final t = (i / points) * 2 * math.pi;
      final r = i.isEven ? 14.0 : 9.0; // alternating radius = ragged edge
      final x = c.dx + r * math.cos(t);
      final y = c.dy + r * math.sin(t);
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    return p..close();
  }

  @override
  bool shouldRepaint(covariant _LesionPainter old) =>
      old.letter != letter || old.concerning != concerning;
}

// ---------------------------------------------------------------------------
// 3 — Red flags
// ---------------------------------------------------------------------------

class _RedFlags extends StatelessWidget {
  const _RedFlags();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Bullets(color: Themes.danger, items: [
            'Bleeding, oozing or crusting with no injury to explain it.',
            'A sore or ulcer that has not healed after four weeks.',
            'Measurable change in size, shape or colour over weeks to months.',
            'A firm growing lump that is pearly, pink, or skin-coloured.',
            'A new pigmented streak or dark band under a fingernail or toenail.',
            'Persistent itch, tenderness or pain localised to one spot.',
            'A new pigmented lesion appearing for the first time after age 40.',
            'Any lesion on the palm, sole, nail bed or mucous membrane.',
          ]),
          const SizedBox(height: 4),
          const _InfoNote(
            'Melanoma found early is usually curable with simple excision; found late it is '
            'not. When in doubt, get it looked at — the cost of a false alarm is one visit.',
            icon: Icons.access_time_rounded,
            color: Themes.danger,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NearbyDoctorsScreen())),
            style: FilledButton.styleFrom(backgroundColor: Themes.danger),
            icon: const Icon(Icons.location_on_outlined, size: 18),
            label: const Text('Find a dermatologist near me'),
          ),
        ],
      );
}

// ---------------------------------------------------------------------------
// 4 — Sun protection
// ---------------------------------------------------------------------------

class _SunProtection extends StatelessWidget {
  const _SunProtection();

  static const _uvBands = <(String, String, Color)>[
    ('0–2', 'Low — minimal protection needed', Themes.mint),
    ('3–5', 'Moderate — sunscreen and shade at midday', Color(0xFFEBC53F)),
    ('6–7', 'High — sunscreen, hat, shade', Themes.warning),
    ('8–10', 'Very high — avoid midday sun', Color(0xFFEF6C3A)),
    ('11+', 'Extreme — stay indoors at peak hours', Themes.danger),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Themes.darkInk : Themes.ink;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How much protection SPF actually gives',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: ink)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _SpfStat('SPF 15', '≈93%', 'UVB blocked', dark)),
          const SizedBox(width: 8),
          Expanded(child: _SpfStat('SPF 30', '≈97%', 'UVB blocked', dark)),
          const SizedBox(width: 8),
          Expanded(child: _SpfStat('SPF 50', '≈98%', 'UVB blocked', dark)),
        ]),
        const SizedBox(height: 10),
        const _InfoNote(
          'Nothing reaches 100%. Beyond SPF 50 the extra benefit is marginal — how much '
          'you apply and how often you reapply matters far more than the number.',
        ),
        const SizedBox(height: 16),
        Text('Apply enough — most people use half of what they should',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: ink)),
        const SizedBox(height: 8),
        const _Bullets(color: Themes.warning, items: [
          'Face and neck: about half a teaspoon (2–3 ml).',
          'Whole body: about 30 ml — roughly a shot glass.',
          'Reapply every two hours, and straight after swimming or towelling.',
          'Apply 15–20 minutes before going out so it binds to the skin.',
        ]),
        const SizedBox(height: 12),
        Text('UV index — what the number means',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: ink)),
        const SizedBox(height: 8),
        for (final b in _uvBands) _uvRow(b.$1, b.$2, b.$3, dark),
        const SizedBox(height: 10),
        const _Bullets(color: Themes.warning, items: [
          'Up to 80% of UV passes through light cloud — overcast is not safe.',
          'Window glass blocks UVB but not UVA, which still ages and damages skin.',
          'Snow reflects up to 80% of UV, sand about 15%, water about 10%.',
          'Tightly woven or UPF 50 fabric outperforms any sunscreen.',
          'Tanning beds emit concentrated UVA and raise melanoma risk — avoid entirely.',
        ]),
      ],
    );
  }

  Widget _uvRow(String range, String meaning, Color color, bool dark) {
    final ink = dark ? Themes.darkInk : Themes.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
          child: Text(range,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5)),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Text(meaning, style: TextStyle(fontSize: 12.8, height: 1.3, color: ink))),
      ]),
    );
  }
}

class _SpfStat extends StatelessWidget {
  const _SpfStat(this.label, this.value, this.caption, this.dark);
  final String label;
  final String value;
  final String caption;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Themes.warning.withValues(alpha: dark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Themes.warning.withValues(alpha: dark ? 0.40 : 0.30)),
      ),
      child: Column(children: [
        Text(label,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: inkSoft)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w900, color: Themes.warning)),
        Text(caption,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: inkSoft)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// 5 — Self-exam checklist + reminder
// ---------------------------------------------------------------------------

class _SelfExamChecklist extends StatelessWidget {
  const _SelfExamChecklist();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Do this in bright light with a full-length and a hand mirror. Work in the same '
          'order every month so nothing is missed, and photograph anything you are '
          'watching so next month has something to compare against.',
          style: TextStyle(color: inkSoft, height: 1.4, fontSize: 13),
        ),
        const SizedBox(height: 12),
        const _Checklist(
          color: Themes.mint,
          doneLabel: 'Full check complete — note anything new before you finish.',
          items: [
            'Face, lips, ears and behind the ears.',
            'Scalp — part the hair in sections, or ask for help.',
            'Neck, chest and torso; lift the breasts to see underneath.',
            'Underarms, both sides of arms, elbows.',
            'Hands: palms, backs, between fingers, and under the nails.',
            'Back and shoulders using a mirror, or ask a partner.',
            'Buttocks and genital area.',
            'Front and back of thighs and shins.',
            'Calves and behind the knees.',
            'Feet: tops, soles, heels, and between the toes.',
          ],
        ),
        const SizedBox(height: 12),
        const _SelfExamReminderTile(),
      ],
    );
  }
}

class _SelfExamReminderTile extends StatelessWidget {
  const _SelfExamReminderTile();

  static String _fmt(DateTime d) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;

    return ValueListenableBuilder<bool>(
      valueListenable: SelfExamReminder.enabled,
      builder: (_, enabled, __) => Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
        decoration: BoxDecoration(
          color: Themes.mint.withValues(alpha: dark ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Themes.mint.withValues(alpha: dark ? 0.40 : 0.35)),
        ),
        child: Row(children: [
          const Icon(Icons.notifications_active_outlined, color: Themes.mint, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: ValueListenableBuilder<DateTime?>(
              valueListenable: SelfExamReminder.nextDue,
              builder: (_, due, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Monthly reminder',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: ink)),
                  Text(
                    enabled && due != null
                        ? 'Next prompt around ${_fmt(due)}'
                        : 'Prompts you in-app when the next check is due.',
                    style: TextStyle(color: inkSoft, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          Switch(
            value: enabled,
            onChanged: (on) async {
              on ? await SelfExamReminder.enable() : await SelfExamReminder.disable();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text(on
                      ? 'Monthly self-exam reminder on.'
                      : 'Reminder turned off.'),
                ));
              }
            },
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6 — Understanding results
// ---------------------------------------------------------------------------

class _UnderstandingResults extends StatelessWidget {
  const _UnderstandingResults();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _Labelled('Model score is not a probability of disease',
              'A score of 78% means the image resembled that category strongly relative to '
              'the others the model knows. It is not a 78% chance you have the condition. '
              'The model has never seen your history, and it can only choose between the '
              'classes it was trained on.'),
          _Labelled('Triage band is the part to act on',
              'Routine monitoring, prompt consultation and urgent evaluation describe how '
              'quickly to get a human opinion. The band deliberately errs toward caution, '
              'so it can be more urgent than the top prediction alone suggests.'),
          _Labelled('Low confidence means the image was ambiguous',
              'Poor lighting, blur, hair, or a lesion the model was not trained on all '
              'lower confidence. Treat a low-confidence result as "unknown", not "benign", '
              'and retake the photo or see a clinician.'),
          _Labelled('The heatmap shows attention, not reasoning',
              'Warm regions influenced the output most. Heat centred on the lesion is '
              'reassuring; heat on background skin, hair or a ruler suggests the model '
              'latched onto an artefact and the result should be discounted.'),
          _Labelled('What this screening cannot do',
              'It cannot rule out cancer, assess depth or spread, replace dermoscopy or '
              'biopsy, or track change over time on its own. A negative screen on a lesion '
              'that worries you does not cancel that worry.'),
        ],
      );
}

class _Labelled extends StatelessWidget {
  const _Labelled(this.title, this.body);
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.check_circle_outline_rounded, size: 16, color: Themes.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: TextStyle(fontWeight: FontWeight.w800, height: 1.3, color: ink)),
          ),
        ]),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Text(body,
              style: TextStyle(color: inkSoft, height: 1.45, fontSize: 12.8)),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// 7 — Condition explorer
// ---------------------------------------------------------------------------

class _Condition {
  const _Condition(this.name, this.urgency, this.looks, this.detail);
  final String name;
  final String urgency; // 'urgent' | 'check' | 'routine'
  final String looks;
  final String detail;
}

class _ConditionExplorer extends StatefulWidget {
  const _ConditionExplorer();

  @override
  State<_ConditionExplorer> createState() => _ConditionExplorerState();
}

class _ConditionExplorerState extends State<_ConditionExplorer> {
  int _selected = 0;

  static const _conditions = <_Condition>[
    _Condition(
      'Melanoma',
      'urgent',
      'Dark, irregular, changing; may be pink or unpigmented.',
      'The most dangerous skin cancer, arising from pigment-producing cells. Often shows '
          'several ABCDE features at once. Most arise on normal skin rather than in an '
          'existing mole. Highly curable when removed early, which is why any changing '
          'pigmented lesion is assessed quickly.',
    ),
    _Condition(
      'Basal cell carcinoma',
      'check',
      'Pearly or waxy bump, sometimes with visible small vessels.',
      'The most common skin cancer. Grows slowly and very rarely spreads, but it erodes '
          'local tissue if ignored, which matters on the face. Often presents as a sore '
          'that bleeds, scabs, heals and returns in the same place.',
    ),
    _Condition(
      'Squamous cell carcinoma',
      'check',
      'Firm red nodule or a scaly, crusted, sometimes tender patch.',
      'Second most common skin cancer, linked to cumulative sun exposure. Can spread if '
          'left untreated, so it is removed promptly. Frequently appears on the head, '
          'neck, ears, lips and backs of the hands.',
    ),
    _Condition(
      'Actinic keratosis',
      'check',
      'Rough, sandpapery patch that is easier felt than seen.',
      'Sun-damage lesion regarded as pre-malignant: a small fraction progress to squamous '
          'cell carcinoma. Commonly treated with cryotherapy or topical therapy, and taken '
          'as a signal to tighten sun protection.',
    ),
    _Condition(
      'Benign mole (nevus)',
      'routine',
      'Even colour, smooth border, stable over years.',
      'A normal cluster of pigment cells. Most adults have 10–40. Reassuring features are '
          'symmetry, a single shade, and no change. Worth photographing so that future '
          'change is easy to spot.',
    ),
    _Condition(
      'Seborrhoeic keratosis',
      'routine',
      'Waxy, "stuck-on" brown plaque with a warty surface.',
      'A very common benign growth that increases with age. Harmless, though frequently '
          'mistaken for melanoma because it can be dark and irregular. Removed only for '
          'comfort or cosmetic reasons.',
    ),
    _Condition(
      'Eczema (atopic dermatitis)',
      'routine',
      'Dry, itchy, red or darkened inflamed patches; may weep.',
      'A chronic inflammatory condition, not cancer. Flares with irritants, allergens, '
          'heat and stress. Managed with emollients, avoiding triggers, and topical '
          'anti-inflammatories. See a doctor if it is infected or not settling.',
    ),
    _Condition(
      'Psoriasis',
      'routine',
      'Well-defined plaques with silvery scale, often on elbows and knees.',
      'An immune-mediated condition with accelerated skin-cell turnover. Chronic and '
          'relapsing, sometimes with joint involvement. Many effective treatments exist, '
          'so a dermatology review is worthwhile.',
    ),
    _Condition(
      'Fungal infection (tinea)',
      'routine',
      'Ring-shaped patch with a raised, scaly, advancing edge.',
      'A superficial infection of skin, hair or nails. Typically itchy and spreading '
          'outward with central clearing. Treated with topical or oral antifungals; it is '
          'contagious through contact and shared items.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;
    final c = _conditions[_selected];
    final (color, label) = switch (c.urgency) {
      'urgent' => (Themes.danger, 'See a doctor promptly'),
      'check' => (Themes.warning, 'Get it checked'),
      _ => (Themes.mint, 'Usually harmless'),
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (var i = 0; i < _conditions.length; i++)
            ChoiceChip(
              label: Text(_conditions[i].name),
              selected: _selected == i,
              showCheckmark: false,
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _selected == i ? Colors.white : ink,
              ),
              selectedColor: Themes.primary,
              backgroundColor: dark ? const Color(0xFF1B202A) : Themes.surface,
              side: BorderSide(
                  color: _selected == i ? Themes.primary : (dark ? Themes.darkBorder : Themes.border)),
              onSelected: (_) => setState(() => _selected = i),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: dark ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: dark ? 0.45 : 0.32)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(c.name,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: ink)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration:
                  BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.visibility_outlined, size: 15, color: inkSoft),
            const SizedBox(width: 6),
            Expanded(
              child: Text(c.looks,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600, color: ink)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(c.detail,
              style: TextStyle(color: inkSoft, height: 1.45, fontSize: 12.6)),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// 8 — Myth buster
// ---------------------------------------------------------------------------

class _MythBuster extends StatefulWidget {
  const _MythBuster();

  @override
  State<_MythBuster> createState() => _MythBusterState();
}

class _MythBusterState extends State<_MythBuster> {
  final Set<int> _revealed = {};

  static const _myths = <(String, String)>[
    (
      'Darker skin does not get skin cancer.',
      'It does, and outcomes are often worse because it is found later. Melanoma in '
          'darker skin favours the palms, soles and nail beds — check those areas.'
    ),
    (
      'You only need sunscreen when it is sunny.',
      'Up to 80% of UV penetrates light cloud, and UVA passes through window glass. '
          'Daily protection matters far more than perceived brightness.'
    ),
    (
      'A base tan protects you from burning.',
      'A tan is DNA damage responding to UV. Its protective effect is roughly SPF 3 — '
          'negligible, while the damage that produced it is permanent.'
    ),
    (
      'Most melanomas start in an existing mole.',
      'The majority arise on previously normal skin. That is why a genuinely new spot '
          'deserves as much attention as a changing old one.'
    ),
    (
      'Sunscreen causes vitamin D deficiency.',
      'Everyday sunscreen use has not been shown to cause deficiency in practice. If '
          'levels are low, supplementation is safer than deliberate UV exposure.'
    ),
    (
      'Skin cancer only affects older people.',
      'Melanoma is among the more common cancers in young adults, and childhood sunburn '
          'raises lifetime risk substantially.'
    ),
    (
      'If it does not hurt, it is not serious.',
      'Most early skin cancers are entirely painless. Appearance and change are the '
          'signals; pain is a late and unreliable one.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _myths.length; i++) _tile(i, dark),
      ],
    );
  }

  Widget _tile(int i, bool dark) {
    final open = _revealed.contains(i);
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;
    final cardBg = dark ? const Color(0xFF1B202A) : Colors.white;
    final borderColor = dark ? Themes.darkBorder : Themes.border;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => open ? _revealed.remove(i) : _revealed.add(i)),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 1.0),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Themes.danger.withValues(alpha: dark ? 0.20 : 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('MYTH',
                      style: TextStyle(
                          fontSize: 9.5, fontWeight: FontWeight.w900, color: Themes.danger)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_myths[i].$1,
                      style: TextStyle(fontWeight: FontWeight.w700, height: 1.35, color: ink)),
                ),
                Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 20, color: inkSoft),
              ]),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 180),
                crossFadeState:
                    open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Themes.mint.withValues(alpha: dark ? 0.22 : 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('FACT',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: Themes.mint)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_myths[i].$2,
                          style: TextStyle(
                              color: inkSoft, height: 1.45, fontSize: 12.8)),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 9 — Searchable glossary
// ---------------------------------------------------------------------------

class _Glossary extends StatefulWidget {
  const _Glossary();

  @override
  State<_Glossary> createState() => _GlossaryState();
}

class _GlossaryState extends State<_Glossary> {
  String _query = '';

  static const _terms = <(String, String)>[
    ('Benign', 'Not cancer. Harmless, though it may still be removed for comfort.'),
    ('Malignant', 'Cancerous — able to invade nearby tissue and potentially spread.'),
    ('Pre-malignant',
        'Not cancer yet, but carries a real chance of becoming cancer if untreated.'),
    ('Melanoma',
        'Cancer of pigment-producing cells. Often dark and changing; the most dangerous '
            'common skin cancer, and highly curable when caught early.'),
    ('Carcinoma',
        'Cancer arising from the skin’s surface cells. Basal and squamous cell carcinoma '
            'are the two common types.'),
    ('Nevus', 'The medical word for a mole — a benign cluster of pigment cells.'),
    ('Dysplastic nevus',
        'An atypical mole with irregular features. Usually benign but monitored, as it '
            'signals slightly higher melanoma risk.'),
    ('Lesion', 'Any abnormal area of skin — a neutral catch-all term, not a diagnosis.'),
    ('Dermoscopy',
        'Examination with a magnifying lens and light that reveals sub-surface patterns '
            'invisible to the naked eye.'),
    ('Biopsy',
        'Removing a small sample of tissue for laboratory examination. The only way to '
            'diagnose skin cancer definitively.'),
    ('Excision', 'Surgical removal of a lesion, usually with a margin of normal skin.'),
    ('Metastasis', 'Spread of cancer from where it started to other parts of the body.'),
    ('In situ', 'Confined to the top layer of skin, with no invasion deeper. Very curable.'),
    ('UVA',
        'Longer-wave ultraviolet. Penetrates deeply, drives ageing, passes through glass '
            'and cloud, and contributes to cancer risk.'),
    ('UVB', 'Shorter-wave ultraviolet. The main cause of sunburn and of DNA damage.'),
    ('SPF',
        'Sun protection factor — how well a product blocks UVB. SPF 30 blocks about 97%.'),
    ('Broad spectrum', 'A sunscreen that protects against both UVA and UVB.'),
    ('Fitzpatrick scale',
        'A I–VI classification of how skin responds to UV, used to tailor sun advice.'),
    ('Erythema', 'Redness of the skin from increased blood flow — for example, sunburn.'),
    ('Pruritus', 'The medical term for itching.'),
    ('Triage',
        'Sorting by urgency — in this app, how soon you should get a lesion examined.'),
    ('Grad-CAM',
        'The technique behind the heatmap: it highlights the image regions that most '
            'influenced the model’s output.'),
    ('Dermatologist', 'A doctor who specialises in conditions of the skin, hair and nails.'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;
    final q = _query.trim().toLowerCase();
    final matches = q.isEmpty
        ? _terms
        : _terms
            .where((t) => t.$1.toLowerCase().contains(q) || t.$2.toLowerCase().contains(q))
            .toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search terms…',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: q.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => _query = ''),
                ),
        ),
      ),
      const SizedBox(height: 12),
      if (matches.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text('No matching term.', style: TextStyle(color: inkSoft)),
        )
      else
        for (final t in matches) _row(t.$1, t.$2, dark),
    ]);
  }

  Widget _row(String term, String meaning, bool dark) {
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(term,
            style: TextStyle(fontWeight: FontWeight.w800, color: ink)),
        const SizedBox(height: 2),
        Text(meaning,
            style: TextStyle(color: inkSoft, height: 1.42, fontSize: 12.8)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// 10 — Fitzpatrick questionnaire
// ---------------------------------------------------------------------------

class _FitzQuestion {
  const _FitzQuestion(this.group, this.prompt, this.choices);
  final String group;
  final String prompt;
  final List<(String, int)> choices; // label, score 0–4
}

class _FitzType {
  const _FitzType(this.roman, this.name, this.summary, this.advice, this.burnTime);
  final String roman;
  final String name;
  final String summary;
  final String advice;
  final String burnTime;
}

class _FitzpatrickQuiz extends StatefulWidget {
  const _FitzpatrickQuiz();

  @override
  State<_FitzpatrickQuiz> createState() => _FitzpatrickQuizState();
}

class _FitzpatrickQuizState extends State<_FitzpatrickQuiz> {
  static const _questions = <_FitzQuestion>[
    _FitzQuestion('Genetic disposition', 'Your eye colour:', [
      ('Light blue, grey or green', 0),
      ('Blue, grey or green', 1),
      ('Blue', 2),
      ('Dark brown', 3),
      ('Brownish black', 4),
    ]),
    _FitzQuestion('Genetic disposition', 'Your natural hair colour:', [
      ('Red or light blond', 0),
      ('Blond', 1),
      ('Chestnut or dark blond', 2),
      ('Dark brown', 3),
      ('Black', 4),
    ]),
    _FitzQuestion('Genetic disposition', 'Your skin colour on unexposed areas:', [
      ('Reddish', 0),
      ('Very pale', 1),
      ('Pale with a beige tint', 2),
      ('Light brown', 3),
      ('Dark brown', 4),
    ]),
    _FitzQuestion('Genetic disposition', 'Freckles on unexposed skin:', [
      ('Many', 0),
      ('Several', 1),
      ('Few', 2),
      ('Very few', 3),
      ('None', 4),
    ]),
    _FitzQuestion('Reaction to sun', 'When you stay too long in the sun:', [
      ('Painful redness, blistering, peeling', 0),
      ('Blistering followed by peeling', 1),
      ('Burns sometimes, then peels', 2),
      ('Rare burns', 3),
      ('Never had a burn', 4),
    ]),
    _FitzQuestion('Reaction to sun', 'To what degree do you turn brown?', [
      ('Hardly or not at all', 0),
      ('Light colour tan', 1),
      ('Reasonable tan', 2),
      ('Very easy tan', 3),
      ('Turn dark brown quickly', 4),
    ]),
    _FitzQuestion('Reaction to sun', 'Do you turn brown within several hours of sun?', [
      ('Never', 0),
      ('Seldom', 1),
      ('Sometimes', 2),
      ('Often', 3),
      ('Always', 4),
    ]),
    _FitzQuestion('Reaction to sun', 'How does your face react to the sun?', [
      ('Very sensitive', 0),
      ('Sensitive', 1),
      ('Normal', 2),
      ('Very resistant', 3),
      ('Never had a problem', 4),
    ]),
    _FitzQuestion('Tanning habits', 'When did you last expose your body to the sun?', [
      ('More than 3 months ago', 0),
      ('2–3 months ago', 1),
      ('1–2 months ago', 2),
      ('Less than a month ago', 3),
      ('Less than 2 weeks ago', 4),
    ]),
    _FitzQuestion('Tanning habits', 'How often is the area in question exposed to sun?', [
      ('Never', 0),
      ('Hardly ever', 1),
      ('Sometimes', 2),
      ('Often', 3),
      ('Always', 4),
    ]),
    _FitzQuestion('Risk history', 'Blistering sunburns before the age of 18:', [
      ('Three or more', 0),
      ('Two', 1),
      ('One', 2),
      ('None that you recall', 3),
      ('Never burns at all', 4),
    ]),
    _FitzQuestion('Risk history', 'Family history of melanoma or skin cancer:', [
      ('A parent, sibling or child affected', 0),
      ('A more distant relative affected', 2),
      ('None known', 4),
    ]),
  ];

  static const _types = <_FitzType>[
    _FitzType('I', 'Very fair — always burns, never tans',
        'Highly UV-sensitive skin, often with red or blond hair and freckles.',
        'SPF 50+ daily, reapply every 2 hours, prioritise shade and clothing over sunscreen alone.',
        'Can burn in 10–15 minutes at high UV'),
    _FitzType('II', 'Fair — burns easily, tans minimally',
        'Burns readily and tans only slightly; cumulative damage builds quickly.',
        'SPF 50 daily, reapply every 2 hours, hat and sunglasses outdoors.',
        'Can burn in 15–20 minutes at high UV'),
    _FitzType('III', 'Medium — sometimes burns, tans gradually',
        'Can burn after long exposure but usually develops a tan.',
        'SPF 30–50 daily; reapply on long outdoor days and near water or snow.',
        'Can burn in 20–30 minutes at high UV'),
    _FitzType('IV', 'Olive — burns minimally, tans easily',
        'Rarely burns and tans well, but UV still causes ageing and DNA damage.',
        'SPF 30 daily; increase at altitude, on water, or in strong midday sun.',
        'Can burn in 30–45 minutes at high UV'),
    _FitzType('V', 'Brown — very rarely burns, tans darkly',
        'Burning is uncommon; skin cancer is less frequent but often detected later.',
        'SPF 30 on exposed skin; do not skip self-exams, especially palms, soles and nails.',
        'Rarely burns, but damage still accumulates'),
    _FitzType('VI', 'Deeply pigmented — almost never burns',
        'Natural pigment gives substantial protection, but not immunity.',
        'SPF 30 on exposed skin; check palms, soles, nail beds and mouth regularly.',
        'Very rarely burns, but damage still accumulates'),
  ];

  final Map<int, int> _answers = {};
  int _index = 0;

  bool get _complete => _answers.length == _questions.length;
  int get _total => _answers.values.fold(0, (a, b) => a + b);

  void _answer(int score) {
    setState(() {
      _answers[_index] = score;
      if (_index < _questions.length - 1) _index++;
    });
  }

  void _reset() => setState(() {
        _answers.clear();
        _index = 0;
      });

  _FitzType get _result {
    final t = _total;
    if (t <= 9) return _types[0];
    if (t <= 19) return _types[1];
    if (t <= 30) return _types[2];
    if (t <= 36) return _types[3];
    if (t <= 42) return _types[4];
    return _types[5];
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_complete) return _resultView(dark);

    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;
    final q = _questions[_index];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Themes.primary.withValues(alpha: dark ? 0.20 : 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(q.group,
              style: const TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w800, color: Themes.primary)),
        ),
        const Spacer(),
        Text('${_index + 1} of ${_questions.length}',
            style: TextStyle(
                color: inkSoft, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: _answers.length / _questions.length,
          minHeight: 6,
          backgroundColor: dark ? const Color(0xFF262C38) : Themes.border,
          color: Themes.primary,
        ),
      ),
      const SizedBox(height: 14),
      Text(q.prompt,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, height: 1.35, color: ink)),
      const SizedBox(height: 10),
      for (final c in q.choices) _choice(c.$1, c.$2, dark),
      const SizedBox(height: 6),
      Row(children: [
        if (_index > 0)
          TextButton.icon(
            onPressed: () => setState(() => _index--),
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Back'),
          ),
        const Spacer(),
        if (_answers.isNotEmpty)
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Restart'),
          ),
      ]),
    ]);
  }

  Widget _choice(String label, int score, bool dark) {
    final selected = _answers[_index] == score;
    final ink = dark ? Themes.darkInk : Themes.ink;
    final unselectedBg = dark ? const Color(0xFF1B202A) : Colors.white;
    final unselectedBorder = dark ? Themes.darkBorder : Themes.border;
    final unselectedIcon = dark ? Themes.darkInkSoft : Themes.border;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: selected ? Themes.primary : unselectedBg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _answer(score),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? Themes.primary : unselectedBorder),
            ),
            child: Row(children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: selected ? Colors.white : unselectedIcon,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.3,
                      color: selected ? Colors.white : ink,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    )),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _resultView(bool dark) {
    final t = _result;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.muted;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Themes.primary, Themes.primaryDark]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Type ${t.roman}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
            ),
            const Spacer(),
            Text('Score $_total / 48',
                style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
          ]),
          const SizedBox(height: 10),
          Text(t.name,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Text(t.summary,
              style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 12.8)),
        ]),
      ),
      const SizedBox(height: 12),
      _resultRow(Icons.wb_sunny_outlined, 'Burn risk', t.burnTime, Themes.warning, dark),
      const SizedBox(height: 8),
      _resultRow(Icons.shield_outlined, 'Your sun routine', t.advice, Themes.mint, dark),
      const SizedBox(height: 12),
      const _InfoNote(
        'Skin type describes UV sensitivity, not risk on its own. Family history, mole '
        'count and past sunburns matter too — every type should still self-examine monthly.',
      ),
      const SizedBox(height: 8),
      Row(children: [
        OutlinedButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('Retake'),
        ),
      ]),
      const SizedBox(height: 6),
      Text('A self-assessment aid, not a medical test.',
          style: TextStyle(
              color: inkSoft, fontSize: 11.5, fontStyle: FontStyle.italic)),
    ]);
  }

  Widget _resultRow(IconData icon, String label, String text, Color color, bool dark) {
    final ink = dark ? Themes.darkInk : Themes.ink;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: dark ? 0.38 : 0.28)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 9),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 12.5, color: color)),
            const SizedBox(height: 2),
            Text(text, style: TextStyle(height: 1.4, fontSize: 12.8, color: ink)),
          ]),
        ),
      ]),
    );
  }
}
