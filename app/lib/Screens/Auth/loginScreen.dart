import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services/auth_service.dart';
import '../../services/motion_service.dart';
import '../../services/sound_service.dart';
import '../../services/theme_service.dart';
import '../theme.dart';
import '../widgets/video_background.dart';
import '../widgets/app_logo_mark.dart';
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
      final emailInput = _email.text.trim().toLowerCase();
      final passwordInput = _password.text.trim();
      final nameInput = _name.text.trim();

      if (_register) {
        authUser = await auth.register(
          email: emailInput,
          password: passwordInput,
          displayName: nameInput,
          deferUserUpdate: true,
        );
      } else {
        authUser = await auth.login(
          email: emailInput,
          password: passwordInput,
          deferUserUpdate: true,
        );
      }
      if (!mounted) return;
      // Trigger the green login success flourish
      SoundService.instance.success();
      setState(() {
        _loading = false;
        _authenticatedUser = authUser;
        _showSuccessVeil = true;
      });
    } catch (e) {
      if (mounted) {
        final errorText = e.toString().replaceAll('Exception: ', '').trim();
        SoundService.instance.error();
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
    // Rebuild when the theme flips so both the form chrome and the new
    // top-right chip re-tint together. isDark uses the app's own preference
    // when set and the OS setting when it isn't.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.instance.mode,
      builder: (context, __, ___) {
        final dark = ThemeService.instance.isDark(context);
        final ink = dark ? Themes.darkInk : Themes.ink;
        final inkSoft = dark ? Themes.darkInkSoft : Themes.inkSoft;
        final accent = dark ? Themes.tealLight : Themes.brand;
        final onMedia = dark ? Themes.onMediaDark : Themes.onMedia;
    return VideoBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              // Server-settings icon (kept where it was — tucked into a corner
              // for advanced use).
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  tooltip: 'Server settings',
                  icon: Icon(Icons.settings_ethernet, color: dark ? Themes.darkInkSoft : Themes.muted),
                  onPressed: _loading ? null : _serverSettings,
                ),
              ),
              // Top-right frosted chip: theme + motion, both live-updating via
              // ValueListenableBuilder — visible BEFORE sign-in so a user
              // arriving in the wrong theme can flip it without hunting for
              // Profile. Matches the mockup's new "chip" in login-dark.
              Positioned(
                top: 6,
                right: 12,
                child: _PreloginChip(dark: dark),
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
                    // Lift the blur slightly and lower the panel alpha so the
                    // ambient blueprint background reads clearly through the
                    // sign-in card — matches user feedback on the register
                    // screen feeling too opaque.
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      // Glass panel preserved in both themes — dark variant
                      // gets the teal-tinted rim from the shared helper. The
                      // explicit low alphas let the video breathe through.
                      decoration: Themes.liquidGlassDecoration(
                        radius: 24,
                        dark: dark,
                        topAlpha: dark ? 0.42 : 0.44,
                        bottomAlpha: dark ? 0.28 : 0.28,
                      ),
                      child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand mark — with glowing ambient emerald/ruby tick/cross depth flourish
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
                              // Logo Mark (dims slightly when tick/cross is active so feedback is 100% crisp & unobstructed)
                              AnimatedOpacity(
                                opacity: (_showSuccessVeil || _showFailureVeil) ? 0.10 : 1.0,
                                duration: const Duration(milliseconds: 250),
                                child: const AppLogoMark(size: 76, glow: true),
                              ),
                              // Vivid glossy tick / cross flourish
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
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _register ? 'Create your patient account' : 'Patient sign in',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: ink,
                        letterSpacing: -0.01,
                        shadows: onMedia,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _register
                          ? 'Sign up to securely save, sync, and share your screenings.'
                          : 'Sign in to access your screening history and reports.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: ink, fontSize: 13.5, shadows: onMedia),
                    ),
                    const SizedBox(height: 26),
                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'Full name (optional)',
                          prefixIcon: Icon(Icons.person_outline, color: accent),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.mail_outline, color: accent),
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
                      autocorrect: false,
                      enableSuggestions: false,
                      onFieldSubmitted: (_) => _loading ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline, color: accent),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: inkSoft),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        final value = (v ?? '').trim();
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
                    Text(
                      'AI-assisted screening tool — not a medical diagnosis.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: inkSoft),
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
      },
    );
  }
}

