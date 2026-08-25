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
  final dark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: dark ? Themes.darkSurface : Colors.white,
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

  Future<void> _submit(List<DoctorDirectoryEntry> doctors) async {
    final doctorId = _selectedId;
    if (doctorId == null) return;

    final selectedDoctor = doctors.firstWhere(
      (d) => d.id == doctorId,
      orElse: () => DoctorDirectoryEntry(id: doctorId, email: 'Doctor'),
    );

    setState(() => _submitting = true);
    try {
      var report = widget.report;
      var reportId = report.id;
      // If report has no server ID yet, persist it to the server first
      if (reportId == null) {
        final saved = await AppData.addReport(report);
        reportId = saved.id;
      }
      if (reportId == null) {
        throw SharingException('Unable to resolve report ID on server. Please check your connection.');
      }

      await SharingService.instance.shareReportWithDoctor(
        doctorId: doctorId,
        reportId: reportId,
        imagePath: report.imagePath,
        gradcamUrl: widget.gradcamUrl,
      );
      if (!mounted) return;
      Navigator.pop(context);
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => ShareSuccessDialog(
          doctorName: selectedDoctor.label,
          condition: widget.report.condition,
          hasGradcam: (widget.gradcamUrl ?? '').isNotEmpty || report.imagePath != null,
        ),
      );
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.82;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: Padding(
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
                  color: dark ? Themes.darkBorder : Themes.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Share with a doctor',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: dark ? Themes.darkInk : Themes.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose a doctor to review your "${widget.report.condition}" screening. '
              'They will be able to see this report and its image in their portal.',
              style: TextStyle(
                color: dark ? Themes.darkInkSoft : Themes.muted,
                height: 1.35,
                fontSize: 13,
              ),
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
                      dark,
                    );
                  }
                  final doctors = snap.data ?? const [];
                  if (doctors.isEmpty) {
                    return _errorBox('No verified doctors are available yet.', dark);
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: doctors.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _doctorTile(doctors[i], dark),
                  );
                },
              ),
            ),

          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: FutureBuilder<List<DoctorDirectoryEntry>>(
              future: _doctors,
              builder: (context, snap) {
                final doctors = snap.data ?? const [];
                return FilledButton.icon(
                  onPressed: (_selectedId == null || _submitting || doctors.isEmpty)
                      ? null
                      : () => _submit(doctors),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(_submitting ? 'Sharing…' : 'Share this screening'),
                );
              },
            ),
          ),
            const SizedBox(height: 8),
            Text(
              'Your photo is encrypted before it is stored, and only the doctor you choose can '
              'see it. You can stop sharing at any time.',
              style: TextStyle(
                color: dark ? Themes.darkInkSoft : Themes.muted,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _doctorTile(DoctorDirectoryEntry d, bool dark) {
    final selected = d.id == _selectedId;
    final accent = dark ? Themes.tealGlow : Themes.primary;
    final tileBg = dark
        ? (selected ? Themes.tealGlow.withValues(alpha: 0.12) : const Color(0xFF1E2430))
        : (selected ? Themes.primary.withValues(alpha: 0.06) : Colors.white);
    final borderColor = selected
        ? accent
        : (dark ? Themes.darkBorder : Themes.border);

    return InkWell(
      onTap: _submitting ? null : () => setState(() => _selectedId = d.id),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tileBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: dark ? 0.20 : 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.medical_services_outlined, color: dark ? Themes.tealLight : Themes.primary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                d.label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: dark ? Themes.darkInk : Themes.ink,
                ),
              ),
              if (d.regNo != null && d.regNo!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Reg. ${d.regNo}',
                  style: TextStyle(
                    color: dark ? Themes.darkInkSoft : Themes.muted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ]),
          ),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? accent : (dark ? Themes.darkInkSoft : Themes.muted),
          ),
        ]),
      ),
    );
  }

  Widget _errorBox(String message, bool dark) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Themes.danger.withValues(alpha: dark ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Themes.danger.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: dark ? Themes.darkInk : Themes.ink, height: 1.35)),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ]),
      );
}

