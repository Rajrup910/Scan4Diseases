import 'dart:io';

import 'package:flutter/material.dart';
import '../theme.dart';
import '../app_data.dart';
import '../Upload/ResultData.dart';
import '../../services/theme_service.dart';
import 'compareScreen.dart';
import 'reportSummarySheet.dart';
import '../Share/share_with_doctor.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _searchQuery = '';
  String _filterTriage = 'all'; // 'all' | 'shared' | 'urgent' | 'prompt' | 'routine'

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeService.instance.mode,
        builder: (_, __, ___) => ValueListenableBuilder<List<ScreeningReport>>(
        valueListenable: AppData.reports,
        builder: (_, reports, __) {
          final dark = ThemeService.instance.isDark(context);
          final ink = dark ? Themes.darkInk : Themes.ink;
          final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
          final onMedia = dark ? Themes.onMediaDark : Themes.onMedia;
          final accent = dark ? Themes.tealLight : Themes.brand;
          final filtered = reports.where((r) {
            final matchesQuery = _searchQuery.isEmpty ||
                r.condition.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                r.triage.toLowerCase().contains(_searchQuery.toLowerCase());
            final triageLower = r.triage.toLowerCase();
            final matchesTriage = switch (_filterTriage) {
              'shared' => r.isShared,
              'urgent' => triageLower.contains('urgent'),
              'prompt' => triageLower.contains('prompt') || triageLower.contains('soon'),
              'routine' => triageLower.contains('routine') || (!triageLower.contains('urgent') && !triageLower.contains('prompt')),
              _ => true,
            };
            return matchesQuery && matchesTriage;
          }).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Row(children: [
                Expanded(
                  child: Text('My screenings',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: ink,
                        letterSpacing: -0.01,
                        shadows: onMedia,
                      )),
                ),
                if (reports.length >= 2)
                  Container(
                    height: 36,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: _glass(dark, radius: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CompareScreeningsScreen()),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.compare_arrows_rounded, size: 16, color: accent),
                              const SizedBox(width: 5),
                              Text(
                                'Compare 2',
                                style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (reports.isNotEmpty)
                  Container(
                    height: 36,
                    width: 36,
                    decoration: _glass(dark, radius: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _confirmClearAll(context, reports.length),
                        child: Center(
                          child: Icon(
                            Icons.delete_sweep_outlined,
                            color: dark ? const Color(0xFFF87171) : Themes.danger,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 2),
              Text('${reports.length} saved report${reports.length == 1 ? '' : 's'}',
                  style: TextStyle(color: ink, fontSize: 13, shadows: onMedia)),
              const SizedBox(height: 14),
              if (reports.isNotEmpty) ...[
                // Search field — dark glass fill with teal-tinted border to match the
                // Reports mockup, no white-on-dark contrast issue.
                TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TextStyle(color: ink),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: dark ? const Color(0x99232A36) : const Color(0x66FFFFFF),
                    hintText: 'Search by condition or triage…',
                    hintStyle: TextStyle(color: inkSoft),
                    prefixIcon: Icon(Icons.search_rounded, size: 20, color: inkSoft),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: dark
                            ? Themes.tealGlow.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.85),
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: accent, width: 1.5),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, size: 18, color: inkSoft),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                // Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('All', 'all', reports.length, dark),
                      const SizedBox(width: 8),
                      _filterChip('Shared', 'shared',
                          reports.where((r) => r.isShared).length, dark),
                      const SizedBox(width: 8),
                      _filterChip('Urgent', 'urgent',
                          reports.where((r) => r.triage.toLowerCase().contains('urgent')).length, dark),
                      const SizedBox(width: 8),
                      _filterChip('Prompt', 'prompt',
                          reports.where((r) => r.triage.toLowerCase().contains('prompt') || r.triage.toLowerCase().contains('soon')).length, dark),
                      const SizedBox(width: 8),
                      _filterChip('Routine', 'routine',
                          reports.where((r) => !r.triage.toLowerCase().contains('urgent') && !r.triage.toLowerCase().contains('prompt')).length, dark),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (reports.isEmpty)
                _empty(dark)
              else if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  alignment: Alignment.center,
                  child: Text('No screenings matched your search or filter.',
                      style: TextStyle(color: inkSoft, fontSize: 13)),
                )
              else ...[
                Text('Swipe a card left to delete, or tap to view full screening analysis.',
                    style: TextStyle(color: ink, fontSize: 12.5, shadows: onMedia)),
                const SizedBox(height: 12),
                ...filtered.map((r) => _reportCard(context, r, dark)),
              ],
            ],
          );
        },
      ));

  /// Central glass helper so every card on this screen shares one look.
  /// Kept private so it never leaks its `dark` argument outside this state.
  BoxDecoration _glass(bool dark, {double radius = 18}) => dark
      ? Themes.liquidGlassDecoration(radius: radius, dark: true, topAlpha: 0.85, bottomAlpha: 0.70)
      : Themes.liquidGlassDecoration(radius: radius);

  Widget _filterChip(String label, String value, int count, bool dark) {
    final active = _filterTriage == value;
    final activeText = dark ? Themes.tealLight : Themes.brand;
    final inactiveText = dark ? Themes.darkInkSoft : Themes.inkSoft;
    final activeBg = dark ? Themes.darkBrandTint : Themes.brandTint.withValues(alpha: 0.70);
    final inactiveBg = dark ? const Color(0x991C212B) : const Color(0x80FFFFFF);
    final activeBorder = dark ? Themes.tealGlow : Themes.brand;
    final inactiveBorder = dark ? Themes.darkBorder : Colors.white.withValues(alpha: 0.85);
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: active,
      selectedColor: activeBg,
      backgroundColor: inactiveBg,
      labelStyle: TextStyle(
        color: active ? activeText : inactiveText,
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: active ? activeBorder : inactiveBorder,
          width: 1.2,
        ),
      ),
      onSelected: (_) => setState(() => _filterTriage = value),
    );
  }

  // --- delete flows ----------------------------------------------------------

  Future<bool> _confirmDelete(BuildContext context, ScreeningReport r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: Themes.danger, size: 30),
        title: const Text('Delete this screening?'),
        content: Text(
          'This removes the "${r.condition}" report from ${_date(r.date)}. '
          'This cannot be undone.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Themes.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppData.deleteReport(r);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Screening deleted.'),
        ));
      }
      return true;
    }
    return false;
  }

  Future<void> _confirmClearAll(BuildContext context, int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_sweep_outlined, color: Themes.danger, size: 30),
        title: const Text('Delete all screenings?'),
        content: Text(
          'This permanently removes all $count saved report${count == 1 ? '' : 's'}. '
          'This cannot be undone.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Themes.danger),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final r in List<ScreeningReport>.from(AppData.reports.value)) {
      await AppData.deleteReport(r);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('All screenings deleted.'),
      ));
    }
  }

  // --- list items ------------------------------------------------------------

  Widget _empty(bool dark) {
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
    final accent = dark ? Themes.tealLight : Themes.brand;
    final tile = dark ? Themes.darkBrandTint : Themes.brandTint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: _glass(dark, radius: 20),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: tile,
            shape: BoxShape.circle,
            border: Border.all(
              color: dark
                  ? Themes.tealGlow.withValues(alpha: 0.27)
                  : Colors.white.withValues(alpha: 0.85),
              width: 1.2,
            ),
          ),
          child: Icon(Icons.assignment_outlined, size: 38, color: accent),
        ),
        const SizedBox(height: 16),
        Text('No screenings yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink)),
        const SizedBox(height: 6),
        Text('Your completed AI-assisted screening reports will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: inkSoft, fontSize: 13, height: 1.4)),
      ]),
    );
  }

  Widget _reportCard(BuildContext context, ScreeningReport r, bool dark) {
    final triageLower = r.triage.toLowerCase();
    // Triage tones split into (text, background, icon) — each also has a dark
    // counterpart so the badge reads as a proper glass pill on the dark canvas
    // rather than a chalky pastel rectangle.
    late final Color triageColor;
    late final Color triageBg;
    late final Color triageBorder;
    late final IconData triageIcon;
    if (triageLower.contains('urgent')) {
      triageColor = dark ? const Color(0xFFF87171) : Themes.urgent;
      triageBg = dark ? const Color(0xFF2A1010) : Themes.urgentBg;
      triageBorder = triageColor.withValues(alpha: dark ? 0.55 : 0.3);
      triageIcon = Icons.priority_high_rounded;
    } else if (triageLower.contains('prompt') || triageLower.contains('soon')) {
      triageColor = dark ? const Color(0xFFE0B463) : Themes.soon;
      triageBg = dark ? const Color(0xFF2A2411) : Themes.soonBg;
      triageBorder = triageColor.withValues(alpha: dark ? 0.55 : 0.3);
      triageIcon = Icons.schedule_rounded;
    } else {
      triageColor = dark ? const Color(0xFF5FD6AD) : Themes.routine;
      triageBg = dark ? const Color(0xFF0D2B23) : Themes.routineBg;
      triageBorder = triageColor.withValues(alpha: dark ? 0.55 : 0.3);
      triageIcon = Icons.check_circle_outline_rounded;
    }

    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
    final accent = dark ? Themes.tealLight : Themes.brand;

    // Dismissible carries `ObjectKey(r)` so Flutter identity-tracks each row
    // across filter changes; the TweenAnimationBuilder inside can therefore
    // animate exactly once per report — new rows fade+glide in when the
    // active filter first surfaces them, existing rows stay put.
    return Dismissible(
      key: ObjectKey(r),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context, r),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.only(right: 22),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Themes.danger,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.delete_outline_rounded, color: Colors.white),
          SizedBox(width: 6),
          Text('Delete',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 6 * (1 - t)), child: child),
        ),
        child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        decoration: _glass(dark, radius: 18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DiagnosisResultsUI(
                  diagnosisData: {
                    'predicted_class': r.condition,
                    'confidence': r.confidence,
                    'triage': r.triage,
                    'explanation': r.explanation,
                  },
                  report: r,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(children: [
                _lesionThumb(r, dark),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.condition,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(_date(r.date), style: TextStyle(color: inkSoft, fontSize: 12)),
                        const SizedBox(width: 8),
                        if (r.isShared)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: (dark ? Themes.tealLight : Themes.routine).withValues(alpha: dark ? 0.22 : 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: (dark ? Themes.tealLight : Themes.routine).withValues(alpha: dark ? 0.55 : 0.35),
                                width: 0.85,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_rounded, size: 11, color: dark ? Themes.tealLight : Themes.routine),
                                const SizedBox(width: 3.5),
                                Text(
                                  'Shared',
                                  style: TextStyle(
                                    color: dark ? Themes.tealLight : Themes.routine,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => showShareWithDoctorSheet(context, r),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: (dark ? Colors.white : Colors.black).withValues(alpha: dark ? 0.08 : 0.04),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: (dark ? Themes.darkBorder : Themes.border).withValues(alpha: 0.85),
                                    width: 0.85,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.lock_outline_rounded, size: 10, color: inkSoft),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Not shared',
                                      style: TextStyle(
                                        color: inkSoft,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 24,
                      constraints: const BoxConstraints(maxWidth: 185),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: triageBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: triageBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(triageIcon, size: 12, color: triageColor),
                          const SizedBox(width: 5),
                          Flexible(
                            child: _MarqueeText(
                              text: r.triage,
                              style: TextStyle(
                                color: triageColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
                IconButton(
                  tooltip: 'Clinical summary',
                  onPressed: () => showReportSummarySheet(context, r),
                  icon: Icon(Icons.summarize_outlined, color: accent, size: 20),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(context, r),
                  icon: Icon(Icons.delete_outline_rounded, color: inkSoft, size: 20),
                ),
              ]),
            ),
          ),
        ),
        ),
      ),
    );
  }

  /// The row's leading tile. When the saved lesion photo is still on disk it
  /// becomes the thumbnail and the shared [Hero] source for the flight into
  /// [DiagnosisResultsUI]; otherwise it falls back to the original brand icon.
  ///
  /// The Hero is only attached when the report has an id — an unsaved result
  /// has no stable tag, and a duplicate/missing tag would break the flight.
  Widget _lesionThumb(ScreeningReport r, bool dark) {
    const size = 48.0;
    final path = r.imagePath ?? '';
    final hasPhoto = path.isNotEmpty && File(path).existsSync();
    final accent = dark ? Themes.tealLight : Themes.brand;
    final tileBg = dark ? Themes.darkBrandTint : Themes.brandTint.withValues(alpha: 0.70);
    final tileEdge = dark
        ? Themes.tealGlow.withValues(alpha: 0.27)
        : Colors.white.withValues(alpha: 0.85);

    final tile = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tileEdge),
      ),
      child: hasPhoto
          ? Image.file(
              File(path),
              width: size,
              height: size,
              fit: BoxFit.cover,
              // If the file vanishes between the check and the decode, fall
              // back rather than showing a broken-image glyph.
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.health_and_safety_outlined, color: accent, size: 24),
            )
          : Icon(Icons.health_and_safety_outlined, color: accent, size: 24),
    );

    if (!hasPhoto || r.id == null) return tile;
    return Hero(tag: 'lesion-${r.id}', child: tile);
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_month(d.month)} ${d.year}';
  String _month(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}

