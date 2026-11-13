import 'dart:async';
import 'dart:io';

import 'package:flightsim_aide/data/services/flight_sim/companion_plugin_service.dart';
import 'package:flightsim_aide/data/services/flight_sim/flight_sim_connection_service.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/plugin_endpoint.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/raw_signal_message.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/signal_spec.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/sim_endpoint.dart';
import 'package:flightsim_aide/data/services/flight_sim/plugin_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../testing/fakes/plugin/fake_companion_plugin_server.dart';
import '../../../../testing/fakes/services/manual_clock.dart';

// AC-10: version mismatch is reported and probing stops

const _sim = SimEndpoint(host: '127.0.0.1', name: 'TESTSIM');

/// Polls (in real time) until [condition] holds.
Future<void> waitFor(
  bool Function() condition, {
  String what = 'condition',
  Duration timeout = const Duration(seconds: 5),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<int> freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void main() {
  late FakeCompanionPluginServer server;
  late ManualClock clock;
  late HttpCompanionPluginService companion;
  late List<int> ports;
  late List<RawSignalMessage> messages;
  late List<Uri> wsAttempts;
  late List<DateTime> wsAttemptTimes;
  late int failWsAttempts;
  late FlightSimConnectionService service;
  final subscriptions = <StreamSubscription<Object?>>[];

  FlightSimConnectionService build({List<SignalSpec>? signals}) {
    final s = FlightSimConnectionService(
      companion: companion,
      clock: clock,
      ports: ports,
      signalSpecs: signals ?? defaultSignals,
      probeTimeout: const Duration(seconds: 3),
      connectWebSocket: (uri) {
        wsAttempts.add(uri);
        wsAttemptTimes.add(clock.now());
        if (failWsAttempts > 0) {
          failWsAttempts--;
          throw const SocketException('refused');
        }
        return WebSocket.connect(uri.toString());
      },
    );
    subscriptions.add(s.signals.listen(messages.add));
    return s;
  }

  setUp(() async {
    server = await FakeCompanionPluginServer.start();
    clock = ManualClock();
    companion = HttpCompanionPluginService(
      client: http.Client(),
      timeout: const Duration(seconds: 3),
    );
    ports = [await freePort(), server.port, await freePort()];
    messages = [];
    wsAttempts = [];
    wsAttemptTimes = [];
    failWsAttempts = 0;
    service = build();
  });

  tearDown(() async {
    for (final s in subscriptions) {
      await s.cancel();
    }
    subscriptions.clear();
    await service.dispose();
    companion.dispose();
    await server.close();
  });

  Future<void> connected() => waitFor(
    () => service.isStreamConnected && server.stream.subscriptionCount == 2,
    what: 'a connected stream',
  );

  group('handshake and subscribe', () {
    test('tries the next address when the first does not answer', () async {
      await service.connect(
        const SimEndpoint(host: '127.0.0.2', alternateHosts: ['127.0.0.1']),
      );
      await waitFor(
        () => service.pluginState == PluginStateReady(server.port),
        what: 'ready on the second address',
      );
      await connected();
      expect(service.pluginEndpoint?.host, '127.0.0.1');
      expect(wsAttempts.single.host, '127.0.0.1');
    });

    test('peekHello answers with the hello and does not connect', () async {
      server.os = 'macos';
      final hello = await service.peekHello(_sim);
      expect(hello?.os, 'macos');
      expect(hello?.port, server.port);
      expect(service.pluginEndpoint, isNull);
      expect(service.pluginState, const PluginStateUnknown());
      expect(service.isStreamConnected, isFalse);
      expect(wsAttempts, isEmpty);
    });

    test('peekHello tries the next address', () async {
      final hello = await service.peekHello(
        const SimEndpoint(host: '127.0.0.2', alternateHosts: ['127.0.0.1']),
      );
      expect(hello?.port, server.port);
    });

    test('peekHello gives null when nothing answers', () async {
      service = build();
      ports
        ..clear()
        ..add(await freePort());
      expect(await service.peekHello(_sim), isNull);
    });

    test('probes the range and takes the first valid hello', () async {
      await service.connect(_sim);
      await waitFor(
        () => service.pluginState == PluginStateReady(server.port),
        what: 'ready',
      );
      expect(
        service.pluginEndpoint,
        PluginEndpoint(host: '127.0.0.1', port: server.port),
      );
    });

    test('remembers the working port', () async {
      await service.connect(_sim);
      await connected();
      await server.dropStreamConnections();
      await waitFor(() => !service.isStreamConnected, what: 'closed');
      clock.advance(const Duration(seconds: 1));
      await waitFor(() => wsAttempts.length == 2, what: 'a second attempt');
      expect(wsAttempts.every((u) => u.port == server.port), isTrue);
      expect(service.pluginEndpoint?.port, server.port);
    });

    test('subscribes once per signal', () async {
      await service.connect(_sim);
      await connected();
      expect(server.stream.subscriptionCount, 2);
      expect(server.stream.clientCount, 1);
    });

    test('values reach the stream as raw messages', () async {
      await service.connect(_sim);
      await waitFor(
        () =>
            messages.any((m) => m.name == onGroundSignal && m.value == 1) &&
            messages.any(
              (m) => m.name == aircraftGenerationSignal && m.value == 12,
            ),
        what: 'both signals',
      );
      final onGround = messages.firstWhere((m) => m.name == onGroundSignal);
      expect(onGround.sampleTime, greaterThan(0));
    });

    test('a generation change arrives as a new message', () async {
      await service.connect(_sim);
      await connected();
      server.generation = 13;
      await waitFor(
        () => messages.any(
          (m) => m.name == aircraftGenerationSignal && m.value == 13,
        ),
        what: 'generation 13',
      );
    });

    test('unknown_name marks the signal unavailable', () async {
      await service.dispose();
      service = build(
        signals: const [
          SignalSpec(aircraftGenerationSignal, 1),
          SignalSpec('sim/does/not/exist', 2),
        ],
      );
      final unavailable = <String>[];
      subscriptions.add(service.unavailableSignals.listen(unavailable.add));
      await service.connect(_sim);
      await waitFor(
        () => unavailable.contains('sim/does/not/exist'),
        what: 'unavailable',
      );
      expect(unavailable, ['sim/does/not/exist']);
      expect(service.isStreamConnected, isTrue);
    });

    test('disconnect closes the WebSocket', () async {
      await service.connect(_sim);
      await connected();
      await service.disconnect();
      await waitFor(() => server.stream.clientCount == 0, what: 'closed');
      expect(service.isStreamConnected, isFalse);
      expect(clock.pendingTimers, 0);
    });
  });

  group('plugin state', () {
    test(
      'no hello answer gives notDetected after 2 s and probing continues',
      () async {
        ports.replaceRange(0, ports.length, [await freePort()]);
        final states = <PluginState>[];
        subscriptions.add(service.pluginStates.listen(states.add));
        await service.connect(_sim);
        expect(service.pluginState, const PluginStateUnknown());
        clock.advance(const Duration(seconds: 2));
        await waitFor(
          () => service.pluginState == const PluginStateNotDetected(),
          what: 'notDetected',
        );
        expect(states.last, const PluginStateNotDetected());
        await waitFor(() => clock.pendingTimers > 0, what: 'the next probe');
      },
    );

    test('every probe failing with errno 65 flags notDetected', () async {
      await service.dispose();
      final denied = HttpCompanionPluginService(
        client: _NoRouteClient(),
        timeout: const Duration(seconds: 3),
      );
      service = FlightSimConnectionService(
        companion: denied,
        clock: clock,
        ports: ports,
        signalSpecs: defaultSignals,
        probeTimeout: const Duration(seconds: 3),
      );
      await service.connect(_sim);
      clock.advance(const Duration(seconds: 2));
      await waitFor(
        () =>
            service.pluginState == const PluginStateNotDetected(noRoute: true),
        what: 'notDetected with noRoute',
      );
      denied.dispose();
    });

    test('a plugin that appears later is found by the next probe', () async {
      final late = await freePort();
      ports.replaceRange(0, ports.length, [late]);
      await service.connect(_sim);
      clock.advance(const Duration(seconds: 2));
      await waitFor(
        () => service.pluginState == const PluginStateNotDetected(),
        what: 'notDetected',
      );
      await waitFor(() => clock.pendingTimers > 0, what: 'the next probe');
      ports.add(server.port);
      clock.advance(const Duration(seconds: 5));
      await waitFor(
        () => service.pluginState == PluginStateReady(server.port),
        what: 'ready',
      );
    });

    test('a version mismatch is reported and probing stops', () async {
      server.protocolVersion = 2;
      await service.connect(_sim);
      await waitFor(
        () =>
            service.pluginState ==
            const PluginStateVersionMismatch(found: 2, required: 1),
        what: 'mismatch',
      );
      expect(server.stream.clientCount, 0);
      expect(clock.pendingTimers, 0);
    });
  });

  group('reconnect', () {
    test(
      'closed connection reconnects after 1 s, 2 s, 5 s (fake clock)',
      () async {
        failWsAttempts = 4;
        final start = clock.now();
        await service.connect(_sim);
        expect(wsAttempts.length, 1);
        clock.advance(const Duration(milliseconds: 999));
        await pumpEventQueue();
        expect(wsAttempts.length, 1);
        clock.advance(const Duration(milliseconds: 1));
        await waitFor(() => wsAttempts.length == 2, what: 'attempt 2');
        clock.advance(const Duration(seconds: 2));
        await waitFor(() => wsAttempts.length == 3, what: 'attempt 3');
        clock.advance(const Duration(seconds: 5));
        await waitFor(() => wsAttempts.length == 4, what: 'attempt 4');
        clock.advance(const Duration(seconds: 5));
        await waitFor(() => wsAttempts.length == 5, what: 'attempt 5');
        expect(
          [for (final t in wsAttemptTimes) t.difference(start).inMilliseconds],
          [0, 1000, 3000, 8000, 13000],
        );
        await connected();
      },
    );

    test('resubscribes after reconnect', () async {
      await service.connect(_sim);
      await connected();
      await server.dropStreamConnections();
      await waitFor(() => !service.isStreamConnected, what: 'closed');
      clock.advance(const Duration(seconds: 1));
      await connected();
      expect(server.stream.clientCount, 1);
    });

    test('3 s of silence marks stale and a frame clears it', () async {
      await service.connect(_sim);
      await connected();
      await waitFor(() => messages.isNotEmpty, what: 'first values');
      server.silence();
      clock.advance(const Duration(seconds: 3));
      await waitFor(() => !service.isStreamConnected, what: 'stale');
      server.stream.silenced = false;
      clock.advance(const Duration(seconds: 1));
      await connected();
    });

    test('heartbeat keeps the stream fresh', () async {
      await service.connect(_sim);
      await connected();
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        clock.advance(const Duration(seconds: 2));
        await pumpEventQueue();
        expect(service.isStreamConnected, isTrue, reason: 'round $i');
      }
      expect(wsAttempts.length, 1);
    });

    test('reconnect leaves one active subscription per signal', () async {
      await service.connect(_sim);
      await connected();
      for (var i = 0; i < 3; i++) {
        await server.dropStreamConnections();
        await waitFor(() => !service.isStreamConnected, what: 'closed $i');
        clock.advance(const Duration(seconds: 1));
        await connected();
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.stream.clientCount, 1);
      expect(server.stream.subscriptionCount, 2);
    });

    test('server restart on a new port is found by re-probing', () async {
      await service.connect(_sim);
      await connected();
      final oldPort = server.port;
      await server.restart();
      ports.add(server.port);
      await waitFor(() => !service.isStreamConnected, what: 'closed');
      clock.advance(const Duration(seconds: 1));
      await connected();
      expect(service.pluginEndpoint?.port, server.port);
      expect(server.port, isNot(oldPort));
    });
  });

  group('watched signals (5.11)', () {
    const speed = 'sim/flightmodel/position/indicated_airspeed';
    const throttle = 'sim/cockpit2/engine/actuators/throttle_ratio[1]';

    test('the limit is the plugin 128 less the fixed signals', () {
      expect(service.maxWatched, 126);
    });

    test('a watched name is subscribed and its values arrive', () async {
      await service.connect(_sim);
      await connected();
      service.watchSignals({speed: 5, throttle: 5});
      await waitFor(
        () =>
            messages.any((m) => m.name == speed && m.value == 77.5) &&
            messages.any((m) => m.name == throttle && m.value == 0.5),
        what: 'watched values',
      );
      expect(server.stream.subscriptionCount, 4);
    });

    test('a name watched before the connection is subscribed on it', () async {
      service.watchSignals({speed: 5});
      await service.connect(_sim);
      await waitFor(
        () => messages.any((m) => m.name == speed),
        what: 'watched value',
      );
    });

    test('a name dropped from the set is unsubscribed', () async {
      await service.connect(_sim);
      await connected();
      service.watchSignals({speed: 5, throttle: 5});
      await waitFor(
        () => server.stream.subscriptionCount == 4,
        what: 'four subscriptions',
      );
      service.watchSignals({speed: 5});
      await waitFor(
        () => server.stream.subscriptionCount == 3,
        what: 'three subscriptions',
      );
    });

    test('a changed rate keeps the connection', () async {
      await service.connect(_sim);
      await connected();
      service.watchSignals({speed: 5});
      await waitFor(
        () => server.stream.subscriptionCount == 3,
        what: 'three subscriptions',
      );
      service.watchSignals({speed: 20});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.stream.subscriptionCount, 3);
      expect(server.stream.clientCount, 1);
      expect(service.isStreamConnected, isTrue);
    });

    test('an unknown or unsupported name is reported once', () async {
      final unavailable = <String>[];
      subscriptions.add(service.unavailableSignals.listen(unavailable.add));
      await service.connect(_sim);
      await connected();
      service.watchSignals({
        'sim/does/not/exist': 5,
        'sim/aircraft/view/acf_ICAO': 5,
      });
      await waitFor(() => unavailable.length == 2, what: 'two reports');
      expect(
        unavailable,
        unorderedEquals(['sim/does/not/exist', 'sim/aircraft/view/acf_ICAO']),
      );
    });

    test('names past the limit are ignored, not sent', () async {
      await service.connect(_sim);
      await connected();
      service.watchSignals({
        for (var i = 0; i < 130; i++)
          'sim/cockpit2/engine/actuators/throttle_ratio[${i * 2}]': 5,
      });
      await waitFor(
        () => server.stream.subscriptionCount == 128,
        what: '128 subscriptions',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.stream.subscriptionCount, 128);
    });

    test('consecutive elements share one range subscription', () async {
      await service.connect(_sim);
      await connected();
      service.watchSignals({
        'sim/cockpit2/engine/actuators/throttle_ratio[0]': 5,
        'sim/cockpit2/engine/actuators/throttle_ratio[1]': 5,
        'sim/cockpit2/engine/actuators/throttle_ratio[2]': 5,
      });
      await waitFor(
        () =>
            messages.any(
              (m) =>
                  m.name == 'sim/cockpit2/engine/actuators/throttle_ratio[2]' &&
                  m.value == 0.75,
            ) &&
            messages.any(
              (m) =>
                  m.name == 'sim/cockpit2/engine/actuators/throttle_ratio[0]' &&
                  m.value == 0.25,
            ),
        what: 'element values from one range',
      );
      // Two fixed signals plus one range.
      expect(server.stream.subscriptionCount, 3);
    });

    test('an element past the end of the array reads as no value', () async {
      await service.connect(_sim);
      await connected();
      const base = 'sim/cockpit2/engine/actuators/throttle_ratio';
      service.watchSignals({for (var i = 2; i <= 5; i++) '$base[$i]': 5});
      await waitFor(
        () => messages.any((m) => m.name == '$base[5]'),
        what: 'values for all four',
      );
      num? latest(String name) =>
          messages.lastWhere((m) => m.name == name).value;
      expect(latest('$base[2]'), 0.75);
      expect(latest('$base[3]'), 1);
      expect(latest('$base[4]'), isNull);
      expect(latest('$base[5]'), isNull);
    });

    test('elements at different rates or with a gap stay separate', () async {
      await service.connect(_sim);
      await connected();
      const base = 'sim/cockpit2/engine/actuators/throttle_ratio';
      service.watchSignals({'$base[0]': 5, '$base[1]': 10, '$base[3]': 5});
      await waitFor(
        () => server.stream.subscriptionCount == 5,
        what: 'three separate subscriptions',
      );
    });

    test('a plugin without ranges gets the elements one by one', () async {
      server.stream.supportRanges = false;
      await service.connect(_sim);
      await connected();
      const base = 'sim/cockpit2/engine/actuators/throttle_ratio';
      service.watchSignals({'$base[0]': 5, '$base[1]': 5, '$base[2]': 5});
      await waitFor(
        () =>
            server.stream.subscriptionCount == 5 &&
            messages.any((m) => m.name == '$base[2]' && m.value == 0.75),
        what: 'single-element fallback',
      );
    });

    test('a range on an unknown name reports every element', () async {
      final unavailable = <String>[];
      subscriptions.add(service.unavailableSignals.listen(unavailable.add));
      await service.connect(_sim);
      await connected();
      service.watchSignals({'no/such[0]': 5, 'no/such[1]': 5});
      await waitFor(() => unavailable.length == 2, what: 'two reports');
      expect(unavailable, unorderedEquals(['no/such[0]', 'no/such[1]']));
    });

    test('the limit counts range subscriptions, not element names', () async {
      await service.connect(_sim);
      await connected();
      const base = 'sim/cockpit2/engine/actuators/throttle_ratio';
      final names = [for (var i = 0; i < 200; i++) '$base[$i]'];
      expect(service.fit(names), names);
      service.watchSignals({for (final n in names) n: 5});
      // Two fixed signals and two ranges (128 + 72 elements).
      await waitFor(
        () => server.stream.subscriptionCount == 4,
        what: 'two range subscriptions',
      );
      await waitFor(
        () => messages.any((m) => m.name == '$base[1]' && m.value == 0.5),
        what: 'a value from the first range',
      );
    });

    test('fit keeps the names whose subscriptions fit and drops the rest', () {
      // Scattered elements cannot share a range: one subscription each.
      const base = 'sim/cockpit2/engine/actuators/throttle_ratio';
      final names = [for (var i = 0; i < 130; i++) '$base[${i * 2}]'];
      expect(service.fit(names), names.take(126).toList());
    });

    test('the set is sent again after a reconnect', () async {
      await service.connect(_sim);
      await connected();
      service.watchSignals({speed: 5});
      await waitFor(
        () => server.stream.subscriptionCount == 3,
        what: 'three subscriptions',
      );
      await server.dropStreamConnections();
      await waitFor(() => !service.isStreamConnected, what: 'closed');
      messages.clear();
      clock.advance(const Duration(seconds: 1));
      await waitFor(
        () =>
            service.isStreamConnected &&
            server.stream.subscriptionCount == 3 &&
            messages.any((m) => m.name == speed),
        what: 'resubscribed',
      );
    });
  });

  group('lifecycle', () {
    test('pause closes the WebSocket', () async {
      await service.connect(_sim);
      await connected();
      await service.pause();
      await waitFor(() => server.stream.clientCount == 0, what: 'closed');
      expect(service.isStreamConnected, isFalse);
    });

    test('resume resubscribes', () async {
      await service.connect(_sim);
      await connected();
      await service.pause();
      await waitFor(() => server.stream.clientCount == 0, what: 'closed');
      await service.resume();
      await connected();
      expect(server.stream.clientCount, 1);
    });

    test('pause twice is harmless', () async {
      await service.connect(_sim);
      await connected();
      await service.pause();
      await service.pause();
      await service.resume();
      await service.resume();
      await connected();
      expect(server.stream.clientCount, 1);
    });

    test('no timers remain after pause', () async {
      failWsAttempts = 1;
      await service.connect(_sim);
      expect(clock.pendingTimers, greaterThan(0));
      await service.pause();
      expect(clock.pendingTimers, 0);
    });

    test('resume without a prior connect does nothing', () async {
      await service.resume();
      expect(wsAttempts, isEmpty);
    });
  });
}

/// Fails every request the way iOS does while Local Network is denied.
class _NoRouteClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => Future.error(
    const SocketException(
      'Connection failed',
      osError: OSError('No route to host', 65),
    ),
  );
}