/// Rich animated success dialog presented to the patient when clinical report sharing succeeds.
class ShareSuccessDialog extends StatefulWidget {
  const ShareSuccessDialog({
    super.key,
    required this.doctorName,
    required this.condition,
    required this.hasGradcam,
  });

  final String doctorName;
  final String condition;
  final bool hasGradcam;

  @override
  State<ShareSuccessDialog> createState() => _ShareSuccessDialogState();
}

class _ShareSuccessDialogState extends State<ShareSuccessDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _discScale;
  late final Animation<double> _haloOpacity;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );

    _discScale = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
      ),
    );

    _haloOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.10, 0.70, curve: Curves.easeOut),
      ),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
    final primaryAccent = dark ? Themes.tealLight : Themes.primary;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(
          color: dark ? Themes.tealGlow.withValues(alpha: 0.22) : Colors.transparent,
          width: 1.1,
        ),
      ),
      backgroundColor: dark ? Themes.darkSurface : Colors.white,
      elevation: 16,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Static jade check disc with a single soft brand halo.
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Static brand-tint halo — fades up once, no expansion.
                    Opacity(
                      opacity: 0.55 * _haloOpacity.value,
                      child: Container(
                        width: 108,
                        height: 108,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              (dark ? Themes.tealGlow : Themes.primary).withValues(alpha: 0.18),
                              (dark ? Themes.tealGlow : Themes.primary).withValues(alpha: 0.0),
                            ],
                            stops: const [0.35, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // Emerald core disc with a restrained ambient shadow.
                    ScaleTransition(
                      scale: _discScale,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF106E5A), Color(0xFF0B4639)],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.30),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Themes.primary.withValues(alpha: 0.22),
                              blurRadius: 10,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 44,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Headline
            Text(
              'Report Shared Successfully!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),

            // Doctor acknowledgment text
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(fontSize: 14, color: inkSoft, height: 1.4),
                children: [
                  const TextSpan(text: 'Your screening for '),
                  TextSpan(
                    text: widget.condition,
                    style: TextStyle(fontWeight: FontWeight.w700, color: ink),
                  ),
                  const TextSpan(text: ' has been delivered to '),
                  TextSpan(
                    text: widget.doctorName,
                    style: TextStyle(fontWeight: FontWeight.w700, color: primaryAccent),
                  ),
                  const TextSpan(text: ' for clinical evaluation.'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Deliverables Check Card
            FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: dark ? Themes.darkBrandTint.withValues(alpha: 0.6) : Themes.brandTint.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: dark ? Themes.darkBorder : Themes.border),
                ),
                child: Column(
                  children: [
                    _deliverableRow(
                      icon: Icons.lock_outline_rounded,
                      text: 'Lesion Photograph (AES-Encrypted)',
                      dark: dark,
                    ),
                    const SizedBox(height: 10),
                    _deliverableRow(
                      icon: Icons.layers_outlined,
                      text: widget.hasGradcam
                          ? 'Grad-CAM Attention Heatmap Attached'
                          : 'Clinical AI Assessment Linked',
                      dark: dark,
                    ),
                    const SizedBox(height: 10),
                    _deliverableRow(
                      icon: Icons.verified_user_outlined,
                      text: 'Available Live in Clinician Portal',
                      dark: dark,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: dark ? Themes.tealGlow : Themes.primary,
                  foregroundColor: dark ? const Color(0xFF06231E) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deliverableRow({required IconData icon, required String text, required bool dark}) {
    final iconAccent = dark ? Themes.tealGlow : Themes.mint;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: iconAccent.withValues(alpha: dark ? 0.22 : 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_circle_rounded, color: iconAccent, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: dark ? Themes.darkInk : Themes.ink,
            ),
          ),
        ),
      ],
    );
  }
}
