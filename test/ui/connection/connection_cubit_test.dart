import 'package:bloc_test/bloc_test.dart';
import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_local.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/domain/models/flight_sim/discovered_sim.dart';
import 'package:flightsim_aide/domain/models/flight_sim/simulator.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_cubit.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_state.dart';
import 'package:flightsim_aide/ui/connection/cubit/known_address.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/services/manual_clock.dart';

// AC-8: invalid manual IP keeps the current state and shows a message
// AC-9: a silent plugin keeps the waiting state

const _cessna = AircraftIdentity(
  icao: 'C172',
  description: 'Cessna 172',
  aircraftPath: 'Aircraft/C172/c172.acf',
  checklistPath: 'Aircraft/C172/clist.txt',
  generation: 1,
);
const _boeing = AircraftIdentity(
  icao: 'B738',
  description: 'Boeing 737',
  aircraftPath: 'Aircraft/B738/b738.acf',
  checklistPath: 'Aircraft/B738/clist.txt',
  generation: 2,
);
const _bare = AircraftIdentity(
  icao: 'PA28',
  description: 'Piper',
  aircraftPath: 'Aircraft/PA28/pa28.acf',
  generation: 3,
);

void main() {
  late FlightSimRepositoryLocal sim;
  late FakeSettingsRepository settings;
  late ManualClock clock;

  setUp(() {
    sim = FlightSimRepositoryLocal();
    settings = FakeSettingsRepository();
    clock = ManualClock();
  });
  tearDown(() => sim.dispose());

  ConnectionCubit build() =>
      ConnectionCubit(flightSim: sim, settings: settings, clock: clock);

  test('starts from the repository snapshot', () {
    sim.setStatus(const ConnectionNoNetwork());
    final cubit = build();
    addTearDown(cubit.close);
    expect(cubit.state, const LinkNoNetwork());
  });

  blocTest<ConnectionCubit, ConnectionViewState>(
    'emits searching then connecting then connected',
    build: build,
    act: (_) async {
      sim.setStatus(const ConnectionConnecting());
      await pumpEventQueue();
      sim.setAircraft(_cessna);
      sim.setStatus(const ConnectionConnected());
    },
    expect: () => [const LinkConnecting(), const LinkConnected(_cessna)],
    verify: (cubit) => expect(cubit.state, const LinkConnected(_cessna)),
  );

  blocTest<ConnectionCubit, ConnectionViewState>(
    'no route to host emits LinkLocalNetworkDenied',
    build: build,
    act: (_) => sim.setStatus(const ConnectionLocalNetworkDenied()),
    expect: () => [const LinkLocalNetworkDenied()],
  );

  blocTest<ConnectionCubit, ConnectionViewState>(
    'version mismatch carries both versions',
    build: build,
    act: (_) => sim.setStatus(
      const ConnectionPluginVersionMismatch(found: 2, required: 1),
    ),
    expect: () => [const LinkVersionMismatch(found: 2, required: 1)],
  );

  blocTest<ConnectionCubit, ConnectionViewState>(
    'aircraft without checklist emits LinkNoChecklist',
    build: build,
    act: (_) {
      sim.setAircraft(_bare);
      sim.setStatus(const ConnectionConnected());
    },
    expect: () => [const LinkNoChecklist(_bare)],
  );

  blocTest<ConnectionCubit, ConnectionViewState>(
    'sim silence emits LinkSimUnreachable with the last seen time',
    build: build,
    act: (_) => sim.setStatus(
      ConnectionSimUnreachable(lastSeen: DateTime.utc(2026, 10, 25, 14, 32)),
    ),
    expect: () => [
      LinkSimUnreachable(lastSeen: DateTime.utc(2026, 10, 25, 14, 32)),
    ],
  );

  blocTest<ConnectionCubit, ConnectionViewState>(
    'connected without a known aircraft stays connecting',
    build: build,
    act: (_) => sim.setStatus(const ConnectionConnected()),
    expect: () => [const LinkConnecting()],
  );

  group('search', () {
    blocTest<ConnectionCubit, ConnectionViewState>(
      'lists the sims seen while searching',
      build: build,
      act: (_) =>
          sim.setSims(const [DiscoveredSim(host: '10.0.0.5', name: 'A')]),
      expect: () => [
        const LinkSearching(
          sims: [DiscoveredSim(host: '10.0.0.5', name: 'A')],
        ),
      ],
    );

    blocTest<ConnectionCubit, ConnectionViewState>(
      'the wait for the aircraft shows the hint after 10 seconds',
      build: build,
      act: (_) async {
        sim.setStatus(const ConnectionConnecting());
        await pumpEventQueue();
        clock.advance(const Duration(seconds: 9));
        clock.advance(const Duration(seconds: 1));
      },
      expect: () => [const LinkConnecting(), const LinkConnecting(hint: true)],
    );

    blocTest<ConnectionCubit, ConnectionViewState>(
      'leaving the wait cancels the timer and drops the hint',
      build: build,
      act: (_) async {
        sim.setStatus(const ConnectionConnecting());
        await pumpEventQueue();
        sim.setStatus(const ConnectionSearching());
        await pumpEventQueue();
        clock.advance(const Duration(seconds: 30));
        sim.setStatus(const ConnectionConnecting());
        await pumpEventQueue();
      },
      expect: () => [
        const LinkConnecting(),
        const LinkSearching(),
        const LinkConnecting(),
      ],
    );
  });

  group('aircraft change', () {
    blocTest<ConnectionCubit, ConnectionViewState>(
      'different live aircraft emits LinkAircraftChanged',
      build: build,
      act: (cubit) async {
        sim.setAircraft(_cessna);
        sim.setStatus(const ConnectionConnected());
        await pumpEventQueue();
        cubit.setLoadedAircraft(_cessna);
        sim.setAircraft(_boeing);
      },
      expect: () => [
        const LinkConnected(_cessna),
        const LinkAircraftChanged(loaded: _cessna, live: _boeing),
      ],
    );

    blocTest<ConnectionCubit, ConnectionViewState>(
      'a live aircraft without a checklist is a change too',
      build: build,
      act: (cubit) async {
        sim.setAircraft(_cessna);
        sim.setStatus(const ConnectionConnected());
        await pumpEventQueue();
        cubit.setLoadedAircraft(_cessna);
        sim.setAircraft(_bare);
      },
      skip: 1,
      expect: () => [const LinkAircraftChanged(loaded: _cessna, live: _bare)],
    );

    blocTest<ConnectionCubit, ConnectionViewState>(
      'a computer the user chose, with an aircraft without checklist, is '
      '"no checklist", not a change',
      build: build,
      act: (cubit) async {
        sim.setAircraft(_cessna);
        sim.setStatus(const ConnectionConnected());
        await pumpEventQueue();
        cubit.setLoadedAircraft(_cessna);
        await cubit.answerSwitch(accept: true);
        sim.setAircraft(_bare);
        await pumpEventQueue();
        // Another aircraft on the same computer later is a change again.
        sim.setAircraft(_boeing);
      },
      skip: 1,
      expect: () => [
        const LinkNoChecklist(_bare),
        const LinkAircraftChanged(loaded: _cessna, live: _boeing),
      ],
    );

    blocTest<ConnectionCubit, ConnectionViewState>(
      'the sim returning to the loaded aircraft clears the notice',
      build: build,
      act: (cubit) async {
        sim.setAircraft(_cessna);
        sim.setStatus(const ConnectionConnected());
        cubit.setLoadedAircraft(_cessna);
        await pumpEventQueue();
        sim.setAircraft(_boeing);
        await pumpEventQueue();
        sim.setAircraft(_cessna);
      },
      skip: 2,
      expect: () => [const LinkConnected(_cessna)],
    );

    blocTest<ConnectionCubit, ConnectionViewState>(
      'a second change replaces the notice',
      build: build,
      act: (cubit) async {
        sim.setAircraft(_cessna);
        sim.setStatus(const ConnectionConnected());
        cubit.setLoadedAircraft(_cessna);
        await pumpEventQueue();
        sim.setAircraft(_boeing);
        await pumpEventQueue();
        sim.setAircraft(_bare);
      },
      skip: 2,
      expect: () => [const LinkAircraftChanged(loaded: _cessna, live: _bare)],
    );

    blocTest<ConnectionCubit, ConnectionViewState>(
      'a new generation of the same aircraft is not a change',
      build: build,
      act: (cubit) async {
        sim.setAircraft(_cessna);
        sim.setStatus(const ConnectionConnected());
        cubit.setLoadedAircraft(_cessna);
        await pumpEventQueue();
        sim.setAircraft(
          AircraftIdentity(
            icao: _cessna.icao,
            description: _cessna.description,
            aircraftPath: _cessna.aircraftPath,
            checklistPath: _cessna.checklistPath,
            generation: 9,
          ),
        );
      },
      skip: 1,
      expect: () => [isA<LinkConnected>()],
    );

    blocTest<ConnectionCubit, ConnectionViewState>(
      'switching (loading the new aircraft) clears the notice',
      build: build,
      act: (cubit) async {
        sim.setAircraft(_cessna);
        sim.setStatus(const ConnectionConnected());
        cubit.setLoadedAircraft(_cessna);
        await pumpEventQueue();
        sim.setAircraft(_boeing);
        await pumpEventQueue();
        cubit.setLoadedAircraft(_boeing);
      },
      skip: 2,
      expect: () => [const LinkConnected(_boeing)],
    );

    blocTest<ConnectionCubit, ConnectionViewState>(
      'connection loss wins over the aircraft notice',
      build: build,
      act: (cubit) async {
        sim.setAircraft(_boeing);
        sim.setStatus(const ConnectionConnected());
        cubit.setLoadedAircraft(_cessna);
        await pumpEventQueue();
        sim.setStatus(const ConnectionNoNetwork());
      },
      skip: 1,
      expect: () => [const LinkNoNetwork()],
    );
  });

  group('actions', () {
    test('valid ip calls the repository and reconnects', () async {
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.setManualIp(' 10.0.0.5 ');
      expect(sim.manualIp, '10.0.0.5');
      expect(cubit.state.inputError, isNull);
    });

    blocTest<ConnectionCubit, ConnectionViewState>(
      'invalid ip emits a message and keeps state',
      build: () {
        sim.setStatus(const ConnectionConnecting());
        return build();
      },
      act: (cubit) => cubit.setManualIp('abc'),
      expect: () => [
        isA<LinkConnecting>().having(
          (s) => s.inputError,
          'error',
          contains('abc'),
        ),
      ],
      verify: (_) => expect(sim.manualIp, isNull),
    );

    blocTest<ConnectionCubit, ConnectionViewState>(
      'a good ip after a bad one clears the message',
      build: () {
        sim.setStatus(const ConnectionConnecting());
        return build();
      },
      act: (cubit) async {
        await cubit.setManualIp('abc');
        await cubit.setManualIp('10.0.0.5');
      },
      expect: () => [
        isA<LinkConnecting>().having((s) => s.inputError, 'error', isNotNull),
        const LinkConnecting(),
      ],
    );

    test('clear returns to automatic', () async {
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.setManualIp('10.0.0.5');
      await cubit.clearManualIp();
      expect(sim.manualIp, isNull);
    });

    test('saved manual ip is read from settings', () async {
      final cubit = build();
      addTearDown(cubit.close);
      expect(await cubit.savedManualIp(), isNull);
      await settings.saveManualIp('10.0.0.5');
      expect(await cubit.savedManualIp(), '10.0.0.5');
    });

    test('cancel connecting delegates and the target is readable', () async {
      final cubit = build();
      addTearDown(cubit.close);
      sim.currentTarget = const DiscoveredSim(host: '10.0.0.5', name: 'Mac');
      expect(cubit.target?.host, '10.0.0.5');
      await cubit.cancelConnecting();
      expect(sim.cancels, 1);
    });

    test('known addresses: the example when nothing is known', () async {
      final cubit = build();
      addTearDown(cubit.close);
      expect(await cubit.knownAddresses(), const [
        KnownAddress(address: exampleAddress, description: 'example'),
      ]);
    });

    test('known addresses: saved, connected and seen computers', () async {
      final cubit = build();
      addTearDown(cubit.close);
      await settings.saveManualIp('10.0.0.5');
      sim.currentTarget = const DiscoveredSim(host: '10.0.0.5', name: 'PC');
      sim.setStatus(const ConnectionConnected());
      sim.setSims(const [
        DiscoveredSim(host: '10.0.0.5', name: 'PC'),
        DiscoveredSim(
          host: '10.0.0.9',
          name: 'MacBook',
          simulator: Simulator.xplane,
          os: HostOs.macos,
        ),
        DiscoveredSim(host: '10.0.0.10'),
      ]);
      final known = await cubit.knownAddresses();
      expect(known.map((k) => k.address), [
        '10.0.0.5',
        '10.0.0.9',
        '10.0.0.10',
      ]);
      expect(known[0].description, 'saved and connected, PC');
      expect(known[1].description, 'MacBook, macOS, X-Plane');
      expect(known[2].description, 'unknown');
    });

    test('a declined computer says so in the list', () async {
      final cubit = build();
      addTearDown(cubit.close);
      const mac = DiscoveredSim(host: '10.0.0.9', name: 'MAC');
      sim.setSims(const [mac]);
      sim.declinedSims = const [mac];
      expect(
        (await cubit.knownAddresses()).single.description,
        'MAC, declined this session',
      );
    });

    test('known addresses: a saved address that is not connected', () async {
      final cubit = build();
      addTearDown(cubit.close);
      await settings.saveManualIp('10.0.0.5');
      expect((await cubit.knownAddresses()).single.description, 'saved');
    });

    test('retry restarts the search', () async {
      final cubit = build();
      addTearDown(cubit.close);
      await cubit.retry();
      expect(sim.retries, 1);
    });

    test('reload says whether it worked', () async {
      final cubit = build();
      addTearDown(cubit.close);
      sim.setAircraft(
        const AircraftIdentity(
          icao: 'C172',
          description: 'Cessna 172',
          aircraftPath: 'a.acf',
        ),
      );
      expect(await cubit.reload(), isTrue);
      sim.setAircraft(null);
      expect(await cubit.reload(), isFalse);
    });

    test('reload delegates to the repository', () async {
      final cubit = build();
      addTearDown(cubit.close);
      sim.setAircraft(_cessna);
      await cubit.reload();
      expect(sim.reloads, 1);
    });

    test('select sim delegates to the repository', () async {
      final cubit = build();
      addTearDown(cubit.close);
      const chosen = DiscoveredSim(host: '10.0.0.5');
      await cubit.selectSim(chosen);
      expect(sim.selectedSim, chosen);
    });
  });

  test('closing cancels subscriptions and the timer', () async {
    final cubit = build();
    await cubit.close();
    expect(clock.pendingTimers, 0);
    sim.setStatus(const ConnectionNoNetwork());
    await pumpEventQueue();
    expect(cubit.state, isNot(const LinkNoNetwork()));
  });
}
