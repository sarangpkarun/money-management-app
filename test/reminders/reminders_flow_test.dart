import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/data/people_repository.dart';
import 'package:money_manager/core/data/providers.dart';
import 'package:money_manager/core/data/reminder_repository.dart';
import 'package:money_manager/core/data/transaction_repository.dart';
import 'package:money_manager/core/models/person.dart';
import 'package:money_manager/core/models/reminder.dart';
import 'package:money_manager/core/money/money.dart';
import 'package:money_manager/reminders/reminders_screen.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ReminderRepository repo;
  late PeopleRepository people;
  late TransactionRepository txns;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = ReminderRepository(db, 'u1');
    people = PeopleRepository(db, 'u1');
    txns = TransactionRepository(db, 'u1');
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reminderRepositoryProvider.overrideWithValue(repo),
          peopleRepositoryProvider.overrideWithValue(people),
          transactionRepositoryProvider.overrideWithValue(txns),
        ],
        child: const MaterialApp(home: RemindersScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Reminder rem(
    String title,
    DateTime at, {
    RepeatRule repeat = const RepeatRule.none(),
    bool done = false,
  }) => Reminder(
    title: title,
    at: at,
    repeat: repeat,
    done: done,
    createdAt: DateTime(2026, 1, 1),
  );

  Future<List<Map<String, dynamic>>> stored() async => [
    for (final d in (await db.collection('users/u1/reminders').get()).docs)
      d.data(),
  ];

  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> openAdd(WidgetTester tester) async {
    await pump(tester);
    await tester.tap(find.text('Add reminder'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  group('list', () {
    testWidgets('empty state', (tester) async {
      await pump(tester);
      expect(find.text('No reminders yet'), findsOneWidget);
      expect(find.text('Add reminder'), findsOneWidget);
    });

    testWidgets('active reminders come in order of their next ring', (
      tester,
    ) async {
      final soon = DateTime.now().add(const Duration(days: 2));
      final later = DateTime.now().add(const Duration(days: 20));
      await repo.add(
        rem('Later one', DateTime(later.year, later.month, later.day, 9)),
      );
      await repo.add(
        rem('Sooner one', DateTime(soon.year, soon.month, soon.day, 9)),
      );
      await pump(tester);
      final a = tester.getTopLeft(find.text('Sooner one')).dy;
      final b = tester.getTopLeft(find.text('Later one')).dy;
      expect(a < b, isTrue);
    });

    testWidgets('a repeating reminder shows its next ring and its rule', (
      tester,
    ) async {
      final start = DateTime(2020, 1, 31, 9);
      await repo.add(rem('Rent', start, repeat: const RepeatRule.monthly()));
      await pump(tester);
      expect(find.textContaining('Monthly on the 31st'), findsOneWidget);
      // The shown ring is in the future, not the 2020 start.
      expect(find.textContaining('2020'), findsNothing);
    });

    testWidgets('a passed one-off is marked passed, not hidden', (
      tester,
    ) async {
      await repo.add(rem('Old', DateTime(2020, 1, 1, 9)));
      await pump(tester);
      expect(find.textContaining('Passed'), findsOneWidget);
    });

    testWidgets('done reminders sit under a Done heading', (tester) async {
      await repo.add(rem('Active', DateTime(2099, 1, 1, 9)));
      await repo.add(rem('Finished', DateTime(2099, 2, 1, 9), done: true));
      await pump(tester);
      expect(find.text('Done'), findsWidgets);
      final heading = tester.getTopLeft(find.text('Done').first).dy;
      expect(tester.getTopLeft(find.text('Active')).dy < heading, isTrue);
      expect(tester.getTopLeft(find.text('Finished')).dy > heading, isTrue);
    });
  });

  group('add', () {
    testWidgets('a title is required', (tester) async {
      await openAdd(tester);
      await save(tester);
      expect(find.text('Enter a title'), findsOneWidget);
      expect(await stored(), isEmpty);
    });

    testWidgets('saves with the defaults', (tester) async {
      await openAdd(tester);
      await tester.enterText(field('Title'), 'Pay Ravi');
      await save(tester);
      final r = (await stored()).single;
      expect(r['title'], 'Pay Ravi');
      expect(r['snoozeMinutes'], 10);
      expect(r['tone'], 'alarm');
      expect(r['vibration'], 'long');
      expect(r['volume'], 'high');
      expect((r['repeat'] as Map)['kind'], 'none');
      expect(find.text('Pay Ravi'), findsOneWidget); // back on the list
    });

    testWidgets('snooze, tone, vibration and volume are saved', (tester) async {
      await openAdd(tester);
      await tester.enterText(field('Title'), 'Loud');
      await tapVisible(tester, find.text('15 min'));
      await tapVisible(tester, find.text('Short'));
      await tapVisible(tester, find.text('Low'));
      await tapVisible(tester, find.text('Alarm sound'));
      await tester.tap(find.text('Ringtone').last);
      await tester.pumpAndSettle();
      await save(tester);
      final r = (await stored()).single;
      expect(r['snoozeMinutes'], 15);
      expect(r['vibration'], 'short');
      expect(r['volume'], 'low');
      expect(r['tone'], 'ringtone');
    });

    testWidgets('weekly needs a weekday, then saves the chosen ones', (
      tester,
    ) async {
      await openAdd(tester);
      await tester.enterText(field('Title'), 'Gym');
      await tapVisible(tester, find.text('Does not repeat'));
      await tester.tap(find.text('Weekly').last);
      await tester.pumpAndSettle();
      await save(tester);
      expect(find.text('Pick at least one weekday'), findsOneWidget);
      expect(await stored(), isEmpty);
      await tapVisible(tester, find.text('Mon'));
      await tapVisible(tester, find.text('Wed'));
      await save(tester);
      final repeat = Map<String, dynamic>.from(
        (await stored()).single['repeat'] as Map,
      );
      expect(repeat['kind'], 'weekly');
      expect(repeat['weekdays'], [1, 3]);
    });

    testWidgets('every N days saves the interval', (tester) async {
      await openAdd(tester);
      await tester.enterText(field('Title'), 'Water plants');
      await tapVisible(tester, find.text('Does not repeat'));
      await tester.tap(find.text('Every N days').last);
      await tester.pumpAndSettle();
      await tester.enterText(field('Every how many days'), '4');
      await save(tester);
      final repeat = Map<String, dynamic>.from(
        (await stored()).single['repeat'] as Map,
      );
      expect(repeat['kind'], 'everyNDays');
      expect(repeat['interval'], 4);
    });

    testWidgets('an out-of-range N is refused', (tester) async {
      await openAdd(tester);
      await tester.enterText(field('Title'), 'x');
      await tapVisible(tester, find.text('Does not repeat'));
      await tester.tap(find.text('Every N days').last);
      await tester.pumpAndSettle();
      await tester.enterText(field('Every how many days'), '400');
      await save(tester);
      expect(find.textContaining('between 1 and 365'), findsOneWidget);
      expect(await stored(), isEmpty);
    });

    testWidgets('can be linked to an open entry', (tester) async {
      // A tall screen so the whole form is on screen, menu included.
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final p = await people.add(
        Person(name: 'Ravi', createdAt: DateTime(2026, 1, 1)),
      );
      final id = await txns.addInstalmentPlan(
        personId: p,
        personName: 'Ravi',
        title: 'Loan',
        total: Money.fromRupees(1000),
        months: 2,
        startDate: DateTime(2030, 1, 31),
      );
      await openAdd(tester);
      await tester.enterText(field('Title'), 'Pay back');
      await tapVisible(tester, find.byType(DropdownButtonFormField<String?>));
      await tester.tap(find.text('Ravi · Loan').last);
      await tester.pumpAndSettle();
      await save(tester);
      expect((await stored()).single['transactionId'], id);
      expect(find.textContaining('Linked entry'), findsOneWidget);
    });
  });

  group('edit', () {
    Future<void> openFirst(WidgetTester tester, String title) async {
      await pump(tester);
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }

    testWidgets('changing the title and the repeat saves', (tester) async {
      await repo.add(rem('Old', DateTime(2099, 1, 1, 9)));
      await openFirst(tester, 'Old');
      expect(find.text('Edit reminder'), findsOneWidget);
      await tester.enterText(field('Title'), 'New');
      await tapVisible(tester, find.text('Does not repeat'));
      await tester.tap(find.text('Every day').last);
      await tester.pumpAndSettle();
      await save(tester);
      final r = (await stored()).single;
      expect(r['title'], 'New');
      expect((r['repeat'] as Map)['kind'], 'daily');
    });

    testWidgets('an old one-off can still be edited', (tester) async {
      await repo.add(rem('Old', DateTime(2020, 1, 1, 9)));
      await openFirst(tester, 'Old');
      await tester.enterText(field('Title'), 'Old renamed');
      await save(tester);
      expect((await stored()).single['title'], 'Old renamed');
    });

    testWidgets('the saved weekday set and N come back in the form', (
      tester,
    ) async {
      await repo.add(
        rem(
          'Gym',
          DateTime(2099, 1, 5, 9),
          repeat: const RepeatRule.weekly({2, 4}),
        ),
      );
      await openFirst(tester, 'Gym');
      final tue = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Tue'),
      );
      final mon = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Mon'),
      );
      expect(tue.selected, isTrue);
      expect(mon.selected, isFalse);
    });

    testWidgets('mark done moves it under Done, reopen brings it back', (
      tester,
    ) async {
      await repo.add(rem('Task', DateTime(2099, 1, 1, 9)));
      await openFirst(tester, 'Task');
      await tester.tap(find.text('Mark done'));
      await tester.pumpAndSettle();
      expect((await stored()).single['done'], isTrue);
      expect(find.text('Done'), findsWidgets);
      await tester.tap(find.text('Task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reopen'));
      await tester.pumpAndSettle();
      expect((await stored()).single['done'], isFalse);
    });

    testWidgets('delete asks first', (tester) async {
      await repo.add(rem('Gone', DateTime(2099, 1, 1, 9)));
      await openFirst(tester, 'Gone');
      await tester.tap(find.byTooltip('Delete reminder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await stored(), hasLength(1));
      await tester.tap(find.byTooltip('Delete reminder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(await stored(), isEmpty);
      expect(find.text('No reminders yet'), findsOneWidget);
    });
  });
}
