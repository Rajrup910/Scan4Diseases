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
          builder: (_, reports, __) => ListView(padding: const EdgeInsets.all(20), children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: Themes.border)),
              child: Row(children: [
                const CircleAvatar(radius: 30, backgroundColor: Color(0xFFE9EEFF), child: Icon(Icons.person_rounded, color: Themes.primary, size: 32)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user?.displayName?.isNotEmpty == true ? user!.displayName! : 'Your profile',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(user?.email ?? 'Not signed in',
                      style: const TextStyle(color: Themes.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
              ]),
            ),
            const SizedBox(height: 18),
            _section('Screening activity', [
              _row(Icons.assignment_outlined, 'Total screenings', '${reports.length}'),
              _row(Icons.calendar_today_outlined, 'Latest screening', reports.isEmpty ? 'None yet' : _date(reports.first.date)),
            ]),
            const SizedBox(height: 14),
            _section('App settings', [
              _languageRow(context),
              _row(Icons.notifications_none_rounded, 'Notifications', 'On'),
              _row(Icons.privacy_tip_outlined, 'Privacy', 'Learn more'),
            ]),
            const SizedBox(height: 22),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () => _confirmLogout(context),
                icon: const Icon(Icons.logout_rounded, color: Themes.danger),
                label: const Text('Sign out', style: TextStyle(color: Themes.danger, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Themes.border)),
              ),
            ),
          ]),
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
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await AuthService.instance.logout();
  }

  /// Language row that reflects the current choice and opens the picker on tap.
  /// The explanation language is what the backend LLM (gemma2) writes its answer in.
  Widget _languageRow(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: LanguageService.instance.code,
        builder: (_, __, ___) => ListTile(
          leading: const Icon(Icons.language_outlined, color: Themes.primary),
          title: const Text('Language'),
          subtitle: const Text('Language of the AI explanation', style: TextStyle(fontSize: 12, color: Themes.muted)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(LanguageService.instance.label, style: const TextStyle(color: Themes.muted, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: Themes.muted),
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
              title: Text(e.value),
              trailing: e.key == current ? const Icon(Icons.check_rounded, color: Themes.primary) : null,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (chosen != null) await LanguageService.instance.set(chosen);
  }

  static String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  Widget _section(String title, List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 8), Card(child: Column(children: children))]);
  Widget _row(IconData icon, String title, String value) => ListTile(leading: Icon(icon, color: Themes.primary), title: Text(title), trailing: Text(value, style: const TextStyle(color: Themes.muted, fontWeight: FontWeight.w600)));
}
