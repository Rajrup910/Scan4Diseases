import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services/auth_service.dart';
import '../theme.dart';

/// Combined sign-in / create-account screen. Shown whenever there is no
/// authenticated user (see [AuthGate]).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  bool _register = false;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final auth = AuthService.instance;
      if (_register) {
        await auth.register(
          email: _email.text,
          password: _password.text,
          displayName: _name.text,
        );
      } else {
        await auth.login(email: _email.text, password: _password.text);
      }
      // On success, AuthGate rebuilds and replaces this screen automatically.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Let the user point the app at whichever backend address is reachable, without an app
  /// rebuild. This is the fix for a laptop whose Wi-Fi (DHCP) IP keeps changing.
  Future<void> _serverSettings() async {
    final controller = TextEditingController(text: ApiConfig.baseUrl);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server settings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Backend address. Use the laptop\'s Wi-Fi IP and port 8000 '
                '(e.g. 192.168.1.7:8000). The phone and laptop must be on the same Wi-Fi, '
                'and the backend must be running.',
                style: TextStyle(fontSize: 13, color: Themes.muted),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Backend URL',
                  prefixIcon: Icon(Icons.dns_outlined),
                  hintText: 'http://192.168.1.7:8000',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'reset'),
            child: const Text('Reset to default'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (action == null || action == 'cancel') return;
    if (action == 'reset') {
      await ApiConfig.setBaseUrl(null);
    } else {
      await ApiConfig.setBaseUrl(action);
    }
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backend set to ${ApiConfig.baseUrl}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: 'Server settings',
                  icon: const Icon(Icons.settings_ethernet, color: Themes.muted),
                  onPressed: _loading ? null : _serverSettings,
                ),
              ),
              Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(18),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Themes.primary.withOpacity(.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.health_and_safety_rounded,
                            size: 44, color: Themes.primary),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _register ? 'Create your account' : 'Welcome back',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _register
                          ? 'Sign up to save and sync your screenings.'
                          : 'Sign in to access your saved screenings.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Themes.muted),
                    ),
                    const SizedBox(height: 26),
                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Name (optional)',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return 'Please enter your email.';
                        if (!value.contains('@') || !value.contains('.')) {
                          return 'Please enter a valid email.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _loading ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        final value = v ?? '';
                        if (value.isEmpty) return 'Please enter your password.';
                        if (_register && value.length < 8) {
                          return 'Use at least 8 characters.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(_register ? 'Create account' : 'Sign in'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                                _register = !_register;
                                _formKey.currentState?.reset();
                              }),
                      child: Text(
                        _register
                            ? 'Already have an account? Sign in'
                            : "Don't have an account? Create one",
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'AI-assisted screening only — not a medical diagnosis.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Themes.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
              ],
            ),
        ),
      );
}
