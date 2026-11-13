import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_local.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/domain/models/flight_sim/discovered_sim.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FlightSimRepositoryLocal repo;

  const aircraft = AircraftIdentity(
    icao: 'C172',
    description: 'Cessna',
    aircraftPath: 'Aircraft/C172/c172.acf',
    generation: 1,
  );

  setUp(() => repo = FlightSimRepositoryLocal());
  tearDown(() => repo.dispose());

  test('can be scripted through every ConnectionStatus', () async {
    final seen = <ConnectionStatus>[];
    repo.connectionStatus.listen(seen.add);
    final script = <ConnectionStatus>[
      const ConnectionConnecting(),
      const ConnectionConnected(),
      const ConnectionNoNetwork(),
      ConnectionSimUnreachable(lastSeen: DateTime.utc(2026, 10, 25)),
      const ConnectionPluginVersionMismatch(found: 2, required: 1),
      const ConnectionSearching(),
    ];
    for (final status in script) {
      repo.setStatus(status);
      expect(repo.current, status);
    }
    await pumpEventQueue();
    expect(seen, script);
  });

  test('setting the same status again emits nothing', () async {
    final seen = <ConnectionStatus>[];
    repo.connectionStatus.listen(seen.add);
    repo.setStatus(const ConnectionConnected());
    repo.setStatus(const ConnectionConnected());
    await pumpEventQueue();
    expect(seen, hasLength(1));
  });

  test('aircraft change emits', () async {
    final seen = <AircraftIdentity?>[];
    repo.liveAircraft.listen(seen.add);
    repo.setAircraft(aircraft);
    repo.setAircraft(null);
    await pumpEventQueue();
    expect(seen, [aircraft, null]);
    expect(repo.currentAircraft, isNull);
  });

  test('on ground is scripted and emits on change', () async {
    final seen = <bool?>[];
    repo.onGroundChanges.listen(seen.add);
    repo.setOnGround(true);
    repo.setOnGround(true);
    repo.setOnGround(false);
    await pumpEventQueue();
    expect(seen, [true, false]);
    expect(repo.onGround, isFalse);
  });

  test('sims are scripted and selectSim records the choice', () async {
    const sim = DiscoveredSim(host: '10.0.0.5', name: 'A');
    repo.setSims([sim]);
    expect(repo.currentSims, [sim]);
    await repo.selectSim(sim);
    expect(repo.selectedSim, sim);
  });

  test('manual ip is validated and remembered', () async {
    expect((await repo.useManualIp('abc')).errorOrNull, isA<InvalidManualIp>());
    expect(repo.manualIp, isNull);
    expect((await repo.useManualIp(' 10.0.0.5 ')).isOk, isTrue);
    expect(repo.manualIp, '10.0.0.5');
    await repo.useAutomaticDiscovery();
    expect(repo.manualIp, isNull);
  });

  test(
    'reload returns the scripted aircraft or an error without one',
    () async {
      expect((await repo.reload()).errorOrNull, isA<PluginNotDetected>());
      repo.setAircraft(aircraft);
      expect((await repo.reload()).valueOrNull, aircraft);
      expect(repo.reloads, 2);
    },
  );

  test('start, pause and resume are counted and harmless', () async {
    await repo.start();
    await repo.pause();
    await repo.resume();
    expect([repo.starts, repo.pauses, repo.resumes], [1, 1, 1]);
  });
}