/// Frosted mini-panel that sits at the top-right of the login screen. Exposes
/// the theme toggle and the reduce-ambient-motion toggle BEFORE sign-in so a
/// user arriving in the wrong appearance can flip it without hunting through
/// Profile. Both bindings are live: tap flips the shared service and every
/// listener across the app rebuilds — including this chip's own icons.
class _PreloginChip extends StatelessWidget {
  const _PreloginChip({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [const Color(0xFF1E2430).withValues(alpha: 0.72),
                 const Color(0xFF141820).withValues(alpha: 0.58)]
              : [Colors.white.withValues(alpha: 0.72),
                 Colors.white.withValues(alpha: 0.54)],
        ),
        border: Border.all(
          color: dark ? Themes.tealGlow.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.85),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: dark ? Themes.tealGlow.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.35),
            blurRadius: 10,
            spreadRadius: -1,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.30 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Theme toggle — icon flips with the current mode.
          _ChipButton(
            icon: dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            tooltip: dark ? 'Switch to light theme' : 'Switch to dark theme',
            dark: dark,
            onTap: () => ThemeService.instance.toggle(context),
          ),
          const SizedBox(width: 2),
          // Motion toggle — the "waves" icon means "ambient motion is on".
          ValueListenableBuilder<bool>(
            valueListenable: MotionService.instance.reduced,
            builder: (_, reduced, __) {
              final forcedByOs = MediaQuery.maybeDisableAnimationsOf(context) == true;
              final held = reduced || forcedByOs;
              return _ChipButton(
                icon: held ? Icons.motion_photos_off_rounded : Icons.waves_rounded,
                tooltip: held
                    ? (forcedByOs ? 'Reduced by device setting' : 'Enable ambient motion')
                    : 'Reduce ambient motion',
                dark: dark,
                onTap: forcedByOs ? null : () => MotionService.instance.toggle(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({
    required this.icon,
    required this.tooltip,
    required this.dark,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final bool dark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tint = dark ? Themes.tealLight : Themes.brand;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(
            icon,
            size: 16,
            color: onTap == null ? tint.withValues(alpha: 0.45) : tint,
          ),
        ),
      ),
    );
  }
}

/// Ambient depth flourish for login feedback:
/// - Crisp, glossy emerald disc with glowing white checkmark tick for success
/// - Crisp, glossy ruby disc with glowing white access denied cross for failure
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
      duration: const Duration(milliseconds: 1250),
    )
      ..addListener(() {
        if (!widget.isError && !_peaked && _c.value >= 0.88) {
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
        // Hold visible for generous duration (0.20 -> 0.88), then gentle fade
        final double opacity;
        if (t <= 0.20) {
          opacity = (t / 0.20).clamp(0.0, 1.0);
        } else if (t <= 0.88) {
          opacity = 1.0;
        } else {
          opacity = (1.0 - (t - 0.88) / 0.12).clamp(0.0, 1.0);
        }

        // easeOutCubic (0.95→1.0) instead of easeOutBack: the previous
        // overshoot bounce clashed with the app's restrained page transition
        // and read as marketing pop. Scale range narrowed so the disc lands
        // calmly.
        final scale = 0.95 + 0.05 * Curves.easeOutCubic.transform((t / 0.35).clamp(0.0, 1.0));

        if (opacity <= 0.01) return const SizedBox.shrink();

        final accent = isErr ? const Color(0xFFEF4444) : Themes.brand;
        final rim    = isErr ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7);

        return Positioned.fill(
          child: Center(
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isErr
                          ? const [
                              Color(0xFFEF4444),
                              Color(0xFFDC2626),
                              Color(0xFF7F1D1D),
                            ]
                          : const [
                              Color(0xFF10B981),
                              Color(0xFF059669),
                              Color(0xFF064E3B),
                            ],
                    ),
                    border: Border.all(color: rim.withValues(alpha: 0.7), width: 1.6),
                    // Restrained: a soft brand-tinted ambient shadow + a hairline
                    // luminous rim, no 36-blur neon bloom. Matches the "no AI-slop
                    // neon glows" language on cards elsewhere in the app.
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.32),
                        blurRadius: 12,
                        spreadRadius: 0,
                        offset: const Offset(0, 6),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.20),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      isErr ? Icons.close_rounded : Icons.check_rounded,
                      size: 52,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
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
