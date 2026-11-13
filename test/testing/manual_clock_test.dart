import 'package:flutter_test/flutter_test.dart';

import '../../testing/fakes/services/manual_clock.dart';

void main() {
  test('advance fires one-shot timers in order and moves now', () {
    final clock = ManualClock();
    final start = clock.now();
    final fired = <String>[];
    clock.timer(const Duration(seconds: 2), () => fired.add('b'));
    clock.timer(const Duration(seconds: 1), () => fired.add('a'));
    clock.advance(const Duration(milliseconds: 1500));
    expect(fired, ['a']);
    expect(clock.now(), start.add(const Duration(milliseconds: 1500)));
    clock.advance(const Duration(seconds: 1));
    expect(fired, ['a', 'b']);
    expect(clock.pendingTimers, 0);
  });

  test('periodic timers repeat and cancel', () {
    final clock = ManualClock();
    var count = 0;
    final timer = clock.periodic(const Duration(seconds: 1), (_) => count++);
    clock.advance(const Duration(milliseconds: 3500));
    expect(count, 3);
    timer.cancel();
    clock.advance(const Duration(seconds: 5));
    expect(count, 3);
    expect(clock.pendingTimers, 0);
  });

  test('a timer set inside a callback fires within the same advance', () {
    final clock = ManualClock();
    final fired = <int>[];
    clock.timer(const Duration(seconds: 1), () {
      fired.add(1);
      clock.timer(const Duration(seconds: 1), () => fired.add(2));
    });
    clock.advance(const Duration(seconds: 3));
    expect(fired, [1, 2]);
  });

  test('a cancelled timer never fires', () {
    final clock = ManualClock();
    var fired = false;
    clock.timer(const Duration(seconds: 1), () => fired = true).cancel();
    clock.advance(const Duration(seconds: 2));
    expect(fired, isFalse);
  });
}
