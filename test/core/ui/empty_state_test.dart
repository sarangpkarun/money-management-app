import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/ui/empty_state.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child, {double scale = 1}) =>
      tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: child),
          ),
        ),
      );

  testWidgets('shows the icon, title and hint', (tester) async {
    await pump(
      tester,
      const EmptyState(
        icon: Icons.people_outline,
        title: 'No people yet',
        hint: 'Add the people you lend to.',
      ),
    );
    expect(find.byIcon(Icons.people_outline), findsOneWidget);
    expect(find.text('No people yet'), findsOneWidget);
    expect(find.text('Add the people you lend to.'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('the buttons call their actions', (tester) async {
    var added = 0;
    var imported = 0;
    await pump(
      tester,
      EmptyState(
        icon: Icons.people_outline,
        title: 'T',
        actionLabel: 'Add person',
        onAction: () => added++,
        secondaryLabel: 'Import',
        onSecondary: () => imported++,
      ),
    );
    await tester.tap(find.text('Add person'));
    await tester.tap(find.text('Import'));
    expect([added, imported], [1, 1]);
  });

  testWidgets('a label without an action shows no button', (tester) async {
    await pump(
      tester,
      const EmptyState(icon: Icons.alarm, title: 'T', actionLabel: 'Go'),
    );
    expect(find.text('Go'), findsNothing);
  });

  testWidgets('the decorative icon is hidden from screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const EmptyState(icon: Icons.alarm, title: 'Nothing here'),
    );
    expect(find.bySemanticsLabel('Nothing here'), findsOneWidget);
    expect(tester.getSemantics(find.byType(Icon)).label, isEmpty);
    handle.dispose();
  });

  testWidgets('with huge text it scrolls instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(
      tester,
      EmptyState(
        icon: Icons.alarm,
        title: 'A fairly long title that wraps over several lines',
        hint:
            'And a hint that is long enough to need quite a few lines at '
            'this size so the column grows beyond the screen.',
        actionLabel: 'Add your first entry',
        onAction: () {},
        secondaryLabel: 'Import from contacts',
        onSecondary: () {},
      ),
      scale: 3,
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Import from contacts'), 100);
    expect(find.text('Import from contacts'), findsOneWidget);
  });
}
