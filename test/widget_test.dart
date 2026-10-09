import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/main.dart';

void main() {
  test('app root is a stateful widget', () {
    expect(const MoneyManagerApp(), isA<StatefulWidget>());
  });
}
