import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_form.dart';
import 'auth_providers.dart';
import 'auth_repository.dart';

class VerifyEmailScreen extends ConsumerWidget {
  const VerifyEmailScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AuthRepository repo() => ref.read(authRepositoryProvider);
    return AuthScaffold(
      title: 'Verify your email',
      children: [
        Text(
          'We sent a verification link to ${user.email}. Open it, then tap '
          '"I\'ve verified" below.',
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final ok = await runAuthAction(context, repo().reloadUser);
            if (ok && !(repo().currentUser?.emailVerified ?? false)) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Email not verified yet.')),
              );
            }
          },
          child: const Text("I've verified"),
        ),
        TextButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final ok = await runAuthAction(context, repo().resendVerification);
            if (ok) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Verification email sent.')),
              );
            }
          },
          child: const Text('Resend email'),
        ),
        TextButton(
          onPressed: () => repo().signOut(),
          child: const Text('Use a different account'),
        ),
      ],
    );
  }
}
