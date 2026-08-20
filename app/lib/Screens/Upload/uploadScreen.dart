import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import '../app_data.dart';
import '../../services/language_service.dart';
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
      if (image != null && mounted) setState(() => _image = image);
    }
    catch (e) { log('$e'); if (mounted) _error('Unable to select the image. Please try again.'); }
  }

  Future<void> _predict() async {
    if (_image == null) return _error('Please add a clear skin image first.');
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
      // Persist to the backend (falls back to a local-only entry if offline).
      await AppData.addReport(report);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => DiagnosisResultsUI(diagnosisData: result)));
      // Clear the form now (behind the results page) so returning to the Screen
      // tab shows a fresh questionnaire instead of the answers just submitted.
      _resetForm();
    } catch (e) {
      log('Prediction error: $e');
      if (mounted) {
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

  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 30), children: [
    Row(children: [
      const Expanded(child: Text('New screening', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
      if (!_loading && (_image != null || _questionnaire.values.any((v) => v != null)))
        TextButton.icon(onPressed: _resetForm, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Clear')),
    ]),
    const SizedBox(height: 5),
    const Text('Use a clear, well-lit photo of the skin area you want to screen.', style: TextStyle(color: Themes.muted)),
    const SizedBox(height: 18),
    _imageCard(),
    const SizedBox(height: 14),
    Row(children: [Expanded(child: _button(Icons.camera_alt_rounded, 'Camera', () => _pick(ImageSource.camera))), const SizedBox(width: 10), Expanded(child: _button(Icons.photo_library_outlined, 'Gallery', () => _pick(ImageSource.gallery)))]),
    const SizedBox(height: 22),
    Card(child: Padding(padding: const EdgeInsets.all(17), child: SymptomsList(key: _symptomsKey, onSymptomsUpdated: (v) => setState(() => _questionnaire = v)))),
    const SizedBox(height: 16),
    SizedBox(height: 54, child: FilledButton.icon(onPressed: _loading ? null : _predict, icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.auto_awesome_rounded), label: Text(_loading ? 'Analyzing image…' : 'Analyze image'))),
    const SizedBox(height: 10),
    const Text('AI-assisted screening only — not a medical diagnosis.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Themes.muted)),
  ]);

  Widget _imageCard() => Container(height: 260, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: Themes.border)), clipBehavior: Clip.antiAlias, child: _image == null ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Themes.primary.withOpacity(.1), shape: BoxShape.circle), child: const Icon(Icons.add_a_photo_rounded, size: 38, color: Themes.primary)), const SizedBox(height: 12), const Text('Add a skin photo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 4), const Text('Camera or gallery', style: TextStyle(color: Themes.muted))]) : FutureBuilder(future: _image!.readAsBytes(), builder: (_, s) => s.hasData ? Stack(fit: StackFit.expand, children: [Image.memory(s.data!, fit: BoxFit.cover), Positioned(top: 12, right: 12, child: IconButton.filled(onPressed: () => setState(() => _image = null), icon: const Icon(Icons.close)))]) : const Center(child: CircularProgressIndicator())));
  Widget _button(IconData icon, String text, VoidCallback onTap) => OutlinedButton.icon(onPressed: _loading ? null : onTap, icon: Icon(icon), label: Text(text), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)));
}
