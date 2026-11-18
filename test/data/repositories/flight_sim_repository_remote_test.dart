import 'dart:io';

import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_remote.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/plugin_session.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/raw_aircraft_info.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/raw_hello.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/signal_spec.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/sim_endpoint.dart';
import 'package:flightsim_aide/data/services/flight_sim/plugin_state.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/domain/models/flight_sim/discovered_sim.dart';
import 'package:flightsim_aide/domain/models/flight_sim/simulator.dart';
import 'package:flightsim_aide/domain/models/flight_sim/switch_offer.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/services/fake_flight_sim_service.dart';
import '../../../testing/fakes/services/fake_network_status_service.dart';
import '../../../testing/fakes/services/fake_plugin_session_source.dart';
import '../../../testing/fakes/services/fake_sim_discovery_service.dart';
import '../../../testing/fakes/services/manual_clock.dart';

// AC-9: plugin not detected status
// AC-10: version mismatch status

const _settle = Duration(milliseconds: 1500);

RawAircraftInfo _info({
  int generation = 12,
  String icao = 'C172',
  bool checklist = true,
}) => RawAircraftInfo(
  protocolVersion: 1,
  generation: generation,
  icao: icao,
  description: 'Cessna Skyhawk 172SP',
  aircraftPath: 'Aircraft/Cessna/172.acf',
  checklistPath: checklist ? 'Aircraft/Cessna/clist.txt' : null,
  checklistModified: checklist ? 1761206400123 : null,
  checklistSize: checklist ? 267 : null,
);

PluginSession _session({int generation = 12, bool checklist = true}) =>
    PluginSession(
      host: '192.168.1.10',
      port: 18086,
      aircraft: _info(generation: generation, checklist: checklist),
    );

