import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import 'loginScreen.dart';

/// Chooses between the sign-in screen and the app, based on auth state.
///
/// [AuthService.instance.restore] runs before the app is built (see main), so
/// on launch this already reflects a remembered session. After login/logout the
/// [AuthService.instance.user] notifier flips and this rebuilds.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.child});

  /// The authenticated app (the bottom-nav shell).
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AuthUser?>(
        valueListenable: AuthService.instance.user,
        builder: (_, user, __) => user == null ? const LoginScreen() : child,
      );
}
