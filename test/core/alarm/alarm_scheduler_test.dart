import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/core/alarm/alarm_plan.dart';
import 'package:money_manager/core/alarm/alarm_scheduler.dart';
import 'package:money_manager/core/models/reminder.dart';

import '../../support/fake_alarm_gateway.dart';

Reminder rem(
  String id,
  DateTime at, {
  RepeatRule repeat = const RepeatRule.none(),
  bool done = false,
  String title = 'T',
  int snooze = 10,
}) => Reminder(
  id: id,
  title: title,
  at: at,
  repeat: repeat,
  done: done,
  snoozeMinutes: snooze,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  final now = DateTime(2030, 1, 7, 12);
  late FakeAlarmGateway gw;
  late AlarmScheduler sched;

  setUp(() {
    gw = FakeAlarmGateway();
    sched = AlarmScheduler(gw);
  });

  test('the first sync schedules everything', () async {
    final r = await sched.sync([
      rem('a', DateTime(2030, 1, 8, 9)),
      rem('b', DateTime(2030, 1, 9, 9), repeat: const RepeatRule.daily()),
    ], now);
    expect(r.scheduled, 31); // 1 + 30
    expect(r.cancelled, 0);
    expect(gw.scheduled.length, 31);
  });

  test('syncing again changes nothing', () async {
    final rs = [rem('a', DateTime(2030, 1, 8, 9))];
    await sched.sync(rs, now);
    final calls = gw.scheduleCalls;
    final r = await sched.sync(rs, now);
    expect(r.scheduled, 0);
    expect(r.cancelled, 0);
    expect(gw.scheduleCalls, calls);
  });

  test('editing one reminder touches only its alarms', () async {
    final a = rem('a', DateTime(2030, 1, 8, 9));
    final b = rem('b', DateTime(2030, 1, 9, 9));
    await sched.sync([a, b], now);
    final before = gw.scheduleCalls;
    final r = await sched.sync([a, rem('b', DateTime(2030, 1, 9, 10))], now);
    expect(r.scheduled, 1);
    expect(gw.scheduleCalls, before + 1);
    final bAlarm = gw.scheduled.values.firstWhere(
      (x) => x.payload.reminderId == 'b',
    );
    expect(bAlarm.at, DateTime(2030, 1, 9, 10));
  });

  test('changing the title or snooze reschedules (payload changed)', () async {
    await sched.sync([rem('a', DateTime(2030, 1, 8, 9))], now);
    final r = await sched.sync([
      rem('a', DateTime(2030, 1, 8, 9), title: 'New', snooze: 5),
    ], now);
    expect(r.scheduled, 1);
    expect(gw.scheduled.values.single.payload.title, 'New');
    expect(gw.scheduled.values.single.payload.snoozeMinutes, 5);
  });

  test('deleting or finishing a reminder cancels its alarms', () async {
    final a = rem(
      'a',
      DateTime(2030, 1, 8, 9),
      repeat: const RepeatRule.daily(),
    );
    final b = rem('b', DateTime(2030, 1, 8, 9));
    await sched.sync([a, b], now);
    expect(gw.scheduled.length, 31);
    var r = await sched.sync([a], now); // b deleted
    expect(r.cancelled, 1);
    expect(gw.scheduled.length, 30);
    r = await sched.sync([rem('a', a.at, repeat: a.repeat, done: true)], now);
    expect(r.cancelled, 30);
    expect(gw.scheduled, isEmpty);
  });

  test('the repeat window slides forward as time passes', () async {
    final d = rem(
      'd',
      DateTime(2030, 1, 1, 9),
      repeat: const RepeatRule.daily(),
    );
    await sched.sync([d], now);
    final firstDay = gw.scheduled.values
        .map((a) => a.at)
        .reduce((x, y) => x.isBefore(y) ? x : y);
    expect(firstDay, DateTime(2030, 1, 8, 9));
    // Ten days later the first ten have fired (the system dropped them).
    final later = DateTime(2030, 1, 17, 12);
    gw.scheduled.removeWhere((_, a) => a.at.isBefore(later));
    final r = await sched.sync([d], later);
    expect(r.scheduled, greaterThan(0));
    expect(gw.scheduled.length, 30);
    expect(
      gw.scheduled.values
          .map((a) => a.at)
          .reduce((x, y) => x.isBefore(y) ? x : y),
      DateTime(2030, 1, 18, 9),
    );
  });

  test('other pending notifications are left alone', () async {
    gw.foreign[5] = 'something else';
    gw.foreign[6] = null;
    await sched.sync([rem('a', DateTime(2030, 1, 8, 9))], now);
    await sched.sync([], now);
    expect(gw.foreign.keys, containsAll([5, 6]));
  });

  test('a pending snooze survives while its reminder is active', () async {
    final a = rem(
      'a',
      DateTime(2030, 1, 8, 9),
      repeat: const RepeatRule.daily(),
    );
    await sched.sync([a], now);
    final snooze = snoozeAlarm(
      gw.scheduled.values.first.payload,
      DateTime(2030, 1, 8, 9, 1),
    );
    await gw.schedule(snooze);
    await sched.sync([a], now);
    expect(gw.scheduled.containsKey(snooze.id), isTrue);
    await sched.sync([rem('a', a.at, repeat: a.repeat, done: true)], now);
    expect(gw.scheduled.containsKey(snooze.id), isFalse);
    // and when the reminder is deleted outright
    await gw.schedule(snooze);
    await sched.sync([], now);
    expect(gw.scheduled.containsKey(snooze.id), isFalse);
  });

  test('without permission nothing is scheduled and it says so', () async {
    gw.allowed = false;
    final r = await sched.sync([rem('a', DateTime(2030, 1, 8, 9))], now);
    expect(r.blocked, isTrue);
    expect(r.scheduled, 0);
    expect(gw.scheduled, isEmpty);
    // Cancels still happen without permission.
    gw.allowed = true;
    await sched.sync([rem('a', DateTime(2030, 1, 8, 9))], now);
    gw.allowed = false;
    final r2 = await sched.sync([], now);
    expect(r2.cancelled, 1);
    expect(gw.scheduled, isEmpty);
  });

  test('once permission is granted the next sync schedules', () async {
    gw.allowed = false;
    final rs = [rem('a', DateTime(2030, 1, 8, 9))];
    await sched.sync(rs, now);
    gw.allowed = true;
    final r = await sched.sync(rs, now);
    expect(r.blocked, isFalse);
    expect(gw.scheduled.length, 1);
  });

  test('clear removes our alarms and nothing else', () async {
    gw.foreign[5] = 'x';
    await sched.sync([rem('a', DateTime(2030, 1, 8, 9))], now);
    await sched.clear();
    expect(gw.scheduled, isEmpty);
    expect(gw.foreign.keys, [5]);
  });

  test('ensurePermissions only asks when needed', () async {
    await sched.ensurePermissions();
    expect(gw.permissionRequests, 0);
    gw.allowed = false;
    final p = await sched.ensurePermissions();
    expect(gw.permissionRequests, 1);
    expect(p.ok, isFalse);
  });
}
