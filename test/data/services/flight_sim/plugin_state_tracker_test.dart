import 'package:flightsim_aide/data/services/flight_sim/model/raw_hello.dart';
import 'package:flightsim_aide/data/services/flight_sim/plugin_state.dart';
import 'package:flightsim_aide/data/services/flight_sim/plugin_state_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../testing/fakes/services/manual_clock.dart';

void main() {
  late ManualClock clock;
  late PluginStateTracker tracker;

  RawHello hello({int version = 1, int port = 18086}) => RawHello(
    protocolVersion: version,
    port: port,
    streamPath: '/v1/stream',
    runId: 'run-1',
  );

  setUp(() {
    clock = ManualClock();
    tracker = PluginStateTracker(clock: clock);
  });

  group('plugin state', () {
    test('starts unknown, also before the sim ip is known', () {
      expect(tracker.state, const PluginStateUnknown());
      clock.advance(const Duration(seconds: 10));
      expect(tracker.state, const PluginStateUnknown());
    });

    test('no hello for 2 s gives notDetected', () {
      tracker.simKnown();
      clock.advance(const Duration(milliseconds: 1900));
      expect(tracker.state, const PluginStateUnknown());
      clock.advance(const Duration(milliseconds: 100));
      expect(tracker.state, const PluginStateNotDetected());
    });

    test('a probe round of no-route failures flags notDetected', () {
      tracker.simKnown();
      tracker.probeRound(noRoute: true);
      clock.advance(const Duration(seconds: 2));
      expect(tracker.state, const PluginStateNotDetected(noRoute: true));
      tracker.probeRound(noRoute: false);
      expect(tracker.state, const PluginStateNotDetected());
    });

    test('a hello and a reset clear the no-route flag', () {
      tracker.simKnown();
      tracker.probeRound(noRoute: true);
      tracker.onHello(18086, hello());
      tracker.lostPlugin();
      clock.advance(const Duration(seconds: 2));
      expect(tracker.state, const PluginStateNotDetected());
      tracker.probeRound(noRoute: true);
      tracker.reset();
      tracker.simKnown();
      clock.advance(const Duration(seconds: 2));
      expect(tracker.state, const PluginStateNotDetected());
    });

    test('hello with version 2 gives versionMismatch with both numbers', () {
      tracker.simKnown();
      tracker.onHello(18086, hello(version: 2));
      expect(
        tracker.state,
        const PluginStateVersionMismatch(found: 2, required: 1),
      );
    });

    test('valid hello gives ready with the port', () {
      tracker.simKnown();
      tracker.onHello(18086, hello());
      expect(tracker.state, const PluginStateReady(18086));
    });

    test('plugin appearing later flips notDetected to ready', () {
      tracker.simKnown();
      clock.advance(const Duration(seconds: 5));
      expect(tracker.state, const PluginStateNotDetected());
      tracker.onHello(18086, hello());
      expect(tracker.state, const PluginStateReady(18086));
    });

    test('hello on a later port of the range is found', () {
      tracker.simKnown();
      tracker.onHello(18090, hello(port: 18090));
      expect(tracker.state, const PluginStateReady(18090));
    });

    test('the latest hello wins', () {
      tracker.simKnown();
      tracker.onHello(18086, hello(version: 2));
      tracker.onHello(18087, hello(port: 18087));
      expect(tracker.state, const PluginStateReady(18087));
    });

    test('reset forgets the plugin and the window', () {
      tracker.simKnown();
      tracker.onHello(18086, hello());
      tracker.reset();
      expect(tracker.state, const PluginStateUnknown());
      clock.advance(const Duration(seconds: 10));
      expect(tracker.state, const PluginStateUnknown());
    });

    test('lostPlugin returns a ready plugin to unknown then notDetected', () {
      tracker.simKnown();
      tracker.onHello(18086, hello());
      tracker.lostPlugin();
      expect(tracker.state, const PluginStateUnknown());
      clock.advance(const Duration(seconds: 2));
      expect(tracker.state, const PluginStateNotDetected());
    });
  });

  group('staleness', () {
    test('a stream that has not started is not stale', () {
      clock.advance(const Duration(seconds: 30));
      expect(tracker.isStale, isFalse);
    });

    test('3 s without a frame marks the stream stale', () {
      tracker.onFrame();
      clock.advance(const Duration(milliseconds: 2999));
      expect(tracker.isStale, isFalse);
      clock.advance(const Duration(milliseconds: 1));
      expect(tracker.isStale, isTrue);
    });

    test('heartbeat keeps it fresh', () {
      tracker.onFrame();
      for (var i = 0; i < 10; i++) {
        clock.advance(const Duration(seconds: 1));
        tracker.onFrame();
      }
      expect(tracker.isStale, isFalse);
    });

    test('a frame after staleness clears it', () {
      tracker.onFrame();
      clock.advance(const Duration(seconds: 4));
      expect(tracker.isStale, isTrue);
      tracker.onFrame();
      expect(tracker.isStale, isFalse);
    });

    test('streamClosed stops the stale judgement', () {
      tracker.onFrame();
      tracker.streamClosed();
      clock.advance(const Duration(seconds: 10));
      expect(tracker.isStale, isFalse);
    });

    test('uses an injected clock, no real sleeps', () {
      final started = DateTime.now();
      tracker.onFrame();
      clock.advance(const Duration(hours: 1));
      expect(tracker.isStale, isTrue);
      expect(DateTime.now().difference(started).inSeconds, lessThan(2));
    });
  });
}
