import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import '../app_data.dart';
import '../../services/haptics_service.dart';
import '../../services/language_service.dart';
import '../../services/sound_service.dart';
import 'DiagnoseAPI.dart';
import 'ResultData.dart';
import 'widgets/SymptomsList.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key, this.camera});
  final dynamic camera;
  @override State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _picker = ImagePicker();
  final _api = DiagnosisApi();
  XFile? _image;
  Map<String, dynamic> _questionnaire = {};
  bool _loading = false;

  // Remounting SymptomsList with a fresh key is the only way to clear its
  // internal dropdown selections, since it owns that state. Changing the key
  // discards the old State and rebuilds the questionnaire blank.
  Key _symptomsKey = UniqueKey();

  /// Return the screen to a clean "new screening" state: no image, no answers,
  /// and a freshly-mounted questionnaire. Called after a screening completes so
  /// the next one does not inherit the previous photo or symptoms.
  void _resetForm() {
    if (!mounted) return;
    setState(() {
      _image = null;
      _questionnaire = {};
      _symptomsKey = UniqueKey();
    });
  }

  /// Longest edge sent to the backend. A modern phone camera produces ~3072x4096,
  /// which re-encodes to well over the server's 10 MB upload limit and was rejected as
  /// `file_too_large`. The model runs at 224x224, so full sensor resolution buys nothing
  /// — 1600px keeps plenty of detail for the Grad-CAM overlay while landing far under
  /// the limit and uploading in a fraction of the time.
  static const double _maxUploadEdge = 1600;

  Future<void> _pick(ImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: _maxUploadEdge,
        maxHeight: _maxUploadEdge,
        imageQuality: 90,
      );
      if (image != null && mounted) {
        Haptics.instance.selection(); // a picked image landed in the card
        setState(() => _image = image);
      }
    }
    catch (e) { log('$e'); if (mounted) _error('Unable to select the image. Please try again.'); }
  }

  Future<void> _predict() async {
    if (_image == null) {
      Haptics.instance.warning(); // nudge: nothing to analyse yet
      return _error('Please add a clear skin image first.');
    }
    Haptics.instance.medium(); // firm confirm that the analysis has started
    setState(() => _loading = true);
    try {
      final result = await _api.predict(
        image: _image!,
        questionnaire: _questionnaire,
        language: LanguageService.instance.code.value,
      );
      if (!mounted) return;
      final triage = result['triage'];
      final triageLabel = (triage is Map ? triage['label']?.toString() : triage?.toString()) ??
          'Professional review recommended';
      final report = ScreeningReport(
        date: DateTime.now(),
        condition: result['predicted_name']?.toString() ??
            result['predicted_class']?.toString() ??
            'Screening result',
        predictedClass: result['predicted_class']?.toString(),
        confidence: result['confidence'] is num
            ? (result['confidence'] as num).toDouble()
            : double.tryParse('${result['confidence']}'),
        triage: triageLabel,
        explanation: result['explanation']?.toString() ?? 'No explanation returned.',
        imagePath: _image!.path,
        symptoms: _questionnaire,
      );
      // Persist to the backend (falls back to a local-only entry if offline). The saved
      // copy carries the server id needed to share this screening with a doctor.
      final saved = await AppData.addReport(report);
      if (!mounted) return;
      SoundService.instance.success();
      Navigator.push(context, MaterialPageRoute(builder: (_) => DiagnosisResultsUI(diagnosisData: result, report: saved)));
      // Clear the form now (behind the results page) so returning to the Screen
      // tab shows a fresh questionnaire instead of the answers just submitted.
      _resetForm();
    } catch (e) {
      log('Prediction error: $e');
      if (mounted) {
        SoundService.instance.error();
        final msg = e is ApiException
            ? e.message
            : 'Could not reach the screening service. Check that the backend is '
                'running and that the device can reach it (run "adb reverse '
                'tcp:8000 tcp:8000" for a USB-connected phone).';
        _error(msg);
      }
    }
    finally { if (mounted) setState(() => _loading = false); }
  }

  void _error(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Themes.darkInk : Themes.ink;
    final onMedia = dark ? Themes.onMediaDark : Themes.onMedia;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Row(children: [
          Expanded(
            child: Text(
              'New screening',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: ink,
                letterSpacing: -0.01,
                shadows: onMedia,
              ),
            ),
          ),
          if (!_loading && (_image != null || _questionnaire.values.any((v) => v != null)))
            TextButton.icon(
              onPressed: _resetForm,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reset'),
            ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Upload a clear, well-lit photo of the skin lesion or area you want to screen.',
          style: TextStyle(
            color: ink,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            shadows: onMedia,
          ),
        ),
        const SizedBox(height: 16),
        _imageCard(dark),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _button(Icons.camera_alt_rounded, 'Take photo', () => _pick(ImageSource.camera), dark)),
          const SizedBox(width: 10),
          Expanded(child: _button(Icons.photo_library_outlined, 'From gallery', () => _pick(ImageSource.gallery), dark)),
        ]),
        const SizedBox(height: 20),
        Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: dark ? Themes.tealGlow.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.85),
              width: 1.2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.checklist_rounded, color: dark ? Themes.tealLight : Themes.brand, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Clinical symptoms questionnaire',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ink),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SymptomsList(
                  key: _symptomsKey,
                  onSymptomsUpdated: (v) => setState(() => _questionnaire = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _loading ? null : _predict,
            icon: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.analytics_outlined, size: 20),
            label: Text(_loading ? 'Analyzing with AI model…' : 'Run screening analysis',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'AI-assisted screening tool — not a medical diagnosis.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink, shadows: onMedia),
        ),
      ],
    );
  }

  Widget _imageCard(bool dark) => Container(
        height: 250,
        decoration: Themes.liquidGlassDecoration(radius: 20, dark: dark),
        clipBehavior: Clip.antiAlias,
        child: _image == null
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: (dark ? Themes.tealGlow : Themes.brand).withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: dark ? Themes.tealGlow.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.85),
                      width: 1.2,
                    ),
                  ),
                  child: Icon(Icons.add_a_photo_rounded, size: 34, color: dark ? Themes.tealLight : Themes.brand),
                ),
                const SizedBox(height: 12),
                Text(
                  'Add a lesion photo',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: dark ? Themes.darkInk : Themes.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Take a photo or choose from gallery',
                  style: TextStyle(color: dark ? Themes.darkInkSoft : Themes.inkSoft, fontSize: 12.5),
                ),
              ])
            : FutureBuilder(
                future: _image!.readAsBytes(),
                builder: (_, s) => s.hasData
                    ? Stack(fit: StackFit.expand, children: [
                        Image.memory(s.data!, fit: BoxFit.cover),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: IconButton.filled(
                            style: IconButton.styleFrom(backgroundColor: Colors.black54),
                            onPressed: () => setState(() => _image = null),
                            icon: const Icon(Icons.close, color: Colors.white, size: 18),
                          ),
                        ),
                      ])
                    : const Center(child: CircularProgressIndicator()),
              ),
      );

  Widget _button(IconData icon, String text, VoidCallback onTap, bool dark) => OutlinedButton.icon(
        onPressed: _loading ? null : onTap,
        icon: Icon(icon, size: 18, color: dark ? Themes.tealLight : Themes.brand),
        label: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13),
          backgroundColor: dark ? const Color(0xFF1E2430) : Themes.glass,
          side: BorderSide(
            color: dark ? Themes.darkBorder : Colors.white.withValues(alpha: 0.85),
            width: 1.2,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
}

