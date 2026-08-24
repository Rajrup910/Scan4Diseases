import 'package:flutter/material.dart';

import '../../services/sharing_service.dart';
import '../app_data.dart';
import '../theme.dart';

/// Open the "share this screening with a doctor" flow as a modal sheet.
///
/// The report must already be saved on the server (so it has an [ScreeningReport.id]) and
/// still have its device-local image ([ScreeningReport.imagePath]). The sheet lists the
/// verified doctors, lets the patient pick one, and on confirm grants that doctor access and
/// uploads the encrypted image — after which the report appears in that doctor's web portal.
Future<void> showShareWithDoctorSheet(
  BuildContext context,
  ScreeningReport report, {
  String? gradcamUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ShareSheet(report: report, gradcamUrl: gradcamUrl),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.report, this.gradcamUrl});
  final ScreeningReport report;

  /// Absolute URL of this screening's Grad-CAM overlay (temporary). Shared alongside the
  /// photo when present so the doctor sees the heatmap too.
  final String? gradcamUrl;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late Future<List<DoctorDirectoryEntry>> _doctors;
  int? _selectedId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _doctors = SharingService.instance.listDoctors();
  }

  void _retry() =>
      setState(() => _doctors = SharingService.instance.listDoctors());

  Future<void> _submit() async {
    final doctorId = _selectedId;
    final imagePath = widget.report.imagePath;
    final reportId = widget.report.id;
    if (doctorId == null || imagePath == null || reportId == null) return;

    setState(() => _submitting = true);
    try {
      await SharingService.instance.shareReportWithDoctor(
        doctorId: doctorId,
        reportId: reportId,
        imagePath: imagePath,
        gradcamUrl: widget.gradcamUrl,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Themes.mint,
        content: Text('Shared. Your doctor can now review this screening.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Themes.danger,
        content: Text(e is SharingException ? e.message : 'Could not share. Please try again.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Themes.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Share with a doctor',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Choose a doctor to review your "${widget.report.condition}" screening. '
            'They will be able to see this report and its image in their portal.',
            style: const TextStyle(color: Themes.muted, height: 1.35, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: FutureBuilder<List<DoctorDirectoryEntry>>(
              future: _doctors,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return _errorBox(
                    snap.error is SharingException
                        ? (snap.error as SharingException).message
                        : 'Could not load the list of doctors.',
                  );
                }
                final doctors = snap.data ?? const [];
                if (doctors.isEmpty) {
                  return _errorBox('No verified doctors are available yet.');
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: doctors.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _doctorTile(doctors[i]),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_selectedId == null || _submitting) ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_submitting ? 'Sharing…' : 'Share this screening'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your photo is encrypted before it is stored, and only the doctor you choose can '
            'see it. You can stop sharing at any time.',
            style: TextStyle(color: Themes.muted, fontSize: 11.5, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _doctorTile(DoctorDirectoryEntry d) {
    final selected = d.id == _selectedId;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _submitting ? null : () => setState(() => _selectedId = d.id),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? Themes.primary.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Themes.primary : Themes.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Themes.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.medical_services_outlined, color: Themes.primary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.label,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              if (d.regNo != null && d.regNo!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Reg. ${d.regNo}',
                    style: const TextStyle(color: Themes.muted, fontSize: 12.5)),
              ],
            ]),
          ),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? Themes.primary : Themes.muted,
          ),
        ]),
      ),
    );
  }

  Widget _errorBox(String message) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Themes.danger.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Themes.danger.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Themes.ink, height: 1.35)),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ]),
      );
}
