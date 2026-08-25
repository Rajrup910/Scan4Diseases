import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/theme_service.dart';
import '../theme.dart';
import '../app_data.dart';
import '../widgets/video_background.dart';

/// Screen allowing side-by-side comparison of 2 screening reports.
///
/// Implements the clinical "E" (Evolution) of the ABCDE melanoma rule by tracking
/// changes in image, match score, and triage urgency over time.
class CompareScreeningsScreen extends StatefulWidget {
  const CompareScreeningsScreen({super.key, this.initialReport1, this.initialReport2});

  final ScreeningReport? initialReport1;
  final ScreeningReport? initialReport2;

  @override
  State<CompareScreeningsScreen> createState() => _CompareScreeningsScreenState();
}

class _CompareScreeningsScreenState extends State<CompareScreeningsScreen> {
  ScreeningReport? _reportA;
  ScreeningReport? _reportB;

  @override
  void initState() {
    super.initState();
    final reports = AppData.reports.value;
    if (widget.initialReport1 != null) {
      _reportA = widget.initialReport1;
    } else if (reports.isNotEmpty) {
      _reportA = reports.first;
    }

    if (widget.initialReport2 != null) {
      _reportB = widget.initialReport2;
    } else if (reports.length > 1) {
      _reportB = reports[1];
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.instance.mode,
      builder: (context, __, ___) {
        final dark = ThemeService.instance.isDark(context);
        return ValueListenableBuilder<List<ScreeningReport>>(
          valueListenable: AppData.reports,
          builder: (context, allReports, _) {
            if (allReports.length < 2) {
              return Scaffold(
                appBar: AppBar(title: const Text('Compare screenings')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: dark ? Themes.darkBrandTint : Themes.brandTint,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.compare_arrows_rounded, size: 36, color: dark ? Themes.tealLight : Themes.brand),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'At least 2 screenings required',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: dark ? Themes.darkInk : Themes.ink),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Save multiple screenings of a spot over time to track visual changes, match scores, and evolution.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: dark ? Themes.darkInkSoft : Themes.inkSoft, fontSize: 13, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Ensure selected reports are valid
            final reportA = _reportA ?? allReports[0];
            final reportB = _reportB ?? allReports[1];

            // Calculate time delta
            final daysDiff = (reportA.date.difference(reportB.date)).inDays.abs();

            return Scaffold(
              extendBodyBehindAppBar: true,
              appBar: AppBar(
                backgroundColor: dark
                    ? const Color(0xFF161920).withValues(alpha: 0.72)
                    : Colors.white.withValues(alpha: 0.85),
                foregroundColor: dark ? Themes.darkInk : Themes.ink,
                elevation: 0,
                scrolledUnderElevation: 1,
                title: const Text('Lesion Evolution (ABCDE)'),
              ),
              body: Stack(
                fit: StackFit.expand,
                children: [
                  const VideoBackground.ambient(),
                  SafeArea(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: dark ? const Color(0xFF142426) : Themes.brandTint,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: dark ? Themes.tealGlow.withValues(alpha: 0.3) : Themes.routineBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.history_edu_rounded, color: dark ? Themes.tealLight : Themes.brand, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Evolution tracking',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                        color: dark ? Themes.tealLight : Themes.brandDark,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$daysDiff days between selected screenings.',
                                      style: TextStyle(fontSize: 12, color: dark ? Themes.darkInkSoft : Themes.inkSoft),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Pickers Row
                        Row(
                          children: [
                            Expanded(
                              child: _reportPicker(
                                context,
                                'Baseline (Scan A)',
                                reportA,
                                allReports,
                                (r) => setState(() => _reportA = r),
                                dark,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _reportPicker(
                                context,
                                'Follow-up (Scan B)',
                                reportB,
                                allReports,
                                (r) => setState(() => _reportB = r),
                                dark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Side by side cards
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _screeningCard(reportA, 'Scan A', dark)),
                            const SizedBox(width: 10),
                            Expanded(child: _screeningCard(reportB, 'Scan B', dark)),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _evolutionAnalysis(reportA, reportB, dark),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _reportPicker(
    BuildContext context,
    String label,
    ScreeningReport selected,
    List<ScreeningReport> all,
    ValueChanged<ScreeningReport> onSelect,
    bool dark,
  ) {
    final accent = dark ? Themes.tealLight : Themes.brand;
    final ink = dark ? Themes.darkInk : Themes.ink;
    final menuBg = dark ? const Color(0xF8161922) : const Color(0xF8FFFFFF);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: dark ? Themes.darkInkSoft : Themes.inkSoft)),
        const SizedBox(height: 4),
        PopupMenuButton<ScreeningReport>(
          position: PopupMenuPosition.under,
          color: menuBg,
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: dark ? Themes.tealGlow.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.85),
              width: 1.2,
            ),
          ),
          onSelected: onSelect,
          itemBuilder: (context) => [
            for (final r in all)
              PopupMenuItem<ScreeningReport>(
                value: r,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${r.condition} (${_date(r.date)})',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: r == selected ? accent : ink,
                          fontWeight: r == selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (r == selected)
                      Icon(Icons.check_rounded, color: accent, size: 16),
                  ],
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: dark ? const Color(0x661E2430) : Colors.white.withValues(alpha: 0.60),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: dark ? Themes.tealGlow.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.85),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${selected.condition} (${_date(selected.date)})',
                    style: TextStyle(fontSize: 12.5, color: ink, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded, color: accent, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _screeningCard(ScreeningReport r, String tag, bool dark) {
    final triageLower = r.triage.toLowerCase();
    final triageColor = triageLower.contains('urgent')
        ? Themes.urgent
        : triageLower.contains('prompt') || triageLower.contains('soon')
            ? Themes.soon
            : (dark ? Themes.tealLight : Themes.routine);

    return Container(
      decoration: Themes.liquidGlassDecoration(radius: 18, dark: dark),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: dark ? Themes.darkBrandTint : Themes.brandTint,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tag,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: dark ? Themes.tealLight : Themes.brand),
                ),
              ),
              Text(_date(r.date), style: TextStyle(fontSize: 11.5, color: dark ? Themes.darkInkSoft : Themes.inkSoft)),
            ],
          ),
          const SizedBox(height: 10),
          // Image container
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF10141C) : Themes.canvas,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: dark ? Themes.tealGlow.withValues(alpha: 0.20) : Colors.white.withValues(alpha: 0.85),
                width: 1.2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: r.imagePath != null && File(r.imagePath!).existsSync()
                ? Image.file(File(r.imagePath!), fit: BoxFit.cover)
                : Center(
                    child: Icon(Icons.image_not_supported_outlined, color: dark ? Themes.darkInkSoft : Themes.inkMuted, size: 28),
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            r.condition,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: dark ? Themes.darkInk : Themes.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Match score: ',
                style: TextStyle(fontSize: 11.5, color: dark ? Themes.darkInkSoft : Themes.inkSoft),
              ),
              Text(
                r.confidence != null ? '${(r.confidence! * 100).toStringAsFixed(1)}%' : '—',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: dark ? Themes.darkInk : Themes.ink),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: triageColor.withValues(alpha: dark ? 0.18 : 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: triageColor.withValues(alpha: dark ? 0.45 : 0.3)),
            ),
            child: Text(
              r.triage,
              style: TextStyle(color: triageColor, fontWeight: FontWeight.w700, fontSize: 10.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _evolutionAnalysis(ScreeningReport a, ScreeningReport b, bool dark) {
    final confA = a.confidence ?? 0.0;
    final confB = b.confidence ?? 0.0;
    final delta = ((confB - confA) * 100).toStringAsFixed(1);
    final isIncrease = (confB - confA) > 0.02;

    return Container(
      decoration: Themes.liquidGlassDecoration(radius: 20, dark: dark),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: dark ? Themes.tealLight : Themes.brand, size: 20),
              const SizedBox(width: 8),
              Text(
                'Evolution comparison findings',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: dark ? Themes.darkInk : Themes.ink),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _diffRow(
            'Condition assessment',
            a.condition == b.condition ? 'Matched category unchanged (${a.condition})' : 'Category changed: ${a.condition} → ${b.condition}',
            a.condition != b.condition,
            dark,
          ),
          Divider(color: dark ? Themes.darkBorder : Themes.border),
          _diffRow(
            'Model match score delta',
            '${(confA * 100).toStringAsFixed(1)}% → ${(confB * 100).toStringAsFixed(1)}% (${isIncrease ? "+$delta%" : "$delta%"})',
            isIncrease,
            dark,
          ),
          Divider(color: dark ? Themes.darkBorder : Themes.border),
          _diffRow(
            'Triage urgency change',
            a.triage == b.triage ? 'Urgency level stable (${a.triage})' : '${a.triage} → ${b.triage}',
            a.triage != b.triage,
            dark,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF261E10) : Themes.warningTint,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: dark ? const Color(0xFF5A4418) : Themes.soonBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: dark ? Themes.tealLight : Themes.warning, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Any noticeable growth, darkening, bleeding, or irregular border evolution over time is a clinical sign to consult a dermatologist.',
                    style: TextStyle(fontSize: 12, height: 1.35, color: dark ? Themes.darkInk : Themes.ink),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _diffRow(String title, String value, bool isChanged, bool dark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              title,
              style: TextStyle(fontSize: 12.5, color: dark ? Themes.darkInkSoft : Themes.inkSoft, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isChanged ? (dark ? Themes.tealLight : Themes.soon) : (dark ? Themes.darkInk : Themes.ink),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
