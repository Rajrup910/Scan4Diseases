import 'package:flutter/material.dart';
import '../../theme.dart';

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
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Answer what you know. Anything left blank is treated as "not reported".',
          style: TextStyle(color: inkSoft, fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 14),
        _dropdown<String>(
          label: 'How long have you noticed it?',
          value: duration,
          icon: Icons.access_time_rounded,
          dark: dark,
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
          icon: Icons.straighten_rounded,
          dark: dark,
          items: const {
            'growing': 'Growing (larger)',
            'stable': 'Staying the same',
            'shrinking': 'Shrinking (smaller)',
            'unknown': 'Not sure',
          },
          onChanged: (v) => setState(() { sizeChange = v; _emit(); }),
        ),
        const SizedBox(height: 12),
        _dropdown<String>(
          label: 'Sun exposure history on this area',
          value: sunExposure,
          icon: Icons.wb_sunny_outlined,
          dark: dark,
          items: const {
            'low': 'Low / mostly covered',
            'moderate': 'Moderate / occasional',
            'high': 'High / frequent or sunburns',
            'unknown': 'Not sure',
          },
          onChanged: (v) => setState(() { sunExposure = v; _emit(); }),
        ),
        const SizedBox(height: 16),
        Text(
          'Specific symptoms & history',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ink),
        ),
        const SizedBox(height: 8),
        _toggle('Recent rapid change?', recentChange, (v) => setState(() { recentChange = v; _emit(); }), dark),
        _toggle('Is it itchy?', itching, (v) => setState(() { itching = v; _emit(); }), dark),
        _toggle('Is it painful or tender?', pain, (v) => setState(() { pain = v; _emit(); }), dark),
        _toggle('Has it bled spontaneously?', bleeding, (v) => setState(() { bleeding = v; _emit(); }), dark),
        _toggle('Has its colour changed?', colorChange, (v) => setState(() { colorChange = v; _emit(); }), dark),
        _toggle('Family history of skin cancer?', familyHistory, (v) => setState(() { familyHistory = v; _emit(); }), dark),
      ],
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required IconData icon,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
    required bool dark,
  }) {
    final accent = dark ? Themes.tealLight : Themes.brand;
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
    final menuBg = dark ? const Color(0xF8161922) : const Color(0xF8FFFFFF);

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: dark ? const Color(0x661E2430) : Colors.white.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dark ? Themes.tealGlow.withValues(alpha: 0.20) : Colors.white.withValues(alpha: 0.85),
          width: 1.2,
        ),
      ),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        dropdownColor: menuBg,
        borderRadius: BorderRadius.circular(16),
        elevation: 12,
        icon: Icon(Icons.keyboard_arrow_down_rounded, color: accent, size: 22),
        style: TextStyle(fontSize: 13.5, color: ink, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 13, color: inkSoft, fontWeight: FontWeight.w500),
          floatingLabelStyle: TextStyle(fontSize: 14, color: accent, fontWeight: FontWeight.w700),
          prefixIcon: Icon(icon, color: accent, size: 20),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        items: [
          for (final e in items.entries)
            DropdownMenuItem<T>(
              value: e.key,
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: e.key == value ? accent : inkSoft.withValues(alpha: 0.35),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: e.key == value ? FontWeight.w700 : FontWeight.w500,
                        color: e.key == value ? accent : ink,
                      ),
                    ),
                  ),
                  if (e.key == value)
                    Icon(Icons.check_rounded, color: accent, size: 16),
                ],
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _toggle(String label, bool? value, ValueChanged<bool?> onChanged, bool dark) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1E2430) : Themes.canvas,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: dark ? Themes.darkBorder : Themes.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: dark ? Themes.darkInk : Themes.ink,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _pill('No', value == false, () => onChanged(value == false ? null : false), dark),
                const SizedBox(width: 6),
                _pill('Yes', value == true, () => onChanged(value == true ? null : true), dark),
              ],
            ),
          ],
        ),
      );

  Widget _pill(String label, bool active, VoidCallback onTap, bool dark) {
    final yesActiveBg = dark ? Themes.tealGlow : Themes.brand;
    final noActiveBg = dark ? Themes.darkInkSoft : Themes.inkSoft;
    final activeBg = label == 'Yes' ? yesActiveBg : noActiveBg;
    final activeTextColor = dark && label == 'Yes' ? const Color(0xFF06231E) : Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? activeBg : (dark ? const Color(0xFF161920) : Colors.white),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? Colors.transparent : (dark ? Themes.darkBorder : Themes.border),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? activeTextColor : (dark ? Themes.darkInkSoft : Themes.inkSoft),
          ),
        ),
      ),
    );
  }
}