/// Single-line horizontal rotating/marquee text widget.
/// Fits within the panel size of "Wound or skin injury" (height: 24dp).
/// Uses a horizontal scroll view to ensure 100% of characters (including complex scripts)
/// are fully rendered without clipping.
/// If text width exceeds the available badge width (such as "Prompt dermatologist consultation"
/// or "Urgent medical evaluation"), it smoothly scrolls from start to end (left to right),
/// pauses at the end, pauses at the start, and cycles smoothly.
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _MarqueeText({
    required this.text,
    required this.style,
  });

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  final ScrollController _scrollController = ScrollController();
  bool _animating = false;
  bool _disposed = false;

  /// True once the label has been measured as wider than the space it was
  /// given. Most triage strings ("Routine", "See a doctor soon") fit outright,
  /// and scrolling those was pure distraction — with four or five cards on
  /// screen the list never sat still. The loop now only ever runs for labels
  /// that genuinely need it.
  bool _overflows = false;

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  /// Starts the scroll loop on the next frame, once and only once.
  void _ensureLoop() {
    if (_animating || _disposed) return;
    _animating = true; // claim immediately so a rebuild can't double-start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _disposed) return;
      _animating = false; // _startAnimationLoop re-claims it
      _startAnimationLoop();
    });
  }

  Future<void> _startAnimationLoop() async {
    if (_animating || !mounted) return;
    _animating = true;

    // `_overflows` is set from the measured layout in build(); if the label
    // stops overflowing (rotation, a shorter triage string) the loop exits on
    // its next pass rather than idling forever.
    while (mounted && !_disposed && _overflows) {
      // 1. Initial pause at start (offset 0) so the user reads the beginning of the text
      await Future.delayed(const Duration(milliseconds: 1400));
      if (!mounted || _disposed) break;

      if (_scrollController.hasClients) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        if (maxExtent > 0) {
          // 2. Smoothly scroll from left to right (natural reading flow)
          final durationMs = (maxExtent * 30).clamp(1200, 3200).toInt();
          await _scrollController.animateTo(
            maxExtent,
            duration: Duration(milliseconds: durationMs),
            curve: Curves.easeInOutCubic,
          );
          if (!mounted || _disposed) break;

          // 3. Pause at the end so the user comfortably reads the rest
          await Future.delayed(const Duration(milliseconds: 1400));
          if (!mounted || _disposed) break;

          // 4. Smoothly return to the start
          final returnMs = (maxExtent * 18).clamp(800, 1800).toInt();
          await _scrollController.animateTo(
            0,
            duration: Duration(milliseconds: returnMs),
            curve: Curves.easeInOutCubic,
          );
          if (!mounted || _disposed) break;
        }
      }
    }
    _animating = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure the label at its natural width and compare against the space
        // actually available. An unbounded width (no constraint to overflow)
        // reads as "fits", which is the safe default.
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();

        _overflows = constraints.maxWidth.isFinite &&
            painter.width > constraints.maxWidth + 0.5;

        if (!_overflows) {
          // Static label — no controller, no loop, no repaint.
          return Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: widget.style,
          );
        }

        _ensureLoop();
        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            style: widget.style,
          ),
        );
      },
    );
  }
}

