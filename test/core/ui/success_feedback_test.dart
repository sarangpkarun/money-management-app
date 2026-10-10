import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/ui/success_feedback.dart';

void main() {
  final burst = find.byKey(const ValueKey('success-burst'));
  late List<String> announced;

  setUp(() {
    announced = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
          message,
        ) async {
          final data = (message as Map)['data'];
          if (data is Map && data['message'] != null) {
            announced.add(data['message'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility,
          null,
        );
  });

  Future<void> pump(
    WidgetTester tester, {
    bool disableAnimations = false,
    bool big = false,
    VoidCallback? onUnderTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () =>
                        showSuccess(context, 'Payment saved', big: big),
                    child: const Text('go'),
                  ),
                  ElevatedButton(
                    onPressed: onUnderTap ?? () {},
                    child: const Text('under'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('appears with its message, then removes itself', (tester) async {
    await pump(tester);
    expect(burst, findsNothing);
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(burst, findsOneWidget);
    expect(find.text('Payment saved'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    expect(burst, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('it never takes taps', (tester) async {
    var taps = 0;
    await pump(tester, onUnderTap: () => taps++);
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(burst, findsOneWidget);
    await tester.tap(find.text('under'));
    expect(taps, 1);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the message is announced to screen readers', (tester) async {
    await pump(tester);
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(announced, ['Payment saved']);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
    'with animations turned off there is no burst, only the announcement',
    (tester) async {
      await pump(tester, disableAnimations: true);
      await tester.tap(find.text('go'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(burst, findsNothing);
      expect(announced, ['Payment saved']);
    },
  );

  testWidgets('the settled burst is bigger and stays longer', (tester) async {
    await pump(tester, big: true);
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 300));
    final bigIcon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
    expect(bigIcon.size, 96);
    // A normal burst is gone by 1 second; the big one is still up.
    await tester.pump(const Duration(milliseconds: 800));
    expect(burst, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(burst, findsNothing);
  });

  testWidgets('a normal burst is the smaller size', (tester) async {
    await pump(tester);
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<Icon>(find.byIcon(Icons.check_circle)).size, 64);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('two in a row both clean up', (tester) async {
    await pump(tester);
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(burst, findsNWidgets(2));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(burst, findsNothing);
  });

  test('durations', () {
    expect(burstDuration(big: false) < burstDuration(big: true), isTrue);
  });
}