void main() {
  late ManualClock clock;
  late FakeFlightSimService flightSim;
  late FakePluginSessionSource sessions;
  late FakeNetworkStatusService network;
  late FakeSettingsRepository settings;
  late List<FakeSimDiscoveryService> discoveries;
  late FlightSimRepositoryRemote repo;
  late List<ConnectionStatus> statuses;

  FlightSimRepositoryRemote build() => FlightSimRepositoryRemote(
    flightSim: flightSim,
    sessions: sessions,
    network: network,
    settings: settings,
    clock: clock,
    simSettle: _settle,
    createDiscovery: (manualHost) {
      final d = FakeSimDiscoveryService(manualHost: manualHost);
      discoveries.add(d);
      return d;
    },
  );

  Future<void> settle() async {
    clock.advance(_settle);
    await pumpEventQueue();
  }

  Future<void> seeSim([
    String host = '192.168.1.10',
    String? name = 'SIM',
  ]) async {
    discoveries.last.see(SimEndpoint(host: host, name: name));
    await pumpEventQueue();
  }

  Future<void> connectSim() async {
    await seeSim();
    await settle();
  }

  Future<void> ready() async {
    flightSim.setPluginState(const PluginStateReady(18086));
    flightSim.setStreamConnected(true);
    await pumpEventQueue();
  }

  setUp(() async {
    clock = ManualClock();
    flightSim = FakeFlightSimService();
    sessions = FakePluginSessionSource();
    network = FakeNetworkStatusService();
    settings = FakeSettingsRepository();
    discoveries = [];
    repo = build();
    statuses = [];
    repo.connectionStatus.listen(statuses.add);
    await repo.start();
  });

  tearDown(() async {
    await repo.dispose();
    await sessions.dispose();
    await flightSim.dispose();
  });

  group('connection status', () {
    test('starts as searching', () {
      expect(repo.current, const ConnectionSearching());
    });

    test('beacon moves to connecting', () async {
      await connectSim();
      expect(repo.current, const ConnectionConnecting());
      expect(flightSim.connects, [
        const SimEndpoint(
          host: '192.168.1.10',
          name: 'SIM',
          simulator: Simulator.xplane,
        ),
      ]);
    });

    test('plugin ready moves to connected', () async {
      await connectSim();
      await ready();
      expect(repo.current, const ConnectionConnected());
    });

    test('a ready plugin without a stream is still connecting', () async {
      await connectSim();
      flightSim.setPluginState(const PluginStateReady(18086));
      await pumpEventQueue();
      expect(repo.current, const ConnectionConnecting());
    });

    test('no hello answer keeps waiting; it proves nothing', () async {
      await connectSim();
      flightSim.setPluginState(const PluginStateNotDetected());
      await pumpEventQueue();
      expect(repo.current, const ConnectionConnecting());
    });

    test('resume connects again to the sim that cancel stopped', () async {
      await connectSim();
      await repo.cancelConnecting();
      flightSim.connects.clear();
      await repo.resumeConnecting();
      expect(flightSim.connects.single.host, '192.168.1.10');
    });

    test('version 2 gives pluginVersionMismatch', () async {
      await connectSim();
      flightSim.setPluginState(
        const PluginStateVersionMismatch(found: 2, required: 1),
      );
      await pumpEventQueue();
      expect(
        repo.current,
        const ConnectionPluginVersionMismatch(found: 2, required: 1),
      );
    });

    test(
      'silence after connected gives simUnreachable with the last seen time',
      () async {
        await connectSim();
        await ready();
        flightSim.emit(onGroundSignal, 1);
        final seen = clock.now();
        clock.advance(const Duration(seconds: 10));
        flightSim.setStreamConnected(false);
        await pumpEventQueue();
        expect(repo.current, ConnectionSimUnreachable(lastSeen: seen));
      },
    );

    test('no network wins over simUnreachable', () async {
      await connectSim();
      await ready();
      flightSim.setStreamConnected(false);
      network.setAvailable(false);
      await pumpEventQueue();
      expect(repo.current, const ConnectionNoNetwork());
    });

    test('no network wins over connected', () async {
      await connectSim();
      await ready();
      network.setAvailable(false);
      await pumpEventQueue();
      expect(repo.current, const ConnectionNoNetwork());
    });

    test('network back with silent sim gives simUnreachable', () async {
      await connectSim();
      await ready();
      flightSim.setStreamConnected(false);
      network.setAvailable(false);
      await pumpEventQueue();
      network.setAvailable(true);
      await pumpEventQueue();
      expect(repo.current, isA<ConnectionSimUnreachable>());
    });

    test('sim back gives connected without a fresh searching state', () async {
      await connectSim();
      await ready();
      flightSim.setStreamConnected(false);
      await pumpEventQueue();
      flightSim.setStreamConnected(true);
      await pumpEventQueue();
      expect(repo.current, const ConnectionConnected());
      final afterFirstConnected = statuses.skipWhile(
        (s) => s is! ConnectionConnected,
      );
      expect(afterFirstConnected.whereType<ConnectionSearching>(), isEmpty);
    });

    test('recovery after the plugin appears returns to connected', () async {
      await connectSim();
      flightSim.setPluginState(const PluginStateNotDetected());
      await pumpEventQueue();
      await ready();
      expect(repo.current, const ConnectionConnected());
    });

    test('manual ip skips searching', () async {
      final result = await repo.useManualIp('10.0.0.7');
      expect(result.isOk, isTrue);
      expect(repo.current, const ConnectionConnecting());
      expect(flightSim.connects.last.host, '10.0.0.7');
      expect(
        discoveries.first.disposed,
        isFalse,
        reason: 'the beacon listener always runs',
      );
    });

    test('manual ip that never answers gives simUnreachable', () async {
      await repo.useManualIp('10.0.0.7');
      flightSim.setPluginState(const PluginStateNotDetected());
      await pumpEventQueue();
      expect(
        repo.current,
        const ConnectionSimUnreachable(manualAddress: '10.0.0.7'),
      );
    });

    test(
      'no-route probes give localNetworkDenied, also after a connect',
      () async {
        await connectSim();
        flightSim.setPluginState(const PluginStateNotDetected(noRoute: true));
        await pumpEventQueue();
        expect(repo.current, const ConnectionLocalNetworkDenied());
        await repo.useManualIp('10.0.0.7');
        flightSim.setPluginState(const PluginStateNotDetected(noRoute: true));
        await pumpEventQueue();
        expect(repo.current, const ConnectionLocalNetworkDenied());
        flightSim.setPluginState(const PluginStateReady(18086));
        await pumpEventQueue();
        expect(repo.current, isNot(isA<ConnectionLocalNetworkDenied>()));
      },
    );

    test('statuses are emitted only on change', () async {
      await connectSim();
      await ready();
      flightSim.setPluginState(const PluginStateReady(18086));
      network.setAvailable(true);
      await pumpEventQueue();
      for (var i = 1; i < statuses.length; i++) {
        expect(statuses[i], isNot(statuses[i - 1]));
      }
    });
  });

  group('live aircraft', () {
    test('session maps all fields to AircraftIdentity', () async {
      sessions.emit(_session());
      await pumpEventQueue();
      expect(
        repo.currentAircraft,
        const AircraftIdentity(
          icao: 'C172',
          description: 'Cessna Skyhawk 172SP',
          aircraftPath: 'Aircraft/Cessna/172.acf',
          checklistModified: 1761206400123,
          checklistSize: 267,
          checklistPath: 'Aircraft/Cessna/clist.txt',
          generation: 12,
        ),
      );
    });

    test('generation change emits a new identity', () async {
      final seen = <AircraftIdentity?>[];
      repo.liveAircraft.listen(seen.add);
      sessions.emit(_session());
      sessions.emit(_session(generation: 13));
      await pumpEventQueue();
      expect(seen.map((a) => a?.generation), [12, 13]);
    });

    test('unchanged session emits nothing', () async {
      final seen = <AircraftIdentity?>[];
      repo.liveAircraft.listen(seen.add);
      sessions.emit(_session());
      sessions.emit(_session());
      await pumpEventQueue();
      expect(seen, hasLength(1));
    });

    test(
      'no checklist fields give an identity with null checklist values',
      () async {
        sessions.emit(_session(checklist: false));
        await pumpEventQueue();
        final a = repo.currentAircraft!;
        expect(a.checklistModified, isNull);
        expect(a.checklistSize, isNull);
        expect(a.checklistPath, isNull);
      },
    );

    test('null session clears the identity', () async {
      final seen = <AircraftIdentity?>[];
      repo.liveAircraft.listen(seen.add);
      sessions.emit(_session());
      sessions.emit(null);
      await pumpEventQueue();
      expect(repo.currentAircraft, isNull);
      expect(seen.last, isNull);
    });

    test('a session error keeps the last identity', () async {
      sessions.emit(_session());
      await pumpEventQueue();
      sessions.emitError(PluginUnreachable());
      await pumpEventQueue();
      expect(repo.currentAircraft?.generation, 12);
    });

    test('a version mismatch error sets the status', () async {
      await connectSim();
      await ready();
      sessions.emitError(PluginVersionMismatch(found: 2, required: 1));
      await pumpEventQueue();
      expect(
        repo.current,
        const ConnectionPluginVersionMismatch(found: 2, required: 1),
      );
    });

    test('repository makes no http request', () {
      final source = File(
        'lib/data/repositories/flight_sim/flight_sim_repository_remote.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('package:http')));
      expect(source, isNot(contains('getAircraft(')));
      expect(source, isNot(contains('CompanionPluginService')));
    });
  });

  group('on ground', () {
    test('no reply is null', () {
      expect(repo.onGround, isNull);
    });

    test('0 maps to false', () async {
      await ready();
      flightSim.emit(onGroundSignal, 0);
      expect(repo.onGround, isFalse);
    });

    test('1 maps to true', () async {
      await ready();
      flightSim.emit(onGroundSignal, 1);
      expect(repo.onGround, isTrue);
    });

    test('other signals are ignored', () async {
      await ready();
      flightSim.emit(aircraftGenerationSignal, 5);
      expect(repo.onGround, isNull);
    });

    test('stale stream turns the value into null', () async {
      await ready();
      flightSim.emit(onGroundSignal, 1);
      flightSim.setStreamConnected(false);
      await pumpEventQueue();
      expect(repo.onGround, isNull);
    });

    test('unknown_name turns the value into null', () async {
      await ready();
      flightSim.emit(onGroundSignal, 1);
      flightSim.emitUnavailable(onGroundSignal);
      expect(repo.onGround, isNull);
    });

    test('value returns after the stream recovers', () async {
      final seen = <bool?>[];
      repo.onGroundChanges.listen(seen.add);
      await ready();
      flightSim.emit(onGroundSignal, 1);
      flightSim.setStreamConnected(false);
      await pumpEventQueue();
      flightSim.setStreamConnected(true);
      flightSim.emit(onGroundSignal, 0);
      await pumpEventQueue();
      expect(repo.onGround, isFalse);
      expect(seen, [true, null, false]);
    });
  });

  group('reload and manual ip', () {
    test('reload asks the session source to refetch', () async {
      sessions.onReload = () async => Ok(_session(generation: 14));
      final result = await repo.reload();
      expect(sessions.reloads, 1);
      expect(result.valueOrNull?.generation, 14);
      expect(repo.currentAircraft?.generation, 14);
    });

    test('reload does not reconnect or touch settings', () async {
      await connectSim();
      sessions.current = _session();
      await repo.reload();
      expect(flightSim.connects, hasLength(1));
      expect(flightSim.disconnects, 0);
      expect(await settings.manualIp(), isNull);
    });

    test('a failed reload is returned and keeps the identity', () async {
      sessions.emit(_session());
      await pumpEventQueue();
      sessions.onReload = () async => Error(PluginUnreachable());
      final result = await repo.reload();
      expect(result.errorOrNull, isA<PluginUnreachable>());
      expect(repo.currentAircraft?.generation, 12);
    });

    test('invalid ip returns Error and keeps the old connection', () async {
      await connectSim();
      final result = await repo.useManualIp('abc');
      expect(result.errorOrNull, isA<InvalidManualIp>());
      expect(discoveries, hasLength(1));
      expect(flightSim.disconnects, 0);
      expect(repo.current, const ConnectionConnecting());
    });

    test('valid ip reconnects and is not saved yet', () async {
      await connectSim();
      await repo.useManualIp(' 10.0.0.7 ');
      expect(await settings.manualIp(), isNull);
      expect(flightSim.connects.last.host, '10.0.0.7');
      expect(discoveries.first.disposed, isFalse);
    });

    test('a typed address that connects is offered for saving once', () async {
      final offers = <String>[];
      final sub = repo.manualIpWorked.listen(offers.add);
      addTearDown(sub.cancel);
      await repo.useManualIp('10.0.0.7');
      expect(offers, isEmpty, reason: 'not connected yet');
      await ready();
      flightSim.setStreamConnected(false);
      await ready();
      expect(offers, ['10.0.0.7']);
    });

    test('the saved address is not offered again', () async {
      await settings.saveManualIp('10.0.0.7');
      final offers = <String>[];
      final sub = repo.manualIpWorked.listen(offers.add);
      addTearDown(sub.cancel);
      await repo.useManualIp('10.0.0.7');
      await ready();
      expect(offers, isEmpty);
    });

    test('dropping the typed address keeps the saved one', () async {
      await settings.saveManualIp('10.0.0.9');
      await repo.useManualIp('10.0.0.7');
      await repo.dropManualIp();
      expect(await settings.manualIp(), '10.0.0.9');
      expect(repo.current, const ConnectionSearching());
      expect(discoveries.last.manualHost, isNull);
    });

    test('clearing goes back to searching', () async {
      await repo.useManualIp('10.0.0.7');
      await repo.useAutomaticDiscovery();
      expect(await settings.manualIp(), isNull);
      expect(flightSim.disconnects, greaterThanOrEqualTo(1));
      expect(repo.current, const ConnectionSearching());
      expect(discoveries.last.manualHost, isNull);
    });

    test('a stored manual ip is used at start', () async {
      await repo.dispose();
      await settings.saveManualIp('10.0.0.9');
      discoveries.clear();
      flightSim.connects.clear();
      repo = build();
      await repo.start();
      expect(discoveries, hasLength(1), reason: 'the listener always runs');
      expect(flightSim.connects.single.host, '10.0.0.9');
    });
  });

  group('multiple sims', () {
    test('one sim connects automatically', () async {
      await seeSim('192.168.1.10');
      expect(
        flightSim.connects,
        isEmpty,
        reason: 'waits for the settle window',
      );
      await settle();
      expect(flightSim.connects.single.host, '192.168.1.10');
      expect(repo.currentSims, [
        const DiscoveredSim(
          host: '192.168.1.10',
          name: 'SIM',
          simulator: Simulator.xplane,
        ),
      ]);
    });

    test('two sims wait for a choice', () async {
      await seeSim('192.168.1.10', 'A');
      await seeSim('192.168.1.117', 'B');
      await settle();
      expect(flightSim.connects, isEmpty);
      expect(repo.currentSims, hasLength(2));
      expect(repo.current, const ConnectionSearching());
    });

    test('one computer on several adapters is one sim, LAN first', () async {
      await seeSim('172.23.0.1', 'SIMPC');
      await seeSim('192.168.1.10', 'SIMPC');
      await seeSim('172.27.112.1', 'SIMPC');
      expect(repo.currentSims, [
        const DiscoveredSim(
          host: '192.168.1.10',
          name: 'SIMPC',
          simulator: Simulator.xplane,
        ),
      ]);
      await settle();
      final target = flightSim.connects.single;
      expect(target.host, '192.168.1.10');
      expect(target.alternateHosts, ['172.23.0.1', '172.27.112.1']);
    });

    test('a beacon means X-Plane; the OS is unknown until asked', () async {
      await seeSim('192.168.1.10', 'A');
      expect(repo.currentSims.single.simulator, Simulator.xplane);
      expect(repo.currentSims.single.os, isNull);
    });

    test('one computer is not asked for its OS', () async {
      await seeSim('192.168.1.10', 'A');
      await settle();
      expect(flightSim.peeks, isEmpty);
    });

    test(
      'with two computers each is asked once and the OS is listed',
      () async {
        flightSim.hellos['192.168.1.10'] = const RawHello(
          protocolVersion: 1,
          port: 18086,
          streamPath: '/v1/stream',
          runId: 'run-1',
          os: 'windows',
        );
        flightSim.hellos['192.168.1.117'] = const RawHello(
          protocolVersion: 1,
          port: 18086,
          streamPath: '/v1/stream',
          runId: 'run-1',
          os: 'macos',
        );
        await seeSim('192.168.1.10', 'A');
        await seeSim('192.168.1.117', 'B');
        await seeSim('192.168.1.117', 'B');
        expect(flightSim.peeks.map((p) => p.host), [
          '192.168.1.10',
          '192.168.1.117',
        ]);
        expect(repo.currentSims.map((s) => s.os), [
          HostOs.windows,
          HostOs.macos,
        ]);
      },
    );

    test(
      'a plugin that does not answer or say leaves the OS unknown',
      () async {
        flightSim.hellos['192.168.1.117'] = const RawHello(
          protocolVersion: 1,
          port: 18086,
          streamPath: '/v1/stream',
          runId: 'run-1',
        );
        await seeSim('192.168.1.10', 'A');
        await seeSim('192.168.1.117', 'B');
        expect(repo.currentSims.map((s) => s.os), [null, null]);
        expect(repo.currentSims, hasLength(2));
      },
    );

    test('a known OS survives the next beacon', () async {
      flightSim.hellos['192.168.1.10'] = const RawHello(
        protocolVersion: 1,
        port: 18086,
        streamPath: '/v1/stream',
        runId: 'run-1',
        os: 'linux',
      );
      await seeSim('192.168.1.10', 'A');
      await seeSim('192.168.1.117', 'B');
      await seeSim('172.23.0.1', 'A');
      expect(repo.currentSims.first.os, HostOs.linux);
    });

    test('different computers are still a choice', () async {
      await seeSim('192.168.1.10', 'A');
      await seeSim('172.23.0.1', 'A');
      await seeSim('192.168.1.117', 'B');
      await settle();
      expect(flightSim.connects, isEmpty);
      expect(repo.currentSims, hasLength(2));
    });

    test('choice is not kept across app starts', () async {
      await seeSim('192.168.1.10', 'A');
      await seeSim('192.168.1.117', 'B');
      await settle();
      await repo.selectSim(
        const DiscoveredSim(host: '192.168.1.117', name: 'B'),
      );
      expect(flightSim.connects.single.host, '192.168.1.117');
    });

    test('after a restart the user is asked again', () async {
      await seeSim('192.168.1.10', 'A');
      await seeSim('192.168.1.117', 'B');
      await settle();
      await repo.selectSim(
        const DiscoveredSim(host: '192.168.1.117', name: 'B'),
      );
      await repo.dispose();
      discoveries.clear();
      flightSim.connects.clear();
      repo = build();
      await repo.start();
      await seeSim('192.168.1.10', 'A');
      await seeSim('192.168.1.117', 'B');
      await settle();
      expect(flightSim.connects, isEmpty);
      expect(repo.currentSims, hasLength(2));
    });

    test('a new search (Rediscover, Retry) asks again', () async {
      await seeSim('192.168.1.10', 'A');
      await seeSim('192.168.1.117', 'B');
      await settle();
      await repo.selectSim(
        const DiscoveredSim(host: '192.168.1.117', name: 'B'),
      );
      flightSim.connects.clear();
      await repo.dropManualIp();
      await seeSim('192.168.1.10', 'A');
      await seeSim('192.168.1.117', 'B');
      await settle();
      expect(flightSim.connects, isEmpty);
      expect(repo.currentSims, hasLength(2));
    });

    test('a second sim after connecting changes nothing', () async {
      await connectSim();
      await seeSim('192.168.1.117', 'B');
      await settle();
      expect(flightSim.connects, hasLength(1));
      expect(repo.currentSims, hasLength(2));
    });

    test('the target is the sim being connected', () async {
      expect(repo.currentTarget, isNull);
      await seeSim('192.168.1.10', 'A');
      await settle();
      expect(repo.currentTarget?.host, '192.168.1.10');
      expect(repo.currentTarget?.name, 'A');
      expect(repo.currentTarget?.simulator, Simulator.xplane);
    });

    test('the simulator is the one the discovery named', () async {
      discoveries.last.see(
        const SimEndpoint(
          host: '192.168.1.10',
          name: 'FLIGHT-PC',
          simulator: Simulator.msfs,
        ),
      );
      await pumpEventQueue();
      await settle();
      expect(repo.currentSims.single.simulator, Simulator.msfs);
      expect(repo.currentTarget?.simulator, Simulator.msfs);
    });

    test(
      'the sim kind in the hello names the simulator once connected',
      () async {
        await connectSim();
        expect(repo.currentTarget?.simulator, Simulator.xplane);
        flightSim.simKind = 'msfs';
        expect(repo.currentTarget?.simulator, Simulator.msfs);
      },
    );

    test('retry forgets the sim and listens for beacons again', () async {
      await connectSim();
      final first = discoveries.last;
      flightSim.setPluginState(const PluginStateNotDetected());
      await pumpEventQueue();
      expect(repo.current, const ConnectionConnecting());
      await repo.retry();
      expect(flightSim.disconnects, 1);
      expect(repo.current, const ConnectionSearching());
      expect(repo.currentTarget, isNull);
      expect(repo.currentSims, isEmpty);
      expect(first.disposed, isTrue);
      expect(discoveries.last, isNot(same(first)));
      expect(flightSim.connects, hasLength(1), reason: 'no new connect yet');
      await seeSim();
      await settle();
      expect(flightSim.connects, hasLength(2));
    });

    test('retry with a manual address reconnects to it', () async {
      await repo.useManualIp('10.0.0.7');
      flightSim.connects.clear();
      await repo.retry();
      expect(flightSim.connects.single.host, '10.0.0.7');
      expect(flightSim.disconnects, 0);
    });

    test(
      'cancel stops connecting, keeps the target and blocks beacons',
      () async {
        await connectSim();
        await repo.cancelConnecting();
        expect(flightSim.disconnects, 1);
        expect(repo.currentTarget?.host, '192.168.1.10');
        await seeSim('192.168.1.117', 'B');
        await settle();
        expect(flightSim.connects, hasLength(1), reason: 'no reconnect');
      },
    );

    test('search after cancel finds the sim again', () async {
      await connectSim();
      await repo.cancelConnecting();
      await repo.retry();
      expect(repo.currentTarget, isNull);
      await seeSim();
      await settle();
      expect(flightSim.connects, hasLength(2));
    });

    test('retry after cancel with a manual address reconnects to it', () async {
      await repo.useManualIp('10.0.0.7');
      flightSim.connects.clear();
      await repo.cancelConnecting();
      await repo.retry();
      expect(flightSim.connects.single.host, '10.0.0.7');
    });

    test('manual ip overrides discovery', () async {
      final automatic = discoveries.single;
      await repo.useManualIp('10.0.0.7');
      await settle();
      expect(automatic.disposed, isFalse);
      expect(discoveries, hasLength(1));
      expect(flightSim.connects.map((s) => s.host), ['10.0.0.7']);
    });
  });

  group('switching computers (task 0.16)', () {
    Future<void> connectA() async {
      await seeSim('192.168.1.10', 'A');
      await settle();
      await ready();
    }

    Future<void> loseA() async {
      flightSim.setStreamConnected(false);
      await pumpEventQueue();
    }

    test('another computer while connected is only listed', () async {
      await connectA();
      await seeSim('192.168.1.117', 'B');
      expect(repo.currentSims, hasLength(2));
      expect(repo.currentSwitchOffer, isNull);
      expect(flightSim.connects, hasLength(1));
    });

    test('A lost with B heard asks, and does not connect', () async {
      await connectA();
      await seeSim('192.168.1.117', 'B');
      await loseA();
      final offer = repo.currentSwitchOffer!;
      expect(offer.from?.name, 'A');
      expect(offer.to.name, 'B');
      expect(flightSim.connects, hasLength(1));
    });

    test('a beacon from B after A is lost asks', () async {
      await connectA();
      await loseA();
      expect(repo.currentSwitchOffer, isNull);
      await seeSim('192.168.1.117', 'B');
      expect(repo.currentSwitchOffer!.to.name, 'B');
    });

    test('a computer that stops sending beacons leaves the list', () async {
      await connectA();
      await seeSim('192.168.1.117', 'B');
      clock.advance(const Duration(seconds: 4));
      await seeSim('192.168.1.10', 'A');
      clock.advance(const Duration(seconds: 2));
      await pumpEventQueue();
      expect(repo.currentSims.map((s) => s.name), ['A']);
      await loseA();
      expect(repo.currentSwitchOffer, isNull);
    });

    test('a silent computer whose plugin answers stays on the list', () async {
      // X-Plane stops beaconing while it loads an aircraft.
      flightSim.hellos['192.168.1.117'] = const RawHello(
        protocolVersion: 1,
        port: 18086,
        streamPath: '/v1/stream',
        runId: 'run-2',
      );
      await connectA();
      await seeSim('192.168.1.117', 'B');
      for (var i = 0; i < 30; i++) {
        clock.advance(const Duration(seconds: 1));
        await seeSim('192.168.1.10', 'A');
        await pumpEventQueue();
      }
      expect(repo.currentSims.map((s) => s.name), containsAll(['A', 'B']));
      // It quits: the plugin no longer answers.
      flightSim.hellos.remove('192.168.1.117');
      for (var i = 0; i < 8; i++) {
        clock.advance(const Duration(seconds: 1));
        await seeSim('192.168.1.10', 'A');
        await pumpEventQueue();
      }
      expect(repo.currentSims.map((s) => s.name), ['A']);
    });

    test('a beacon every second keeps a computer on the list', () async {
      await connectA();
      await seeSim('192.168.1.117', 'B');
      for (var i = 0; i < 12; i++) {
        clock.advance(const Duration(seconds: 1));
        await seeSim('192.168.1.117', 'B');
        await seeSim('192.168.1.10', 'A');
      }
      expect(repo.currentSims, hasLength(2));
    });

    test('a computer that returns after leaving is a new candidate', () async {
      await connectA();
      await seeSim('192.168.1.117', 'B');
      clock.advance(const Duration(seconds: 6));
      await loseA();
      expect(repo.currentSwitchOffer, isNull);
      await seeSim('192.168.1.117', 'B');
      expect(repo.currentSwitchOffer!.to.name, 'B');
    });

    test('the question closes when its computer leaves', () async {
      await connectA();
      await seeSim('192.168.1.117', 'B');
      await loseA();
      expect(repo.currentSwitchOffer, isNotNull);
      clock.advance(const Duration(seconds: 6));
      await pumpEventQueue();
      expect(repo.currentSwitchOffer, isNull);
    });

    test('A back on a new address is retried there', () async {
      await connectA();
      await loseA();
      flightSim.connects.clear();
      await seeSim('192.168.1.200', 'A');
      expect(flightSim.connects.single.hosts, contains('192.168.1.200'));
      expect(repo.currentTarget?.name, 'A');
      await seeSim('192.168.1.200', 'A');
      expect(flightSim.connects, hasLength(1));
    });

    test('with a typed address other computers are still listed', () async {
      await repo.useManualIp('10.0.0.7');
      await seeSim('192.168.1.117', 'B');
      expect(repo.currentSims.single.name, 'B');
      expect(flightSim.connects.single.host, '10.0.0.7');
    });

    test('Yes connects to B and clears the question', () async {
      await connectA();
      await seeSim('192.168.1.117', 'B');
      await loseA();
      final offers = <SwitchOffer?>[];
      repo.switchOffers.listen(offers.add);
      await repo.answerSwitch(accept: true);
      await pumpEventQueue();
      expect(flightSim.connects.last.host, '192.168.1.117');
      expect(repo.currentSwitchOffer, isNull);
      expect(offers, [null]);
    });

    test('No declines B, keeps A and never asks again', () async {
      await connectA();
      await seeSim('192.168.1.117', 'B');
      await loseA();
      await repo.answerSwitch(accept: false);
      expect(repo.declinedSims.single.name, 'B');
      expect(repo.currentSims, hasLength(2), reason: 'still on the list');
      expect(flightSim.connects, hasLength(1));
      expect(repo.currentTarget?.name, 'A');
      await seeSim('192.168.1.117', 'B');
      await seeSim('192.168.1.117', 'B');
      expect(repo.currentSwitchOffer, isNull);
    });

    test('A coming back clears the question', () async {
      await connectA();
      await seeSim('192.168.1.117', 'B');
      await loseA();
      await ready();
      expect(repo.currentSwitchOffer, isNull);
    });

    test('searching again finds only B: asks instead of connecting', () async {
      await connectA();
      await loseA();
      await repo.retry();
      await seeSim('192.168.1.117', 'B');
      await settle();
      expect(flightSim.connects, hasLength(1));
      expect(repo.currentSwitchOffer!.from?.name, 'A');
      expect(repo.currentSwitchOffer!.to.name, 'B');
    });

    test('searching again finds A: connects without asking', () async {
      await connectA();
      await loseA();
      await repo.retry();
      await seeSim('192.168.1.10', 'A');
      await settle();
      expect(flightSim.connects, hasLength(2));
      expect(repo.currentSwitchOffer, isNull);
    });

    test('No after a search keeps B from auto-connecting', () async {
      await connectA();
      await loseA();
      await repo.retry();
      await seeSim('192.168.1.117', 'B');
      await settle();
      await repo.answerSwitch(accept: false);
      await seeSim('192.168.1.117', 'B');
      await settle();
      expect(flightSim.connects, hasLength(1));
      expect(repo.current, const ConnectionSearching());
    });

    test('picking B in the chooser forgets the No', () async {
      await connectA();
      await seeSim('192.168.1.117', 'B');
      await loseA();
      await repo.answerSwitch(accept: false);
      await repo.selectSim(repo.currentSims.firstWhere((s) => s.name == 'B'));
      expect(repo.declinedSims, isEmpty);
      expect(flightSim.connects.last.host, '192.168.1.117');
    });

    test('typing the address of B forgets the No', () async {
      await connectA();
      await seeSim('192.168.1.117', 'B');
      await loseA();
      await repo.answerSwitch(accept: false);
      await repo.useManualIp('192.168.1.117');
      expect(repo.declinedSims, isEmpty);
    });

    test('the first connection never asks', () async {
      await seeSim('192.168.1.117', 'B');
      await settle();
      expect(repo.currentSwitchOffer, isNull);
      expect(flightSim.connects.single.host, '192.168.1.117');
    });
  });
}
