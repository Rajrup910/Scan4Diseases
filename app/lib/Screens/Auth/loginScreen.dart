import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services/auth_service.dart';
import '../theme.dart';
import '../widgets/video_background.dart';
import '../widgets/app_logo_mark.dart';
import '../widgets/slide_to_start.dart';
import '../widgets/expanding_orbs_painter.dart';
import '../widgets/emerald_waves.dart';

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
  bool _showSuccessVeil = false;
  bool _showFailureVeil = false;
  String _failureErrorMessage = '';
  AuthUser? _authenticatedUser;

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
      AuthUser authUser;
      if (_register) {
        authUser = await auth.register(
          email: _email.text,
          password: _password.text,
          displayName: _name.text,
          deferUserUpdate: true,
        );
      } else {
        authUser = await auth.login(
          email: _email.text,
          password: _password.text,
          deferUserUpdate: true,
        );
      }
      if (!mounted) return;
      // Trigger the green login success flourish
      setState(() {
        _loading = false;
        _authenticatedUser = authUser;
        _showSuccessVeil = true;
      });
    } catch (e) {
      if (mounted) {
        final errorText = e.toString().replaceAll('Exception: ', '').trim();
        setState(() {
          _loading = false;
          _showFailureVeil = true;
          _failureErrorMessage = errorText.isNotEmpty ? errorText : 'Authentication failed. Please check your credentials.';
        });
      }
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
  Widget build(BuildContext context) {
    return VideoBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                // Frosted glossy panel behind the form — the app twin of the
                // portal's glass login card. Real backdrop blur lets the ambient
                // video read through, a bright top-edge gloss + hairline rim give
                // it depth.
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      decoration: Themes.liquidGlassDecoration(radius: 24),
                      child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand mark — with glowing ambient emerald/ruby tick/cross depth flourish in background
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Center(
                        child: SizedBox(
                          width: 110,
                          height: 110,
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              // Background glossy blurry tick / cross depth effect behind the emblem
                              _LogoAuthHalo(
                                active: _showSuccessVeil || _showFailureVeil,
                                isError: _showFailureVeil,
                                onPeak: () {
                                  if (_showSuccessVeil && _authenticatedUser != null) {
                                    AuthService.instance.activateUser(_authenticatedUser!);
                                  }
                                },
                                onDismissed: () {
                                  if (mounted && _showFailureVeil) {
                                    setState(() => _showFailureVeil = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(_failureErrorMessage),
                                        behavior: SnackBarBehavior.floating,
                                        backgroundColor: Themes.danger,
                                      ),
                                    );
                                  }
                                },
                              ),
                              const AppLogoMark(size: 76, glow: true),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _register ? 'Create your patient account' : 'Patient sign in',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Themes.ink, letterSpacing: -0.01, shadows: Themes.onMedia),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _register
                          ? 'Sign up to securely save, sync, and share your screenings.'
                          : 'Sign in to access your screening history and reports.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Themes.ink, fontSize: 13.5, shadows: Themes.onMedia),
                    ),
                    const SizedBox(height: 26),
                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Full name (optional)',
                          prefixIcon: Icon(Icons.person_outline, color: Themes.brand),
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
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.mail_outline, color: Themes.brand),
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
                        prefixIcon: const Icon(Icons.lock_outline, color: Themes.brand),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Themes.inkSoft),
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
                    _GlowingSignInButton(
                      onPressed: _loading ? null : _submit,
                      loading: _loading,
                      label: _register ? 'Create account' : 'Sign in',
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
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'AI-assisted screening tool — not a medical diagnosis.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: Themes.inkSoft),
                    ),
                  ],
                ),
              ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
  }
}

/// Ambient depth flourish in the background of the logo for login feedback:
/// - Blurry, glossy emerald aura with checkmark tick radiating in background for success
/// - Blurry, glossy ruby aura with access denied cross radiating in background for failure
class _LogoAuthHalo extends StatefulWidget {
  final bool active;
  final bool isError;
  final VoidCallback? onPeak;
  final VoidCallback? onDismissed;

  const _LogoAuthHalo({
    required this.active,
    this.isError = false,
    this.onPeak,
    this.onDismissed,
  });

  @override
  State<_LogoAuthHalo> createState() => _LogoAuthHaloState();
}

class _LogoAuthHaloState extends State<_LogoAuthHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _peaked = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )
      ..addListener(() {
        if (!widget.isError && !_peaked && _c.value >= 0.45) {
          _peaked = true;
          widget.onPeak?.call();
        }
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onDismissed?.call();
        }
      });
    if (widget.active) _c.forward();
  }

  @override
  void didUpdateWidget(covariant _LogoAuthHalo old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _peaked = false;
      _c.forward(from: 0);
    } else if (!widget.active && old.active) {
      _c.reset();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active && _c.value == 0) return const SizedBox.shrink();
    final isErr = widget.isError;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // Smooth bell curve opacity
        final double opacity;
        if (t <= 0.3) {
          opacity = (t / 0.3).clamp(0.0, 1.0);
        } else if (t <= 0.7) {
          opacity = 1.0;
        } else {
          opacity = (1.0 - (t - 0.7) / 0.3).clamp(0.0, 1.0);
        }

        final scale = 0.75 + 0.55 * Curves.easeOutBack.transform(t.clamp(0.0, 1.0));

        if (opacity <= 0.01) return const SizedBox.shrink();

        return Positioned.fill(
          child: Center(
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity * 0.92,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: isErr
                          ? [
                              const Color(0xFFEF4444).withValues(alpha: 0.75),
                              const Color(0xFFB91C1C).withValues(alpha: 0.40),
                              const Color(0xFF7F1D1D).withValues(alpha: 0.15),
                              Colors.transparent,
                            ]
                          : [
                              const Color(0xFF2DD4BF).withValues(alpha: 0.80),
                              const Color(0xFF15B79E).withValues(alpha: 0.45),
                              const Color(0xFF0F766E).withValues(alpha: 0.18),
                              Colors.transparent,
                            ],
                      stops: const [0.0, 0.45, 0.75, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isErr ? const Color(0xFFEF4444) : Themes.brand)
                            .withValues(alpha: 0.50),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: Center(
                        child: Icon(
                          isErr ? Icons.close_rounded : Icons.check_rounded,
                          size: 48,
                          color: isErr
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFFE6FFFA),
                          shadows: [
                            Shadow(
                              color: (isErr ? const Color(0xFFEF4444) : Themes.mint)
                                  .withValues(alpha: 0.8),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Elegant glossy emerald button with dynamic waves of bright and dark green.
class _GlowingSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final String label;

  const _GlowingSignInButton({
    required this.onPressed,
    required this.loading,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(14);

    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          // Subtle, soft depth shadow
          BoxShadow(
            color: Themes.brand.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: onPressed,
            child: EmeraldWaves(
              borderRadius: borderRadius,
              height: 52,
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        shadows: [
                          Shadow(
                            color: Color(0x60000000),
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Elegant glossy emerald button with dynamic waves of bright and dark green.
class _GlowingSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final String label;

  const _GlowingSignInButton({
    required this.onPressed,
    required this.loading,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(14);

    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          // Subtle, soft depth shadow
          BoxShadow(
            color: Themes.brand.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: onPressed,
            child: EmeraldWaves(
              borderRadius: borderRadius,
              height: 52,
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        shadows: [
                          Shadow(
                            color: Color(0x60000000),
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
