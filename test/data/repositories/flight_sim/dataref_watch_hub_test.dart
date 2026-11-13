import 'package:flightsim_aide/data/repositories/flight_sim/dataref_watch_hub.dart';
import 'package:flightsim_aide/domain/models/flight_sim/dataref.dart';
import 'package:flightsim_aide/domain/models/flight_sim/dataref_value.dart';
import 'package:flightsim_aide/domain/models/settings/user_options.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../../testing/fakes/services/fake_flight_sim_service.dart';
import '../../../../testing/fakes/services/manual_clock.dart';

// AC-39: the stream rate option sets how often values arrive; changing it re-subscribes without dropping the link
// AC-41: each name is subscribed once, released after a delay, reported when unavailable, unknown when the link is down
// AC-45: past the subscription cap the first names fit and the rest stay manual with the notice

const _rpm = Dataref('a/rpm');
const _oil = Dataref('a/oil');
const _fuel = Dataref('a/fuel', 2);

void main() {
  late FakeFlightSimService service;
  late FakeSettingsRepository settings;
  late ManualClock clock;
  late DatarefWatchHub hub;

  setUp(() {
    service = FakeFlightSimService();
    settings = FakeSettingsRepository();
    clock = ManualClock();
    hub = DatarefWatchHub(
      source: service,
      settings: settings,
      clock: clock,
      releaseDelay: const Duration(seconds: 2),
    );
    service.setStreamConnected(true);
  });

  tearDown(() => hub.dispose());

  void send(String name, num? v) => service.emit(name, v);

  group('subscriptions (5.6)', () {
    test('a watch subscribes its names at the stream rate', () {
      hub.watch([_rpm, _fuel]);
      expect(service.watchCalls.last, {'a/rpm': 5, 'a/fuel[2]': 5});
    });

    test('two watches of one name subscribe it once', () {
      hub.watch([_rpm]);
      hub.watch([_rpm, _oil]);
      expect(service.watchCalls.last, {'a/rpm': 5, 'a/oil': 5});
      expect(hub.subscribedNames, ['a/rpm', 'a/oil']);
    });

    test('a name stays until its last watch is released, plus the delay', () {
      final a = hub.watch([_rpm]);
      final b = hub.watch([_rpm, _oil]);
      a.release();
      clock.advance(const Duration(seconds: 5));
      expect(service.watchCalls.last.keys, containsAll(['a/rpm', 'a/oil']));
      b.release();
      clock.advance(const Duration(seconds: 1));
      expect(service.watchCalls.last.keys, containsAll(['a/rpm', 'a/oil']));
      clock.advance(const Duration(seconds: 2));
      expect(service.watchCalls.last, isEmpty);
    });

    test('watching again inside the delay keeps the subscription', () {
      hub.watch([_rpm]).release();
      final calls = service.watchCalls.length;
      clock.advance(const Duration(seconds: 1));
      hub.watch([_rpm]);
      clock.advance(const Duration(seconds: 5));
      expect(service.watchCalls.length, calls);
      expect(hub.subscribedNames, ['a/rpm']);
    });

    test('release twice is harmless', () {
      final w = hub.watch([_rpm]);
      w.release();
      w.release();
      clock.advance(const Duration(seconds: 3));
      expect(hub.subscribedNames, isEmpty);
    });
  });

  group('values and throttling (5.4, 5.7)', () {
    test('current is unknown before anything arrives, never zero', () {
      final w = hub.watch([_rpm]);
      expect(w.current[_rpm], const DatarefValue.unknown());
    });

    test('a batch carries the latest value once per tick', () async {
      final w = hub.watch([_rpm, _oil]);
      final batches = <Map<Dataref, DatarefValue>>[];
      w.batches.listen(batches.add);
      send('a/rpm', 1000);
      send('a/rpm', 1100);
      send('a/oil', 40);
      expect(batches, isEmpty);
      clock.advance(const Duration(milliseconds: 200));
      await Future<void>.delayed(Duration.zero);
      expect(batches, hasLength(1));
      expect(batches.single[_rpm]!.number, 1100);
      expect(batches.single[_oil]!.number, 40);
      expect(w.current[_rpm]!.number, 1100);
    });

    test('an unchanged value is not sent again', () async {
      final w = hub.watch([_rpm]);
      final batches = <Map<Dataref, DatarefValue>>[];
      w.batches.listen(batches.add);
      send('a/rpm', 5);
      clock.advance(const Duration(milliseconds: 200));
      send('a/rpm', 5);
      clock.advance(const Duration(milliseconds: 200));
      await Future<void>.delayed(Duration.zero);
      expect(batches, hasLength(1));
    });

    test('a batch holds only the names the watch asked for', () async {
      final a = hub.watch([_rpm]);
      final b = hub.watch([_oil]);
      final seenA = <Map<Dataref, DatarefValue>>[];
      final seenB = <Map<Dataref, DatarefValue>>[];
      a.batches.listen(seenA.add);
      b.batches.listen(seenB.add);
      send('a/oil', 3);
      clock.advance(const Duration(milliseconds: 200));
      await Future<void>.delayed(Duration.zero);
      expect(seenA, isEmpty);
      expect(seenB.single.keys, [_oil]);
    });

    test('a null value (past the end) is unknown, not zero', () async {
      final w = hub.watch([_fuel]);
      send('a/fuel[2]', null);
      clock.advance(const Duration(milliseconds: 200));
      expect(w.current[_fuel]!.isKnown, isFalse);
      expect(w.unavailable, isEmpty);
    });

    test('values for names nobody watches are ignored', () {
      final w = hub.watch([_rpm]);
      send('a/other', 1);
      expect(w.current.keys, [_rpm]);
    });
  });

  group('rate (5.7, 5.8)', () {
    test('a higher rate ticks faster', () async {
      await settings.update((o) => o.set(UserOptions.streamRateHzOption, 20));
      await Future<void>.delayed(Duration.zero);
      final w = hub.watch([_rpm]);
      final batches = <Map<Dataref, DatarefValue>>[];
      w.batches.listen(batches.add);
      send('a/rpm', 1);
      clock.advance(const Duration(milliseconds: 50));
      await Future<void>.delayed(Duration.zero);
      expect(batches, hasLength(1));
    });

    test(
      'changing the rate re-subscribes with the new rate, no drop',
      () async {
        hub.watch([_rpm]);
        expect(service.watchCalls.last, {'a/rpm': 5});
        await settings.update((o) => o.set(UserOptions.streamRateHzOption, 10));
        await Future<void>.delayed(Duration.zero);
        expect(service.watchCalls.last, {'a/rpm': 10});
        expect(service.disconnects, 0);
        expect(hub.rateHz, 10);
      },
    );

    test('an option change that is not the rate does nothing', () async {
      hub.watch([_rpm]);
      final calls = service.watchCalls.length;
      await settings.update((o) => o.set(UserOptions.autoModeOption, false));
      await Future<void>.delayed(Duration.zero);
      expect(service.watchCalls.length, calls);
    });
  });

  group('unavailable names (5.9)', () {
    test(
      'a name the plugin rejects is reported once and stays unknown',
      () async {
        final w = hub.watch([_rpm, _oil]);
        final changes = <Set<Dataref>>[];
        w.unavailableChanges.listen(changes.add);
        service.emitUnavailable('a/oil');
        service.emitUnavailable('a/oil');
        await Future<void>.delayed(Duration.zero);
        expect(w.unavailable, {_oil});
        expect(changes, [
          {_oil},
        ]);
        expect(w.current[_oil]!.isKnown, isFalse);
      },
    );

    test('past the limit the first names fit and the rest are unavailable', () {
      service.maxWatched = 2;
      final w = hub.watch([_rpm, _oil, _fuel]);
      expect(service.watchCalls.last.keys, ['a/rpm', 'a/oil']);
      expect(w.unavailable, {_fuel});
    });

    test('a reconnect forgets the rejection so it can be reported again', () {
      final w = hub.watch([_oil]);
      service.emitUnavailable('a/oil');
      expect(w.unavailable, {_oil});
      service.setStreamConnected(false);
      service.setStreamConnected(true);
      expect(w.unavailable, isEmpty);
    });
  });

  group('stale and lost link (5.10)', () {
    test('every value becomes unknown when the stream drops', () async {
      final w = hub.watch([_rpm, _oil]);
      final batches = <Map<Dataref, DatarefValue>>[];
      w.batches.listen(batches.add);
      send('a/rpm', 1);
      send('a/oil', 2);
      clock.advance(const Duration(milliseconds: 200));
      service.setStreamConnected(false);
      clock.advance(const Duration(milliseconds: 200));
      await Future<void>.delayed(Duration.zero);
      expect(batches, hasLength(2));
      expect(batches.last.values.every((v) => !v.isKnown), isTrue);
      expect(w.current.values.every((v) => !v.isKnown), isTrue);
    });

    test('values return when the stream does', () async {
      final w = hub.watch([_rpm]);
      send('a/rpm', 1);
      service.setStreamConnected(false);
      service.setStreamConnected(true);
      send('a/rpm', 1);
      expect(w.current[_rpm]!.number, 1);
    });
  });
}
