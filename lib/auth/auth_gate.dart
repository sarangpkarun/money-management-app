import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';
import 'login_screen.dart';
import 'verify_email_screen.dart';

/// Shows login when signed out, the verify-email screen until the address is
/// verified (the Firestore rules require it), then [home].
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    return auth.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Auth error: $e'))),
      data: (user) {
        if (user == null) return const LoginScreen();
        if (!user.emailVerified) return VerifyEmailScreen(user: user);
        // Fire-and-forget: creates the profile doc; failures must not block use.
        ref.watch(profileBootstrapProvider);
        return home;
      },
    );
  }
}
