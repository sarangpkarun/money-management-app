import 'app_settings.dart';

class AppUser {
  const AppUser({
    required this.name,
    this.currency = 'INR',
    this.timezone = 'Asia/Kolkata',
    this.settings = AppSettings.defaults,
  });

  final String name;
  final String currency;
  final String timezone;

  /// Display and reminder preferences. Saved separately from the profile fields
  /// (see `UserRepository.saveSettings`), so editing the profile never resets
  /// them.
  final AppSettings settings;

  Map<String, dynamic> toMap() => {
    'name': name,
    'currency': currency,
    'timezone': timezone,
  };

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
    name: (m['name'] as String?) ?? '',
    currency: (m['currency'] as String?) ?? 'INR',
    timezone: (m['timezone'] as String?) ?? 'Asia/Kolkata',
    settings: AppSettings.fromMap(
      m['settings'] is Map
          ? Map<String, dynamic>.from(m['settings'] as Map)
          : null,
    ),
  );
}
