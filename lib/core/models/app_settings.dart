import '../money/money.dart';

/// How dates are written.
enum DateStyle { dMonY, dmy, mdy }

enum ThemeChoice { system, light, dark }

enum SummaryMode { off, daily, weekly }

/// Currency symbols for the supported currencies.
const currencySymbols = {
  'INR': '₹',
  'USD': r'$',
  'EUR': '€',
  'GBP': '£',
  'AED': 'AED ',
};

String currencySymbol(String code) => currencySymbols[code] ?? '$code ';

T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

int _minutes(Object? v, int fallback) =>
    v is int && v >= 0 && v < 24 * 60 ? v : fallback;

/// A daily window (it may cross midnight) in which automatic alarms and the
/// summary wait for the end instead of ringing.
class QuietHours {
  const QuietHours({
    this.enabled = false,
    this.startMinutes = 22 * 60,
    this.endMinutes = 7 * 60,
  });

  final bool enabled;

  /// Minutes after midnight.
  final int startMinutes;
  final int endMinutes;

  QuietHours copyWith({bool? enabled, int? startMinutes, int? endMinutes}) =>
      QuietHours(
        enabled: enabled ?? this.enabled,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
      );

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'start': startMinutes,
    'end': endMinutes,
  };

  factory QuietHours.fromMap(Map<String, dynamic>? m) => m == null
      ? const QuietHours()
      : QuietHours(
          enabled: m['enabled'] == true,
          startMinutes: _minutes(m['start'], 22 * 60),
          endMinutes: _minutes(m['end'], 7 * 60),
        );

  @override
  bool operator ==(Object other) =>
      other is QuietHours &&
      other.enabled == enabled &&
      other.startMinutes == startMinutes &&
      other.endMinutes == endMinutes;

  @override
  int get hashCode => Object.hash(enabled, startMinutes, endMinutes);
}

/// The daily or weekly summary notification.
class SummarySettings {
  const SummarySettings({
    this.mode = SummaryMode.off,
    this.minutes = 8 * 60,
    this.weekday = DateTime.monday,
  });

  final SummaryMode mode;

  /// Minutes after midnight.
  final int minutes;

  /// 1 = Monday ... 7 = Sunday (weekly only).
  final int weekday;

  SummarySettings copyWith({SummaryMode? mode, int? minutes, int? weekday}) =>
      SummarySettings(
        mode: mode ?? this.mode,
        minutes: minutes ?? this.minutes,
        weekday: weekday ?? this.weekday,
      );

  Map<String, dynamic> toMap() => {
    'mode': mode.name,
    'minutes': minutes,
    'weekday': weekday,
  };

  factory SummarySettings.fromMap(Map<String, dynamic>? m) => m == null
      ? const SummarySettings()
      : SummarySettings(
          mode: _byName(SummaryMode.values, m['mode'], SummaryMode.off),
          minutes: _minutes(m['minutes'], 8 * 60),
          weekday: m['weekday'] is int && m['weekday'] >= 1 && m['weekday'] <= 7
              ? m['weekday'] as int
              : DateTime.monday,
        );

  @override
  bool operator ==(Object other) =>
      other is SummarySettings &&
      other.mode == mode &&
      other.minutes == minutes &&
      other.weekday == weekday;

  @override
  int get hashCode => Object.hash(mode, minutes, weekday);
}

/// The user's display, reminder and summary preferences, kept on their profile
/// so every phone they sign in on agrees.
class AppSettings {
  const AppSettings({
    this.grouping,
    this.dateStyle = DateStyle.dMonY,
    this.theme = ThemeChoice.system,
    this.autoAlarmMinutes = 9 * 60,
    this.quietHours = const QuietHours(),
    this.summary = const SummarySettings(),
  });

  static const defaults = AppSettings();

  /// Null means automatic: Indian grouping for rupees, western otherwise.
  final NumberGrouping? grouping;
  final DateStyle dateStyle;
  final ThemeChoice theme;

  /// When automatic payment alarms ring, in minutes after midnight.
  final int autoAlarmMinutes;
  final QuietHours quietHours;
  final SummarySettings summary;

  NumberGrouping groupingFor(String currency) =>
      grouping ??
      (currency == 'INR' ? NumberGrouping.indian : NumberGrouping.western);

  AppSettings copyWith({
    NumberGrouping? grouping,
    bool clearGrouping = false,
    DateStyle? dateStyle,
    ThemeChoice? theme,
    int? autoAlarmMinutes,
    QuietHours? quietHours,
    SummarySettings? summary,
  }) => AppSettings(
    grouping: clearGrouping ? null : (grouping ?? this.grouping),
    dateStyle: dateStyle ?? this.dateStyle,
    theme: theme ?? this.theme,
    autoAlarmMinutes: autoAlarmMinutes ?? this.autoAlarmMinutes,
    quietHours: quietHours ?? this.quietHours,
    summary: summary ?? this.summary,
  );

  Map<String, dynamic> toMap() => {
    'grouping': grouping?.name,
    'dateStyle': dateStyle.name,
    'theme': theme.name,
    'autoAlarmMinutes': autoAlarmMinutes,
    'quietHours': quietHours.toMap(),
    'summary': summary.toMap(),
  };

  /// Missing or damaged values fall back to the defaults.
  factory AppSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return defaults;
    NumberGrouping? grouping;
    for (final g in NumberGrouping.values) {
      if (g.name == m['grouping']) grouping = g;
    }
    return AppSettings(
      grouping: grouping,
      dateStyle: _byName(DateStyle.values, m['dateStyle'], DateStyle.dMonY),
      theme: _byName(ThemeChoice.values, m['theme'], ThemeChoice.system),
      autoAlarmMinutes: _minutes(m['autoAlarmMinutes'], 9 * 60),
      quietHours: QuietHours.fromMap(
        m['quietHours'] is Map
            ? Map<String, dynamic>.from(m['quietHours'] as Map)
            : null,
      ),
      summary: SummarySettings.fromMap(
        m['summary'] is Map
            ? Map<String, dynamic>.from(m['summary'] as Map)
            : null,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.grouping == grouping &&
      other.dateStyle == dateStyle &&
      other.theme == theme &&
      other.autoAlarmMinutes == autoAlarmMinutes &&
      other.quietHours == quietHours &&
      other.summary == summary;

  @override
  int get hashCode => Object.hash(
    grouping,
    dateStyle,
    theme,
    autoAlarmMinutes,
    quietHours,
    summary,
  );
}
