import 'package:flutter/material.dart';

/// What the app keeps and where, in plain words.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const sections = [
    (
      'What is stored',
      'Your people, entries, payments, reminders and settings are saved in '
          'your own account in the cloud so they appear on every phone you sign '
          'in on. Only you can read them.',
    ),
    (
      'Contacts',
      'The app reads your contacts only when you open "Import from contacts", '
          'and saves only the people you tick. Nothing else leaves your phone.',
    ),
    (
      'Ads and tracking',
      'There are no ads, and this version does not track what you do.',
    ),
    (
      'Your copy',
      'Settings, then "Export my data" gives you a file with everything in your '
          'account. It contains private information, so keep it somewhere safe.',
    ),
    (
      'Deleting everything',
      'Profile, then "Delete account" erases your account and all its data for '
          'good.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          for (final (title, body) in sections) ...[
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(body),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}
