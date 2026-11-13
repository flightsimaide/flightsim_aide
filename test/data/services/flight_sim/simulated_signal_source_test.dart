import 'package:flightsim_aide/data/services/flight_sim/model/raw_signal_message.dart';
import 'package:flightsim_aide/data/services/flight_sim/simulated_signal_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../testing/fakes/services/manual_clock.dart';

// AC-41: the simulated source scripts values, drift, rejected names and a lost link without a sim

void main() {
  late ManualClock clock;
  late SimulatedSignalSource source;
  late List<RawSignalMessage> seen;

  setUp(() {
    clock = ManualClock();
    source = SimulatedSignalSource(clock: clock);
    seen = [];
    source.signals.listen(seen.add);
  });

  tearDown(() => source.dispose());

  double? last(String name) =>
      seen.lastWhere((m) => m.name == name).value?.toDouble();

  test('sends the set value of each watched name every period', () {
    source.setValue('a/x', 3);
    source.watchSignals({'a/x': 5});
    clock.advance(const Duration(milliseconds: 250));
    expect(seen.where((m) => m.name == 'a/x'), hasLength(2));
    expect(last('a/x'), 3);
  });

  test('a name with no value is sent as null, not zero', () {
    source.watchSignals({'a/x': 5});
    clock.advance(const Duration(milliseconds: 100));
    expect(seen.single.value, isNull);
  });

  test('a script changes values at its times', () {
    source.watchSignals({'a/x': 5});
    source.schedule(const Duration(seconds: 1), 'a/x', 1);
    source.schedule(const Duration(seconds: 3), 'a/x', 2);
    clock.advance(const Duration(milliseconds: 900));
    expect(last('a/x'), isNull);
    clock.advance(const Duration(seconds: 1));
    expect(last('a/x'), 1);
    clock.advance(const Duration(seconds: 2));
    expect(last('a/x'), 2);
  });

  test('drift moves a value in steps up to the target and stops', () {
    source.watchSignals({'a/x': 5});
    source.drift('a/x', from: 0, to: 25, step: 10);
    clock.advance(const Duration(milliseconds: 1100));
    expect(last('a/x'), 10);
    clock.advance(const Duration(seconds: 5));
    expect(last('a/x'), 25);
    clock.advance(const Duration(seconds: 1));
    expect(clock.pendingTimers, 1); // only the send tick is left
  });

  test('drift downwards works too', () {
    source.watchSignals({'a/x': 5});
    source.drift('a/x', from: 10, to: 0, step: 4);
    clock.advance(const Duration(seconds: 5));
    expect(last('a/x'), 0);
  });

  test('a rejected name is reported and never sent', () {
    final unavailable = <String>[];
    source.unavailableSignals.listen(unavailable.add);
    source.reject('a/bad');
    source.watchSignals({'a/bad': 5, 'a/x': 5});
    clock.advance(const Duration(seconds: 1));
    expect(unavailable, ['a/bad']);
    expect(seen.where((m) => m.name == 'a/bad'), isEmpty);
  });

  test('a lost link sends nothing and announces itself', () {
    final states = <bool>[];
    source.streamConnected.listen(states.add);
    source.watchSignals({'a/x': 5});
    source.setConnected(false);
    source.setConnected(false);
    clock.advance(const Duration(seconds: 1));
    expect(seen, isEmpty);
    source.setConnected(true);
    expect(states, [false, true]);
    expect(source.isStreamConnected, isTrue);
  });

  test('records each watched set', () {
    source.watchSignals({'a/x': 5});
    source.watchSignals({'a/x': 10, 'a/y': 10});
    expect(source.watchCalls.last, {'a/x': 10, 'a/y': 10});
  });
}
