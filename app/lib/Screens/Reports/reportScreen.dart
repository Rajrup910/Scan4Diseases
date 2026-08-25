import 'dart:io';

import 'package:flutter/material.dart';
import '../theme.dart';
import '../app_data.dart';
import '../Upload/ResultData.dart';
import 'compareScreen.dart';
import 'reportSummarySheet.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _searchQuery = '';
  String _filterTriage = 'all'; // 'all' | 'urgent' | 'prompt' | 'routine'

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<List<ScreeningReport>>(
        valueListenable: AppData.reports,
        builder: (_, reports, __) {
          final filtered = reports.where((r) {
            final matchesQuery = _searchQuery.isEmpty ||
                r.condition.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                r.triage.toLowerCase().contains(_searchQuery.toLowerCase());
            final triageLower = r.triage.toLowerCase();
            final matchesTriage = switch (_filterTriage) {
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
                const Expanded(
                  child: Text('My screenings',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Themes.ink, letterSpacing: -0.01, shadows: Themes.onMedia)),
                ),
                if (reports.length >= 2)
                  Container(
                    height: 36,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: Themes.liquidGlassDecoration(radius: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CompareScreeningsScreen()),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.compare_arrows_rounded, size: 16, color: Themes.brand),
                            SizedBox(width: 5),
                            Text(
                              'Compare 2',
                              style: TextStyle(
                                color: Themes.brand,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (reports.isNotEmpty)
                  Container(
                    height: 36,
                    width: 36,
                    decoration: Themes.liquidGlassDecoration(radius: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _confirmClearAll(context, reports.length),
                        child: const Center(
                          child: Icon(Icons.delete_sweep_outlined, color: Themes.danger, size: 18),
                        ),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 2),
              Text('${reports.length} saved report${reports.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: Themes.ink, fontSize: 13, shadows: Themes.onMedia)),
              const SizedBox(height: 14),
              if (reports.isNotEmpty) ...[
                // Search field
                TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0x66FFFFFF),
                    hintText: 'Search by condition or triage…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Themes.inkSoft),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.85), width: 1.2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Themes.brand, width: 1.5),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
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
                      _filterChip('All', 'all', reports.length),
                      const SizedBox(width: 8),
                      _filterChip('Urgent', 'urgent',
                          reports.where((r) => r.triage.toLowerCase().contains('urgent')).length),
                      const SizedBox(width: 8),
                      _filterChip('Prompt', 'prompt',
                          reports.where((r) => r.triage.toLowerCase().contains('prompt') || r.triage.toLowerCase().contains('soon')).length),
                      const SizedBox(width: 8),
                      _filterChip('Routine', 'routine',
                          reports.where((r) => !r.triage.toLowerCase().contains('urgent') && !r.triage.toLowerCase().contains('prompt')).length),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (reports.isEmpty)
                _empty()
              else if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  alignment: Alignment.center,
                  child: const Text('No screenings matched your search or filter.',
                      style: TextStyle(color: Themes.inkSoft, fontSize: 13)),
                )
              else ...[
                const Text('Swipe a card left to delete, or tap to view full screening analysis.',
                    style: TextStyle(color: Themes.ink, fontSize: 12.5, shadows: Themes.onMedia)),
                const SizedBox(height: 12),
                ...filtered.map((r) => _reportCard(context, r)),
              ],
            ],
          );
        },
      );

  Widget _filterChip(String label, String value, int count) {
    final active = _filterTriage == value;
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: active,
      selectedColor: Themes.brandTint.withValues(alpha: 0.70),
      backgroundColor: const Color(0x80FFFFFF),
      labelStyle: TextStyle(
        color: active ? Themes.brand : Themes.inkSoft,
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: active ? Themes.brand : Colors.white.withValues(alpha: 0.85),
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

  Widget _empty() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        decoration: Themes.liquidGlassDecoration(radius: 20),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Themes.brandTint,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.2),
            ),
            child: const Icon(Icons.assignment_outlined, size: 38, color: Themes.brand),
          ),
          const SizedBox(height: 16),
          const Text('No screenings yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Themes.ink)),
          const SizedBox(height: 6),
          const Text('Your completed AI-assisted screening reports will appear here.',
              textAlign: TextAlign.center, style: TextStyle(color: Themes.inkSoft, fontSize: 13, height: 1.4)),
        ]),
      );

  Widget _reportCard(BuildContext context, ScreeningReport r) {
    final triageLower = r.triage.toLowerCase();
    final (triageColor, triageBg, triageIcon) = triageLower.contains('urgent')
        ? (Themes.urgent, Themes.urgentBg, Icons.priority_high_rounded)
        : triageLower.contains('prompt') || triageLower.contains('soon')
            ? (Themes.soon, Themes.soonBg, Icons.schedule_rounded)
            : (Themes.routine, Themes.routineBg, Icons.check_circle_outline_rounded);

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
        child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.85), width: 1.2),
        ),
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
              _lesionThumb(r),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.condition,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Themes.ink)),
                  const SizedBox(height: 4),
                  Text(_date(r.date), style: const TextStyle(color: Themes.inkSoft, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Container(
                    height: 24,
                    constraints: const BoxConstraints(maxWidth: 185),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: triageBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: triageColor.withValues(alpha: 0.3)),
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
                icon: const Icon(Icons.summarize_outlined, color: Themes.brand, size: 20),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(context, r),
                icon: const Icon(Icons.delete_outline_rounded, color: Themes.inkSoft, size: 20),
              ),
            ]),
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
  Widget _lesionThumb(ScreeningReport r) {
    const size = 48.0;
    final path = r.imagePath ?? '';
    final hasPhoto = path.isNotEmpty && File(path).existsSync();

    final tile = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Themes.brandTint.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
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
                  const Icon(Icons.health_and_safety_outlined, color: Themes.brand, size: 24),
            )
          : const Icon(Icons.health_and_safety_outlined, color: Themes.brand, size: 24),
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

