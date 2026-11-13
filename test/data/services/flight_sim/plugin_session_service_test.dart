import 'dart:io';

import 'package:flightsim_aide/data/services/flight_sim/companion_plugin_service.dart';
import 'package:flightsim_aide/data/services/flight_sim/flight_sim_connection_service.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/plugin_endpoint.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/plugin_session.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/raw_aircraft_info.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/raw_checklist_response.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/raw_hello.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/sim_endpoint.dart';
import 'package:flightsim_aide/data/services/flight_sim/plugin_session_service.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../testing/fakes/plugin/fake_companion_plugin_server.dart';
import '../../../../testing/fakes/services/manual_clock.dart';

Future<void> waitFor(
  bool Function() condition, {
  String what = 'condition',
  Duration timeout = const Duration(seconds: 6),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Delegates to the real service and counts `getAircraft` calls.
class _CountingCompanion implements CompanionPluginService {
  _CountingCompanion(this.inner);
  final CompanionPluginService inner;
  int aircraftCalls = 0;

  @override
  Future<Result<RawHello>> getHello(String host, int port) =>
      inner.getHello(host, port);

  @override
  Future<Result<RawAircraftInfo>> getAircraft(PluginEndpoint endpoint) {
    aircraftCalls++;
    return inner.getAircraft(endpoint);
  }

  @override
  Future<Result<RawChecklistFetch>> getChecklist(
    PluginEndpoint endpoint, {
    String? ifNoneMatch,
  }) => inner.getChecklist(endpoint, ifNoneMatch: ifNoneMatch);
}

void main() {
  late FakeCompanionPluginServer server;
  late ManualClock clock;
  late HttpCompanionPluginService http_;
  late _CountingCompanion companion;
  late FlightSimConnectionService flightSim;
  late PluginSessionService sessions;
  late List<PluginSession?> emitted;
  late List<Object> errors;

  setUp(() async {
    server = await FakeCompanionPluginServer.start();
    clock = ManualClock();
    http_ = HttpCompanionPluginService(
      client: http.Client(),
      timeout: const Duration(milliseconds: 500),
    );
    companion = _CountingCompanion(http_);
    flightSim = FlightSimConnectionService(
      companion: companion,
      clock: clock,
      ports: [server.port],
      probeTimeout: const Duration(milliseconds: 500),
    );
    sessions = PluginSessionService(flightSim: flightSim, companion: companion);
    emitted = [];
    errors = [];
    sessions.changes.listen(emitted.add, onError: errors.add);
    sessions.start();
  });

  tearDown(() async {
    await sessions.dispose();
    await flightSim.dispose();
    http_.dispose();
    await server.close();
  });

  Future<void> up() async {
    await flightSim.connect(const SimEndpoint(host: '127.0.0.1'));
    await waitFor(() => sessions.current != null, what: 'a session');
  }

  test('plugin ready fetches the aircraft once', () async {
    await up();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(companion.aircraftCalls, 1);
    final session = sessions.current!;
    expect(session.host, '127.0.0.1');
    expect(session.port, server.port);
    expect(session.aircraft.icao, 'C172');
    expect(session.generation, 12);
    expect(emitted.length, 1);
  });

  test('generation change fetches once more and emits a new session', () async {
    await up();
    server.loadAircraft(
      icao: 'B738',
      description: 'Boeing 737-800',
      aircraftPath: 'Aircraft/B738/b738.acf',
    );
    await waitFor(
      () => sessions.current?.aircraft.icao == 'B738',
      what: 'B738',
    );
    expect(companion.aircraftCalls, 2);
    expect(sessions.current!.generation, 13);
    expect(emitted.map((s) => s?.aircraft.icao), ['C172', 'B738']);
  });

  test('unchanged generation never refetches', () async {
    await up();
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(companion.aircraftCalls, 1);
  });

  test('reload refetches without a generation change', () async {
    await up();
    server.editChecklist('sw_checklist:A\nsw_item:x|y\n');
    final result = await sessions.reload();
    expect(result.isOk, isTrue);
    expect(companion.aircraftCalls, 2);
    expect(result.valueOrNull!.aircraft.checklistSize, 27);
    expect(sessions.current!.generation, 12);
  });

  test('reload before the plugin is known is PluginUnreachable', () async {
    final result = await sessions.reload();
    expect(result.errorOrNull, isA<PluginUnreachable>());
    expect(companion.aircraftCalls, 0);
  });

  test('plugin disappearing emits null', () async {
    await up();
    await server.close();
    await waitFor(() => flightSim.isStreamConnected == false, what: 'closed');
    clock.advance(const Duration(seconds: 1));
    await waitFor(() => sessions.current == null, what: 'no session');
    expect(emitted.last, isNull);
  });

  test('fetch failure keeps the last session and reports the error', () async {
    await up();
    server.dropNext();
    server.loadAircraft(
      icao: 'B738',
      description: 'Boeing 737-800',
      aircraftPath: 'Aircraft/B738/b738.acf',
    );
    await waitFor(() => errors.isNotEmpty, what: 'an error');
    expect(errors.first, isA<PluginUnreachable>());
    expect(sessions.current?.aircraft.icao, anyOf('C172', 'B738'));
    // The next generation message retries and succeeds.
    await waitFor(
      () => sessions.current?.aircraft.icao == 'B738',
      what: 'B738',
    );
  });

  test('generation wrap from 2^31-1 to 0 counts as a change', () async {
    server.generation = 0x7fffffff;
    await up();
    expect(sessions.current!.generation, 0x7fffffff);
    server.loadAircraft(
      icao: 'X',
      description: 'x',
      aircraftPath: 'Aircraft/X/x.acf',
    );
    await waitFor(
      () => sessions.current?.generation == 0,
      what: 'generation 0',
    );
    expect(companion.aircraftCalls, 2);
  });

  test('getAircraft is called from nowhere else', () {
    final callers = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.readAsStringSync().contains('.getAircraft(')) {
        callers.add(entity.path.replaceAll(r'\', '/'));
      }
    }
    expect(callers, [
      'lib/data/services/flight_sim/plugin_session_service.dart',
    ]);
  });
}
