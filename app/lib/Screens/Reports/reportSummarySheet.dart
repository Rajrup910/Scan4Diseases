import 'package:flutter/material.dart';
import '../theme.dart';
import '../app_data.dart';
import '../widgets/app_logo_mark.dart';

/// Shows a doctor-ready consultation summary sheet for a screening report.
///
/// Designed to be shown directly to a doctor during an in-person visit or exported.
Future<void> showReportSummarySheet(BuildContext context, ScreeningReport report) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: dark ? Themes.darkSurface : Themes.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ReportSummaryContent(report: report),
  );
}

class _ReportSummaryContent extends StatelessWidget {
  const _ReportSummaryContent({required this.report});
  final ScreeningReport report;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
    final borderColor = dark ? Themes.darkBorder : Themes.border;

    final triageLower = report.triage.toLowerCase();
    final (triageColor, triageBg, triageBorder) = triageLower.contains('urgent')
        ? (
            Themes.urgent,
            dark ? const Color(0xFF2B1315) : Themes.urgentBg,
            dark ? const Color(0xFF6B2127) : Themes.urgentBorder,
          )
        : triageLower.contains('prompt') || triageLower.contains('soon')
            ? (
                Themes.soon,
                dark ? const Color(0xFF281E09) : Themes.soonBg,
                dark ? const Color(0xFF5D430C) : Themes.soonBorder,
              )
            : (
                dark ? Themes.tealLight : Themes.routine,
                dark ? const Color(0xFF102722) : Themes.routineBg,
                dark ? const Color(0xFF1B594C) : Themes.routineBorder,
              );

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: ListView(
          controller: scrollController,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: dark ? Themes.darkBorder : Themes.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Uniform Scan4Disease brandmark — glowing electric teal emblem.
                const AppLogoMark(size: 26, glow: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Clinical Consultation Summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Evidence summary generated for in-person medical evaluation. Screened ${_formatDate(report.date)}.',
              style: TextStyle(color: inkSoft, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            // Result Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF1E2430) : Themes.glass,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: dark ? Themes.darkBorder : Colors.white.withValues(alpha: 0.85),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        report.condition,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: triageBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: triageBorder),
                        ),
                        child: Text(
                          report.triage,
                          style: TextStyle(color: triageColor, fontWeight: FontWeight.w700, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  if (report.predictedClass != null && report.predictedClass!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('Model class: ${report.predictedClass!.toUpperCase()}',
                        style: TextStyle(color: inkSoft, fontSize: 12)),
                  ],
                  if (report.confidence != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text('Model match score: ', style: TextStyle(fontSize: 13, color: inkSoft)),
                        Text('${(report.confidence! * 100).toStringAsFixed(1)}%',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Reported Symptoms Table
            if (report.symptoms.isNotEmpty) ...[
              Text(
                'Reported Patient History & Symptoms',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  children: [
                    for (final entry in report.symptoms.entries)
                      if (entry.value != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: dark ? Themes.darkBorder : Themes.borderSubtle)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  _formatSymptomKey(entry.key),
                                  style: TextStyle(fontSize: 12.5, color: inkSoft),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _formatSymptomVal(entry.value),
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ink),
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Clinical Explanation
            if (report.explanation.isNotEmpty) ...[
              Text(
                'AI Model Finding Summary',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF1E2430) : Themes.surfaceDim,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  report.explanation,
                  style: TextStyle(fontSize: 13, height: 1.4, color: ink),
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Disclaimer
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF261E10) : Themes.warningTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: dark ? const Color(0xFF5A4418) : Themes.soonBorder),
              ),
              child: Text(
                'This screening report is decision-support material only. It does not replace a clinical biopsy, dermatoscopy, or diagnosis by a registered medical practitioner.',
                style: TextStyle(fontSize: 11.5, height: 1.35, color: ink),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatSymptomKey(String k) => switch (k) {
        'duration' => 'Duration observed',
        'size_change' => 'Size change evolution',
        'sun_exposure' => 'Sun exposure',
        'recent_change' => 'Recent rapid change',
        'itching' => 'Itching sensation',
        'pain' => 'Pain / tenderness',
        'bleeding' => 'Bleeding spontaneously',
        'color_change' => 'Colour changes',
        'family_history' => 'Family history of skin cancer',
        _ => k.replaceAll('_', ' '),
      };

  String _formatSymptomVal(dynamic v) {
    if (v is bool) return v ? 'Yes' : 'No';
    return v.toString().replaceAll('_', ' ');
  }
}
