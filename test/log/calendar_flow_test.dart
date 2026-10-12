import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/log_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/models/log_entry.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/log/calendar_screen.dart';
import 'package:money_manager/log/log_list_screen.dart';

void main() {
  late LogRepository repo;
  final today = DateTime(2026, 10, 13);

  setUp(() => repo = LogRepository(FakeFirebaseFirestore(), 'u1'));

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [logRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  LogEntry e(String title, DateTime d, int rupees, {String? account}) =>
      LogEntry(
        title: title,
        date: d,
        amount: Money.fromRupees(rupees),
        account: account,
        createdAt: DateTime(2026, 1, 1),
      );

  testWidgets('calendar shows the selected day and month totals', (
    tester,
  ) async {
    await repo.add(e('Amazon', today, 850, account: 'HDFC Credit Card'));
    await repo.add(e('Old', DateTime(2026, 10, 2), 100));
    await pump(tester, CalendarScreen(today: today));

    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Spent ₹950'), findsOneWidget);
    expect(find.text('Amazon'), findsOneWidget);
    expect(find.text('Old'), findsNothing);

    await tester.tap(find.text('2').first);
    await tester.pumpAndSettle();
    expect(find.text('Old'), findsOneWidget);
    expect(find.text('Amazon'), findsNothing);
  });

  testWidgets('adding from the calendar saves on the selected day', (
    tester,
  ) async {
    await pump(tester, CalendarScreen(today: today));
    expect(find.text('Nothing on this day'), findsOneWidget);

    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'What was it for?'),
      'Fuel',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '500');
    await tester.enterText(
      find.widgetWithText(TextField, 'Paid with (optional)'),
      'HDFC Credit Card',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = (await repo.getAll()).single;
    expect(saved.title, 'Fuel');
    expect(saved.date, today);
    expect(saved.account, 'HDFC Credit Card');
    expect(find.text('Fuel'), findsOneWidget);
  });

  testWidgets('save is blocked without a title', (tester) async {
    await pump(tester, CalendarScreen(today: today));
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter what this is for'), findsOneWidget);
    expect(await repo.getAll(), isEmpty);
  });

  testWidgets('list search finds where something was paid', (tester) async {
    await repo.add(
      e('Headphones', DateTime(2026, 9, 5), 2000, account: 'HDFC Credit Card'),
    );
    await repo.add(e('Lunch', DateTime(2026, 10, 1), 200, account: 'Cash'));
    await pump(tester, const LogListScreen());

    expect(find.text('Headphones'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hdfc');
    await tester.pumpAndSettle();
    expect(find.text('Headphones'), findsOneWidget);
    expect(find.text('Lunch'), findsNothing);
  });
}
