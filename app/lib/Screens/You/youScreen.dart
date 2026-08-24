import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/language_service.dart';
import '../theme.dart';
import '../app_data.dart';

class YouScreen extends StatelessWidget {
  const YouScreen({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AuthUser?>(
        valueListenable: AuthService.instance.user,
        builder: (_, user, __) => ValueListenableBuilder<List<ScreeningReport>>(
          valueListenable: AppData.reports,
          builder: (_, reports, __) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: Themes.liquidGlassDecoration(radius: 20),
                child: Row(children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Themes.brandTint.withValues(alpha: 0.70),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.2),
                    ),
                    child: const Icon(Icons.person_rounded, color: Themes.brand, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName?.isNotEmpty == true ? user!.displayName! : 'Patient Profile',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Themes.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          user?.email ?? 'Not signed in',
                          style: const TextStyle(color: Themes.inkSoft, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              _section('Screening activity', [
                _row(Icons.assignment_outlined, 'Total screenings', '${reports.length}'),
                const Divider(),
                _row(Icons.calendar_today_outlined, 'Latest screening', reports.isEmpty ? 'None yet' : _date(reports.first.date)),
              ]),
              const SizedBox(height: 16),
              _section('App preferences', [
                _languageRow(context),
                const Divider(),
                _row(Icons.notifications_none_rounded, 'Monthly reminder', 'Active'),
                const Divider(),
                _row(Icons.privacy_tip_outlined, 'Privacy & consent', 'Managed per report'),
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
                  label: const Text('Sign out', style: TextStyle(color: Themes.danger, fontWeight: FontWeight.w700, fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.45), width: 1.2),
                    backgroundColor: const Color(0xFFFEF2F2).withValues(alpha: 0.85),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

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

  Widget _languageRow(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: LanguageService.instance.code,
        builder: (_, __, ___) => ListTile(
          leading: const Icon(Icons.language_outlined, color: Themes.brand, size: 20),
          title: const Text('Explanation language', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Themes.ink)),
          subtitle: const Text('Language of the AI clinical explanation', style: TextStyle(fontSize: 12, color: Themes.inkSoft)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(LanguageService.instance.label, style: const TextStyle(color: Themes.brand, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: Themes.inkMuted, size: 18),
          ]),
          onTap: () => _pickLanguage(context),
        ),
      );

  Future<void> _pickLanguage(BuildContext context) async {
    final current = LanguageService.instance.code.value;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Align(alignment: Alignment.centerLeft, child: Text('Explanation language', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
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

  static String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  Widget _section(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Themes.ink, letterSpacing: 0.2, shadows: Themes.onMedia)),
      const SizedBox(height: 8),
      Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.85), width: 1.2),
        ),
        child: Column(children: children),
      ),
    ],
  );
  Widget _row(IconData icon, String title, String value) => ListTile(
    leading: Icon(icon, color: Themes.brand, size: 20),
    title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Themes.ink)),
    trailing: Text(value, style: const TextStyle(color: Themes.inkSoft, fontWeight: FontWeight.w600, fontSize: 13)),
  );
}

