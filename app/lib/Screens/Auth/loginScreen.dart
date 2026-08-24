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
                    // Brand mark — glowing electric teal emblem (twin of the web mark).
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Center(child: AppLogoMark(size: 76, glow: true)),
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
          Positioned.fill(
            child: _LoginAuthEscalationVeil(
              active: _showSuccessVeil || _showFailureVeil,
              isError: _showFailureVeil,
              errorMessage: _failureErrorMessage,
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
          ),
        ],
      ),
    ),
  ),
);
  }
}

/// Full-screen Expanding Waves with Logo Dismantling & Breathing Transparency Escalation/De-escalation
class _LoginAuthEscalationVeil extends StatefulWidget {
  final bool active;
  final bool isError;
  final String? errorMessage;
  final VoidCallback? onPeak;
  final VoidCallback? onDismissed;

  const _LoginAuthEscalationVeil({
    required this.active,
    this.isError = false,
    this.errorMessage,
    this.onPeak,
    this.onDismissed,
  });

  @override
  State<_LoginAuthEscalationVeil> createState() => _LoginAuthEscalationVeilState();
}

class _LoginAuthEscalationVeilState extends State<_LoginAuthEscalationVeil>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _peaked = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2900),
    )
      ..addListener(() {
        if (!widget.isError && !_peaked && _c.value >= 0.86) {
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
  void didUpdateWidget(covariant _LoginAuthEscalationVeil old) {
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

  /// Multi-stage breathing transparency envelope:
  /// - 0.00 -> 0.45: Escalation (opacity 0 -> 1.0, multi-shade waves bloom from dismantled logo)
  /// - 0.45 -> 0.62: Full Abyss Peak (opaque 1.0 immersion)
  /// - 0.62 -> 0.76: Breathing Dip (opacity dips to 0.74, increasing transparency to show glowing rings)
  /// - 0.76 -> 0.86: Secondary Deep Pulse (opacity rises back to 0.94)
  /// - 0.86 -> 1.00: Final De-escalation (opacity dissolves to 0.0, cleanly revealing home screen)
  double _veil(double t) {
    if (t <= 0.45) {
      return Curves.easeOutCubic.transform((t / 0.45).clamp(0.0, 1.0));
    }
    if (t <= 0.62) {
      return 1.0;
    }
    if (t <= 0.76) {
      final p = (t - 0.62) / 0.14;
      return 1.0 - 0.26 * Curves.easeInOutCubic.transform(p.clamp(0.0, 1.0));
    }
    if (t <= 0.86) {
      final p = (t - 0.76) / 0.10;
      return 0.74 + 0.20 * Curves.easeInOutCubic.transform(p.clamp(0.0, 1.0));
    }
    final p = (t - 0.86) / 0.14;
    return (1.0 - Curves.easeOutCubic.transform(p.clamp(0.0, 1.0))) * 0.94;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active && _c.value == 0) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: !widget.active,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          final opacity = _veil(t).clamp(0.0, 1.0);
          if (opacity <= 0.001) return const SizedBox.shrink();

          final isErr = widget.isError;
          final signScale = 0.5 + 0.5 * Curves.easeOutBack.transform(((t - 0.20) / 0.35).clamp(0.0, 1.0));

          // Dismantling parameters
          final dismantleProgress = (t / 0.38).clamp(0.0, 1.0);
          final ringDismantleScale = 1.0 + 3.0 * Curves.easeOutCubic.transform(dismantleProgress);
          final ringDismantleAlpha = (1.0 - dismantleProgress).clamp(0.0, 1.0);
          final crossDismantleScale = 1.0 + 2.4 * Curves.easeOutCubic.transform(dismantleProgress);
          final crossDismantleRotation = 0.65 * Curves.easeOutCubic.transform(dismantleProgress);

          return Opacity(
            opacity: opacity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: 24 * opacity,
                    sigmaY: 24 * opacity,
                  ),
                  child: const SizedBox.expand(),
                ),
                CustomPaint(
                  painter: ExpandingOrbsPainter(
                    progress: t,
                    opacity: opacity,
                    isError: isErr,
                  ),
                  child: const SizedBox.expand(),
                ),

                // Center Dismantling Logo Fragment Eruption
                if (dismantleProgress < 0.98)
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Dismantling expanding outer ring
                        Transform.scale(
                          scale: ringDismantleScale,
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: (isErr ? const Color(0xFFEF4444) : Themes.mint)
                                    .withValues(alpha: 0.85 * ringDismantleAlpha),
                                width: 3.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (isErr ? const Color(0xFFEF4444) : Themes.brand)
                                      .withValues(alpha: 0.70 * ringDismantleAlpha),
                                  blurRadius: 28,
                                  spreadRadius: 3,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Dismantling crossbars breaking apart
                        Transform.scale(
                          scale: crossDismantleScale,
                          child: Transform.rotate(
                            angle: crossDismantleRotation,
                            child: Icon(
                              Icons.all_inclusive_rounded,
                              size: 48,
                              color: (isErr ? const Color(0xFFFCA5A5) : const Color(0xFF6FE0CD))
                                  .withValues(alpha: 0.85 * ringDismantleAlpha),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Central Glowing Sign (Checkmark for success, Cross for failure)
                if (t >= 0.20)
                  Center(
                    child: Transform.scale(
                      scale: signScale,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isErr
                                ? const [
                                    Color(0xFFEF4444),
                                    Color(0xFFB3261E),
                                    Color(0xFF7F1D1D),
                                  ]
                                : const [
                                    Color(0xFF15B79E),
                                    Color(0xFF12695A),
                                    Color(0xFF0D4F44),
                                  ],
                          ),
                          border: Border.all(
                            color: isErr
                                ? const Color(0xFFF87171)
                                : const Color(0xFF6FE0CD),
                            width: 2.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isErr
                                  ? const Color(0xFFEF4444).withValues(alpha: 0.75)
                                  : const Color(0xFF15B79E).withValues(alpha: 0.75),
                              blurRadius: 40,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            isErr ? Icons.close_rounded : Icons.check_rounded,
                            color: Colors.white,
                            size: 54,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
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
