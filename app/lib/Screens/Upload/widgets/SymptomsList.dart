import 'package:flutter/material.dart';

/// Structured symptom questionnaire.
///
/// Every value emitted here MUST match the backend `Questionnaire` schema, which
/// uses typed enums and `extra="forbid"`. Mismatched enum values or types cause
/// HTTP 422. The valid values are:
///
///   duration     : less_than_1_month | 1_to_3_months | 3_to_12_months
///                  | more_than_1_year | unknown
///   size_change  : growing | stable | shrinking | unknown
///   sun_exposure : low | moderate | high | unknown        (string)
///   recent_change, itching, pain, bleeding, color_change, family_history : bool
///
/// Unanswered fields are left null and dropped before sending.
class SymptomsList extends StatefulWidget {
  const SymptomsList({super.key, required this.onSymptomsUpdated});
  final ValueChanged<Map<String, dynamic>> onSymptomsUpdated;

  @override
  State<SymptomsList> createState() => _SymptomsListState();
}

class _SymptomsListState extends State<SymptomsList> {
  String? duration;
  String? sizeChange;
  String? sunExposure;
  bool? recentChange, itching, pain, bleeding, colorChange, familyHistory;

  void _emit() => widget.onSymptomsUpdated({
        'duration': duration,
        'recent_change': recentChange,
        'itching': itching,
        'pain': pain,
        'bleeding': bleeding,
        'size_change': sizeChange,
        'color_change': colorChange,
        'family_history': familyHistory,
        'sun_exposure': sunExposure,
      });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Skin / Lesion Details',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Answer what you know. Anything left blank is treated as “not reported”.'),
          const SizedBox(height: 14),
          _dropdown<String>(
            label: 'How long have you noticed it?',
            value: duration,
            items: const {
              'less_than_1_month': 'Less than a month',
              '1_to_3_months': '1–3 months',
              '3_to_12_months': '3–12 months',
              'more_than_1_year': 'More than a year',
              'unknown': 'Not sure',
            },
            onChanged: (v) => setState(() { duration = v; _emit(); }),
          ),
          const SizedBox(height: 12),
          _dropdown<String>(
            label: 'Has its size changed?',
            value: sizeChange,
            items: const {
              'growing': 'Growing',
              'stable': 'Staying the same',
              'shrinking': 'Shrinking',
              'unknown': 'Not sure',
            },
            onChanged: (v) => setState(() { sizeChange = v; _emit(); }),
          ),
          const SizedBox(height: 12),
          _dropdown<String>(
            label: 'How much sun exposure has this area had?',
            value: sunExposure,
            items: const {
              'low': 'Low',
              'moderate': 'Moderate',
              'high': 'High',
              'unknown': 'Not sure',
            },
            onChanged: (v) => setState(() { sunExposure = v; _emit(); }),
          ),
          const SizedBox(height: 6),
          _yesNo('Has it changed recently?', recentChange, (v) => setState(() { recentChange = v; _emit(); })),
          _yesNo('Is it itchy?', itching, (v) => setState(() { itching = v; _emit(); })),
          _yesNo('Is it painful?', pain, (v) => setState(() { pain = v; _emit(); })),
          _yesNo('Has it bled on its own?', bleeding, (v) => setState(() { bleeding = v; _emit(); })),
          _yesNo('Has its colour changed?', colorChange, (v) => setState(() { colorChange = v; _emit(); })),
          _yesNo('Family history of skin cancer?', familyHistory, (v) => setState(() { familyHistory = v; _emit(); })),
        ],
      );

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) =>
      DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [
          for (final e in items.entries)
            DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
        ],
        onChanged: onChanged,
      );

  Widget _yesNo(String label, bool? value, ValueChanged<bool?> onChanged) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            Expanded(child: Text(label)),
            DropdownButton<bool?>(
              value: value,
              hint: const Text('Select'),
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem<bool?>(value: true, child: Text('Yes')),
                DropdownMenuItem<bool?>(value: false, child: Text('No')),
              ],
              onChanged: onChanged,
            ),
          ]),
        ),
      );
}
