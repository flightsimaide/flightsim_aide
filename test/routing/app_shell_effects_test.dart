import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository.dart';
import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_local.dart';
import 'package:flightsim_aide/data/repositories/settings/settings_repository.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../testing/fakes/repositories/fake_checklist_repository.dart';
import '../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../testing/fakes/services/in_memory_progress_storage_service.dart';

const _cessna = AircraftIdentity(
  icao: 'C172',
  description: 'Cessna 172',
  aircraftPath: 'a.acf',
  checklistPath: 'clist.txt',
  generation: 1,
);

final _doc = ChecklistDocument(
  checklists: [
    Checklist(
      name: 'Taxi',
      title: 'Taxi',
      items: const [ChecklistItem(ChecklistItemType.check, 'Lights')],
    ),
  ],
  warnings: const [],
  sourceName: 'a.txt',
);

void main() {
  late FlightSimRepositoryLocal sim;
  late FakeChecklistRepository checklists;
  late FakeChecklistProgressRepository progress;
  late InMemoryProgressStorageService storage;

  Future<void> pumpApp(WidgetTester tester, {bool withSim = true}) async {
    sim = FlightSimRepositoryLocal();
    storage = InMemoryProgressStorageService();
    checklists = FakeChecklistRepository(loadResults: [Ok(_doc)]);
    progress = FakeChecklistProgressRepository(storage: storage);
    final router = createRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ChecklistRepository>.value(value: checklists),
          RepositoryProvider<ChecklistProgressRepository>.value(
            value: progress,
          ),
          if (withSim) ...[
            RepositoryProvider<FlightSimRepository>.value(value: sim),
            RepositoryProvider<SettingsRepository>.value(
              value: FakeSettingsRepository(),
            ),
          ],
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await checklists.dispose();
    await sim.dispose();
  }

  testWidgets('backgrounding pauses the link and notes the time; coming back '
      'resumes', (tester) async {
    await pumpApp(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(sim.pauses, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(sim.resumes, 1);
    await finish(tester);
  });

  testWidgets('without a simulator, lifecycle changes are harmless', (
    tester,
  ) async {
    await pumpApp(tester, withSim: false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('a failed save shows a warning and keeps the marks', (
    tester,
  ) async {
    await pumpApp(tester);
    sim.setAircraft(_cessna);
    sim.setStatus(const ConnectionConnected());
    await tester.pumpAndSettle();
    await tester.runAsync(pumpEventQueue);
    storage.failWrites = true;
    progress.toggle('Taxi', 0);
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
    expect(
      find.text('Could not save your progress on this device.'),
      findsOneWidget,
    );
    expect(progress.current.isChecked('Taxi', 0), isTrue);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    await finish(tester);
  });
}
