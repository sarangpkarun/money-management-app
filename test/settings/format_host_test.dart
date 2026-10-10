import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/user_repository.dart';
import 'package:money_manager/core/models/app_settings.dart';
import 'package:money_manager/core/models/app_user.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/core/ui/format.dart';
import 'package:money_manager/settings/format_host.dart';

void main() {
  late FakeFirebaseFirestore db;
  late UserRepository repo;

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = UserRepository(db, 'u1');
    await repo.save(const AppUser(name: 'A'));
  });

  tearDown(() {
    MoneyFormat.reset();
    DateFormatHolder.style = DateStyle.dMonY;
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [userRepositoryProvider.overrideWithValue(repo)],
        child: FormatHost(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  // Built once, with no dependency on the settings: it can only
                  // redraw because the host rebuilds the whole tree.
                  Builder(
                    builder: (_) => Text(Money.fromRupees(1234567).format()),
                  ),
                  Builder(
                    builder: (_) =>
                        Text(formatShortDate(DateTime(2026, 10, 9))),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('defaults: rupees, Indian grouping, "9 Oct 2026"', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('₹12,34,567'), findsOneWidget);
    expect(find.text('9 Oct 2026'), findsOneWidget);
  });

  testWidgets('changing the currency redraws amounts already on screen', (
    tester,
  ) async {
    await pump(tester);
    await repo.save(const AppUser(name: 'A', currency: 'USD'));
    await tester.pumpAndSettle();
    expect(find.text(r'$1,234,567'), findsOneWidget);
    expect(find.text('₹12,34,567'), findsNothing);
  });

  testWidgets('an explicit number format overrides the currency default', (
    tester,
  ) async {
    await pump(tester);
    await repo.save(const AppUser(name: 'A', currency: 'USD'));
    await repo.saveSettings(const AppSettings(grouping: NumberGrouping.indian));
    await tester.pumpAndSettle();
    expect(find.text(r'$12,34,567'), findsOneWidget);
  });

  testWidgets('changing the date style redraws dates', (tester) async {
    await pump(tester);
    await repo.saveSettings(const AppSettings(dateStyle: DateStyle.dmy));
    await tester.pumpAndSettle();
    expect(find.text('09/10/2026'), findsOneWidget);
    await repo.saveSettings(const AppSettings(dateStyle: DateStyle.mdy));
    await tester.pumpAndSettle();
    expect(find.text('10/09/2026'), findsOneWidget);
  });

  testWidgets('changing something unrelated does not disturb formats', (
    tester,
  ) async {
    await pump(tester);
    await repo.saveSettings(const AppSettings(theme: ThemeChoice.dark));
    await tester.pumpAndSettle();
    expect(find.text('₹12,34,567'), findsOneWidget);
    expect(find.text('9 Oct 2026'), findsOneWidget);
  });
}
