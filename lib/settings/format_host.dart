import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/app_settings.dart';
import '../core/money/money.dart';
import '../core/ui/format.dart';
import 'settings_providers.dart';

/// Applies the user's currency, number and date formats to the whole app. The
/// formatters are read from small holders (so the many `Money.format()` and
/// `formatShortDate()` calls need no changes); when a setting changes the holders
/// are updated and every mounted screen is rebuilt once.
class FormatHost extends ConsumerStatefulWidget {
  const FormatHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<FormatHost> createState() => _FormatHostState();
}

class _FormatHostState extends ConsumerState<FormatHost> {
  (String, NumberGrouping, DateStyle)? _applied;

  void _rebuildAll() {
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final currency = ref.watch(appCurrencyProvider);
    final symbol = currencySymbol(currency);
    final grouping = settings.groupingFor(currency);
    final next = (symbol, grouping, settings.dateStyle);

    MoneyFormat.symbol = symbol;
    MoneyFormat.grouping = grouping;
    DateFormatHolder.style = settings.dateStyle;

    final changed = _applied != null && _applied != next;
    _applied = next;
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildAll();
      });
    }
    return widget.child;
  }
}
