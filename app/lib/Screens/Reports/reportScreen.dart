import 'package:flutter/material.dart';
import '../theme.dart';
import '../app_data.dart';
import '../Upload/ResultData.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<List<ScreeningReport>>(
        valueListenable: AppData.reports,
        builder: (_, reports, __) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              const Expanded(
                child: Text('My screenings',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              if (reports.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _confirmClearAll(context, reports.length),
                  style: TextButton.styleFrom(foregroundColor: Themes.danger),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Clear all'),
                ),
            ]),
            const SizedBox(height: 2),
            Text('${reports.length} saved report${reports.length == 1 ? '' : 's'}',
                style: const TextStyle(color: Themes.muted)),
            const SizedBox(height: 18),
            if (reports.isEmpty)
              _empty()
            else ...[
              const Text('Swipe a card left to delete, or use the delete button.',
                  style: TextStyle(color: Themes.muted, fontSize: 12.5)),
              const SizedBox(height: 12),
              ...reports.map((r) => _reportCard(context, r)),
            ],
          ],
        ),
      );

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
    // Copy first: deleting mutates the underlying list as we go.
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
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Themes.border),
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: Themes.primary.withValues(alpha: .1), shape: BoxShape.circle),
            child: const Icon(Icons.assignment_outlined, size: 42, color: Themes.primary),
          ),
          const SizedBox(height: 14),
          const Text('No screenings yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Your completed screening reports will appear here.',
              textAlign: TextAlign.center, style: TextStyle(color: Themes.muted)),
        ]),
      );

  Widget _reportCard(BuildContext context, ScreeningReport r) => Dismissible(
        key: ObjectKey(r),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _confirmDelete(context, r),
        background: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.only(right: 22),
          alignment: Alignment.centerRight,
          decoration: BoxDecoration(
            color: Themes.danger,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white),
            SizedBox(width: 6),
            Text('Delete',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ]),
        ),
        child: Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DiagnosisResultsUI(diagnosisData: {
                  'predicted_class': r.condition,
                  'confidence': r.confidence,
                  'triage': r.triage,
                  'explanation': r.explanation,
                }),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(17, 15, 8, 15),
              child: Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Themes.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.health_and_safety_outlined, color: Themes.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.condition,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 5),
                    Text(_date(r.date), style: const TextStyle(color: Themes.muted)),
                    const SizedBox(height: 6),
                    Text(r.triage,
                        style: const TextStyle(
                            color: Themes.primary, fontWeight: FontWeight.w600)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(context, r),
                  icon: const Icon(Icons.delete_outline_rounded, color: Themes.muted),
                ),
              ]),
            ),
          ),
        ),
      );

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_month(d.month)} ${d.year}';
  String _month(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}
