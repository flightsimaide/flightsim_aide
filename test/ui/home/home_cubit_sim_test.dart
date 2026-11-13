import 'dart:async';

import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_local.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/checklist/attach_outcome.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/ui/home/cubit/home_cubit.dart';
import 'package:flightsim_aide/ui/home/cubit/home_state.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../../testing/fakes/repositories/fake_checklist_repository.dart';

const _cessna = AircraftIdentity(
  icao: 'C172',
  description: 'Cessna 172',
  aircraftPath: 'a.acf',
  checklistPath: 'clist.txt',
  generation: 1,
);
const _boeing = AircraftIdentity(
  icao: 'B738',
  description: 'Boeing',
  aircraftPath: 'b.acf',
  checklistPath: 'clist.txt',
  generation: 2,
);
const _bare = AircraftIdentity(
  icao: 'PA28',
  description: 'Piper',
  aircraftPath: 'c.acf',
  generation: 3,
);

final _doc = ChecklistDocument(
  checklists: const [],
  warnings: const [],
  sourceName: 'a.txt',
);

void main() {
  late FlightSimRepositoryLocal sim;
  late FakeChecklistRepository checklists;
  late FakeChecklistProgressRepository progress;
  late HomeCubit cubit;

  setUp(() {
    sim = FlightSimRepositoryLocal();
    checklists = FakeChecklistRepository(loadResults: [Ok(_doc)]);
    progress = FakeChecklistProgressRepository();
    cubit = HomeCubit(
      checklistRepository: checklists,
      progressRepository: progress,
      flightSim: sim,
    );
  });
  tearDown(() async {
    await cubit.close();
    await checklists.dispose();
    await sim.dispose();
  });

  test('connected with checklist loads once', () async {
    sim.setAircraft(_cessna);
    sim.setStatus(const ConnectionConnected());
    await pumpEventQueue();
    expect(checklists.loadCount, 1);
    expect(cubit.state, HomeLoaded(_doc, aircraft: _cessna));
  });

  test('already connected when the cubit is created loads once', () async {
    final other = FlightSimRepositoryLocal()
      ..setAircraft(_cessna)
      ..setStatus(const ConnectionConnected());
    addTearDown(other.dispose);
    final repo = FakeChecklistRepository(loadResults: [Ok(_doc)]);
    addTearDown(repo.dispose);
    final c = HomeCubit(
      checklistRepository: repo,
      progressRepository: FakeChecklistProgressRepository(),
      flightSim: other,
    );
    addTearDown(c.close);
    await pumpEventQueue();
    expect(repo.loadCount, 1);
  });

  test('a later aircraft change does not load by itself', () async {
    sim.setAircraft(_cessna);
    sim.setStatus(const ConnectionConnected());
    await pumpEventQueue();
    sim.setAircraft(_boeing);
    await pumpEventQueue();
    expect(checklists.loadCount, 1);
    expect((cubit.state as HomeLoaded).aircraft, _cessna);
  });

  test('status ticks do not reload', () async {
    sim.setAircraft(_cessna);
    sim.setStatus(const ConnectionConnected());
    await pumpEventQueue();
    sim.setStatus(const ConnectionNoNetwork());
    await pumpEventQueue();
    sim.setStatus(const ConnectionConnected());
    await pumpEventQueue();
    expect(checklists.loadCount, 1);
  });

  test('waiting for the aircraft shows no load', () async {
    sim.setStatus(const ConnectionConnecting());
    await pumpEventQueue();
    expect(checklists.loadCount, 0);
    expect(cubit.state, const HomeInitial());
  });

  test('an aircraft without a checklist is not loaded', () async {
    sim.setAircraft(_bare);
    sim.setStatus(const ConnectionConnected());
    await pumpEventQueue();
    expect(checklists.loadCount, 0);
  });

  test('connected before the aircraft is known waits for it', () async {
    sim.setStatus(const ConnectionConnected());
    await pumpEventQueue();
    expect(checklists.loadCount, 0);
    sim.setAircraft(_cessna);
    await pumpEventQueue();
    expect(checklists.loadCount, 1);
  });

  test('without a flight sim nothing loads by itself', () async {
    final repo = FakeChecklistRepository(loadResults: [Ok(_doc)]);
    addTearDown(repo.dispose);
    final c = HomeCubit(
      checklistRepository: repo,
      progressRepository: FakeChecklistProgressRepository(),
    );
    addTearDown(c.close);
    await pumpEventQueue();
    expect(repo.loadCount, 0);
    await c.load();
    expect(c.state, HomeLoaded(_doc));
  });

  test('closing cancels the subscriptions', () async {
    await cubit.close();
    sim.setAircraft(_cessna);
    sim.setStatus(const ConnectionConnected());
    await pumpEventQueue();
    expect(checklists.loadCount, 0);
  });

  test('network source attaches with the aircraft and run id captured before '
      'the load', () async {
    sim.setAircraft(_cessna);
    sim.runId = 'run-1';
    sim.setStatus(const ConnectionConnected());
    await pumpEventQueue();
    expect(progress.attachCalls, hasLength(1));
    expect(progress.attachCalls.single.$2, _cessna);
    expect(progress.attachCalls.single.$3, 'run-1');
  });

  test('aircraft changing during the load discards the result and does not '
      'attach', () async {
    final gate = Completer<void>();
    checklists.loadGate = gate.future;
    sim.setAircraft(_cessna);
    sim.setStatus(const ConnectionConnected());
    await pumpEventQueue();
    expect(cubit.state, const HomeLoading());
    sim.setAircraft(_boeing);
    checklists.loadGate = null;
    gate.complete();
    await pumpEventQueue();
    expect(progress.attachCalls.length, lessThanOrEqualTo(1));
    // The first result was discarded; a second load ran for the new aircraft.
    expect(checklists.loadCount, 2);
    expect(progress.attachCalls.single.$2, _boeing);
    expect((cubit.state as HomeLoaded).aircraft, _boeing);
  });

  test(
    'progress is never saved under an aircraft other than the one loaded',
    () async {
      final gate = Completer<void>();
      checklists.loadGate = gate.future;
      sim.setAircraft(_cessna);
      sim.setStatus(const ConnectionConnected());
      await pumpEventQueue();
      sim.setAircraft(_boeing);
      gate.complete();
      await pumpEventQueue();
      expect(progress.attachCalls.where((c) => c.$2 == _cessna), isEmpty);
    },
  );

  group('reconnect', () {
    Future<void> connectedAndLoaded() async {
      sim.setAircraft(_cessna);
      sim.setOnGround(true);
      sim.runId = 'run-1';
      sim.setStatus(const ConnectionConnected());
      await pumpEventQueue();
      expect(cubit.state, isA<HomeLoaded>());
    }

    test('recovery with the same aircraft applies the reconnect rule and '
        'does not attach again', () async {
      await connectedAndLoaded();
      sim.setStatus(const ConnectionNoNetwork());
      await pumpEventQueue();
      sim.setStatus(const ConnectionConnected());
      await pumpEventQueue();
      expect(progress.reconnectCalls, ['run-1']);
      expect(progress.attachCalls, hasLength(1));
      expect(checklists.loadCount, 1);
      expect(cubit.state, isA<HomeLoaded>());
    });

    test(
      'a new connection with the checklist loaded changes nothing',
      () async {
        await connectedAndLoaded();
        final before = cubit.state;
        sim.setStatus(const ConnectionSearching());
        await pumpEventQueue();
        sim.setStatus(const ConnectionConnected());
        await pumpEventQueue();
        expect(cubit.state, before);
        expect((cubit.state as HomeLoaded).openList, isFalse);
        expect(checklists.loadCount, 1, reason: 'not loaded again');
      },
    );

    test('recovery with a different aircraft does not reconnect', () async {
      await connectedAndLoaded();
      sim.setStatus(const ConnectionNoNetwork());
      await pumpEventQueue();
      sim.setAircraft(_boeing);
      sim.setStatus(const ConnectionConnected());
      await pumpEventQueue();
      expect(progress.reconnectCalls, isEmpty);
    });

    test('a sim restart without an outage state does not reconnect', () async {
      await connectedAndLoaded();
      sim.setStatus(const ConnectionSearching());
      await pumpEventQueue();
      sim.setStatus(const ConnectionConnected());
      await pumpEventQueue();
      expect(progress.reconnectCalls, isEmpty);
    });

    test(
      'a prompt from the reconnect rule keeps the list and answers',
      () async {
        await connectedAndLoaded();
        progress.forcedReconnect = const AttachNeedsPrompt();
        sim.setStatus(const ConnectionNoNetwork());
        await pumpEventQueue();
        sim.setStatus(const ConnectionConnected());
        await pumpEventQueue();
        expect(cubit.state, isA<HomeReconnectPrompt>());
        await cubit.answerPrompt(useSaved: true);
        expect(cubit.state, HomeLoaded(_doc, aircraft: _cessna));
        expect(progress.promptAnswers, [true]);
      },
    );

    test('popup request while paused is shown after resume', () async {
      await connectedAndLoaded();
      progress.forcedReconnect = const AttachNeedsPrompt();
      cubit.appPaused();
      sim.setStatus(const ConnectionNoNetwork());
      await pumpEventQueue();
      sim.setStatus(const ConnectionConnected());
      await pumpEventQueue();
      expect(cubit.state, isA<HomeLoaded>());
      cubit.appResumed();
      expect(cubit.state, isA<HomeReconnectPrompt>());
    });

    test('resume without a deferred prompt changes nothing', () async {
      await connectedAndLoaded();
      cubit.appPaused();
      cubit.appResumed();
      expect(cubit.state, isA<HomeLoaded>());
    });
  });

  group('reload', () {
    AircraftIdentity edited(int modified, {int generation = 1}) =>
        AircraftIdentity(
          icao: _cessna.icao,
          description: _cessna.description,
          aircraftPath: _cessna.aircraftPath,
          checklistPath: _cessna.checklistPath,
          checklistModified: modified,
          checklistSize: 100,
          generation: generation,
        );

    final second = ChecklistDocument(
      checklists: const [],
      warnings: const ['edited'],
      sourceName: 'a.txt',
    );

    test('reload with unchanged file keeps list and marks', () async {
      sim.setAircraft(edited(1));
      sim.setStatus(const ConnectionConnected());
      await pumpEventQueue();
      progress.toggle('X', 0);
      final states = <HomeState>[];
      final sub = cubit.stream.listen(states.add);
      sim.setAircraft(edited(1, generation: 5));
      await pumpEventQueue();
      expect(checklists.loadCount, 1);
      expect(states, isEmpty);
      expect(progress.current.isChecked('X', 0), isTrue);
      await sub.cancel();
    });

    test('reload after an edited file shows the new items without reopening '
        'the list', () async {
      sim.setAircraft(edited(1));
      sim.setStatus(const ConnectionConnected());
      await pumpEventQueue();
      progress.toggle('X', 0);
      final checklistsRepo = checklists;
      checklistsRepo.emit(second);
      final states = <HomeState>[];
      final sub = cubit.stream.listen(states.add);
      sim.setAircraft(edited(2));
      await pumpEventQueue();
      expect(checklists.loadCount, 2);
      expect(states.single, isA<HomeLoaded>());
      expect((states.single as HomeLoaded).aircraft, edited(2));
      expect(progress.current.isChecked('X', 0), isTrue);
      await sub.cancel();
    });

    test('a different aircraft is never refreshed', () async {
      sim.setAircraft(edited(1));
      sim.setStatus(const ConnectionConnected());
      await pumpEventQueue();
      sim.setAircraft(_boeing);
      await pumpEventQueue();
      expect(checklists.loadCount, 1);
    });
  });
}
