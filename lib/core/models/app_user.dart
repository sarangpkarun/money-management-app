class AppUser {
  const AppUser({
    required this.name,
    this.currency = 'INR',
    this.timezone = 'Asia/Kolkata',
  });

  final String name;
  final String currency;
  final String timezone;

  Map<String, dynamic> toMap() => {
    'name': name,
    'currency': currency,
    'timezone': timezone,
  };

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
    name: m['name'] as String,
    currency: (m['currency'] as String?) ?? 'INR',
    timezone: (m['timezone'] as String?) ?? 'Asia/Kolkata',
  );
}
