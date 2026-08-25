import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/language_service.dart';
import '../../services/motion_service.dart';
import '../../services/theme_service.dart';
import '../theme.dart';
import '../app_data.dart';

class YouScreen extends StatelessWidget {
  const YouScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = ThemeService.instance.isDark(context);
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
    final accent = dark ? Themes.tealLight : Themes.brand;

    return ValueListenableBuilder<AuthUser?>(
      valueListenable: AuthService.instance.user,
      builder: (_, user, __) => ValueListenableBuilder<List<ScreeningReport>>(
        valueListenable: AppData.reports,
        builder: (_, reports, __) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: Themes.liquidGlassDecoration(radius: 20, dark: dark),
              child: Row(children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: (dark ? Themes.darkBrandTint : Themes.brandTint).withValues(alpha: dark ? 0.9 : 0.70),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: dark ? Themes.tealGlow.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.85),
                      width: 1.2,
                    ),
                  ),
                  child: Icon(Icons.person_rounded, color: accent, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName?.isNotEmpty == true ? user!.displayName! : 'Patient Profile',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user?.email ?? 'Not signed in',
                        style: TextStyle(color: inkSoft, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            _section(context, 'Screening activity', dark, [
              _row(Icons.assignment_outlined, 'Total screenings', '${reports.length}', dark),
              const Divider(),
              _row(Icons.calendar_today_outlined, 'Latest screening',
                  reports.isEmpty ? 'None yet' : _date(reports.first.date), dark),
            ]),
            const SizedBox(height: 16),
            _section(context, 'App preferences', dark, [
              _themeRow(context, dark),
              const Divider(),
              _motionRow(context, dark),
              const Divider(),
              _languageRow(context, dark),
              const Divider(),
              _row(Icons.notifications_none_rounded, 'Monthly reminder', 'Active', dark),
              const Divider(),
              _row(Icons.privacy_tip_outlined, 'Privacy & consent', 'Managed per report', dark),
            ]),
            const SizedBox(height: 24),
            Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: OutlinedButton.icon(
                onPressed: () => _confirmLogout(context),
                icon: const Icon(Icons.logout_rounded, color: Themes.danger, size: 18),
                label: const Text('Sign out',
                    style: TextStyle(color: Themes.danger, fontWeight: FontWeight.w700, fontSize: 14)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.45), width: 1.2),
                  backgroundColor: dark
                      ? const Color(0xFF3A1B1B).withValues(alpha: 0.55)
                      : const Color(0xFFFEF2F2).withValues(alpha: 0.85),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in anytime. Your saved reports stay in your account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Themes.danger),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true) await AuthService.instance.logout();
  }

  /// Dark / light appearance toggle. Moon/sun icon plus an adaptive switch that
  /// flips [ThemeService] between explicit light and dark; the whole app rebuilds
  /// through the root [ValueListenableBuilder] in `main.dart`.
  Widget _themeRow(BuildContext context, bool dark) => ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeService.instance.mode,
        builder: (_, __, ___) {
          final isDark = ThemeService.instance.isDark(context);
          final accent = isDark ? Themes.tealLight : Themes.brand;
          return ListTile(
            leading: Icon(
              isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              color: accent,
              size: 20,
            ),
            title: Text('Dark mode',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? Themes.darkInk : Themes.ink)),
            subtitle: Text(isDark ? 'Glossy emerald theme' : 'Bright clinical theme',
                style: TextStyle(fontSize: 12, color: isDark ? Themes.darkInkSoft : Themes.inkSoft)),
            trailing: Switch.adaptive(
              value: isDark,
              activeThumbColor: Themes.tealGlow,
              onChanged: (_) => ThemeService.instance.toggle(context),
            ),
            onTap: () => ThemeService.instance.toggle(context),
          );
        },
      );

  /// Ambient-motion toggle. Sits directly beneath the theme switch because the
  /// two are the same kind of choice: how the app presents itself. Freezes the
  /// decorative wave surfaces without touching purposeful motion (page
  /// transitions, the success tick), so feedback is never lost.
  Widget _motionRow(BuildContext context, bool dark) => ValueListenableBuilder<bool>(
        valueListenable: MotionService.instance.reduced,
        builder: (_, reduced, __) {
          final ink = dark ? Themes.darkInk : Themes.ink;
          final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
          final accent = dark ? Themes.tealLight : Themes.brand;
          // Reflect the platform setting so the row never claims motion is on
          // while the OS is suppressing it.
          final forcedByOs = MediaQuery.maybeDisableAnimationsOf(context) == true;
          return ListTile(
            leading: Icon(
              reduced || forcedByOs ? Icons.motion_photos_off_rounded : Icons.waves_rounded,
              color: accent,
              size: 20,
            ),
            title: Text('Reduce ambient motion',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink)),
            subtitle: Text(
              forcedByOs
                  ? 'On — following your device accessibility setting'
                  : reduced
                      ? 'Decorative surfaces hold still'
                      : 'Living emerald wave surfaces',
              style: TextStyle(fontSize: 12, color: inkSoft),
            ),
            trailing: Switch.adaptive(
              value: reduced || forcedByOs,
              activeThumbColor: Themes.tealGlow,
              // The OS setting wins; don't let the switch imply otherwise.
              onChanged: forcedByOs ? null : (v) => MotionService.instance.set(v),
            ),
            onTap: forcedByOs ? null : () => MotionService.instance.toggle(),
          );
        },
      );

  Widget _languageRow(BuildContext context, bool dark) {
    final ink = dark ? Themes.darkInk : Themes.ink;
    final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
    final accent = dark ? Themes.tealLight : Themes.brand;
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.instance.code,
      builder: (_, __, ___) => ListTile(
        leading: Icon(Icons.language_outlined, color: accent, size: 20),
        title: Text('Explanation language',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ink)),
        subtitle: Text('Language of the AI clinical explanation',
            style: TextStyle(fontSize: 12, color: inkSoft)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(LanguageService.instance.label,
              style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: dark ? Themes.darkInkSoft : Themes.inkMuted, size: 18),
        ]),
        onTap: () => _pickLanguage(context),
      ),
    );
  }

  Future<void> _pickLanguage(BuildContext context) async {
    final current = LanguageService.instance.code.value;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Explanation language',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          ),
          for (final e in LanguageService.supported.entries)
            ListTile(
              title: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: e.key == current ? const Icon(Icons.check_rounded, color: Themes.brand) : null,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (chosen != null) await LanguageService.instance.set(chosen);
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _section(BuildContext context, String title, bool dark, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Frosted rounded pill header — soft, visible, and smooth over the
          // dynamic video background instead of a hard-edged bare label.
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Themes.sectionHeaderPill(title, dark: dark),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: dark ? Themes.tealGlow.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.85),
                width: 1.2,
              ),
            ),
            child: Column(children: children),
          ),
        ],
      );

  Widget _row(IconData icon, String title, String value, bool dark) => ListTile(
        leading: Icon(icon, color: dark ? Themes.tealLight : Themes.brand, size: 20),
        title: Text(title,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: dark ? Themes.darkInk : Themes.ink)),
        trailing: Text(value,
            style: TextStyle(
                color: dark ? Themes.darkInkSoft : Themes.inkSoft, fontWeight: FontWeight.w600, fontSize: 13)),
      );
}
