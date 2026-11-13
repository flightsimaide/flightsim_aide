import 'package:flightsim_aide/app.dart';
import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository_impl.dart';
import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository.dart';
import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_local.dart';
import 'package:flightsim_aide/data/repositories/settings/settings_repository.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/ui/checklist_list/widgets/checklist_list_screen.dart';
import 'package:flightsim_aide/ui/home/widgets/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../testing/e2e_harness.dart';
import '../testing/fakes/repositories/fake_settings_repository.dart';
import '../testing/fakes/services/in_memory_progress_storage_service.dart';

// Task 0.15: the plugin's run id tells an X-Plane restart from the same run
// AC-16: the same run restores marks and last viewed silently, and stays on Home
// AC-18: a new X-Plane run prompts; both answers work
// AC-19: an unknown run id prompts
// AC-20: edited checklist drops only its own marks
// AC-17: reworked by task 0.15, the shutdown rule is gone
// AC-28: reworked by task 0.15, the 30-minute gap is replaced by the run id

const _cessna = AircraftIdentity(
  icao: 'C172',
  description: 'Cessna 172',
  aircraftPath: 'Aircraft/C172/c172.acf',
  checklistPath: 'Aircraft/C172/clist.txt',
  generation: 1,
);

const _file = '''
sw_checklist:Start:Start
sw_item:Battery|ON
sw_item:Fuel|OPEN
sw_checklist:Shutdown:Shutdown
sw_item:Engine|OFF
sw_item:Battery|OFF
''';

/// The same file with the first Start item reworded.
const _editedFile = '''
sw_checklist:Start:Start
sw_item:Master|ON
sw_item:Fuel|OPEN
sw_checklist:Shutdown:Shutdown
sw_item:Engine|OFF
sw_item:Battery|OFF
''';

/// One run of the app. The storage outlives it, like the files outlive a real
/// app process; [runId] is what the plugin reports for that X-Plane run.
class _Run {
  _Run(this.tester, this.storage, {String text = _file})
    : sim = FlightSimRepositoryLocal(),
      progress = ChecklistProgressRepositoryImpl(storage: storage),
      checklists = ChecklistRepositoryImpl(
        source: textSource('clist.txt', text),
        parser: const AircraftWorkflowParser(),
      );

  final WidgetTester tester;
  final InMemoryProgressStorageService storage;
  final FlightSimRepositoryLocal sim;
  final ChecklistProgressRepositoryImpl progress;
  final ChecklistRepositoryImpl checklists;

  /// Starts the app and connects the sim with the given run id.
  Future<void> start({required String? runId}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      App(
        providers: [
          RepositoryProvider<ChecklistRepository>.value(value: checklists),
          RepositoryProvider<ChecklistProgressRepository>.value(
            value: progress,
          ),
          RepositoryProvider<FlightSimRepository>.value(value: sim),
          RepositoryProvider<SettingsRepository>.value(
            value: FakeSettingsRepository(),
          ),
        ],
      ),
    );
    sim.setAircraft(_cessna);
    sim.runId = runId;
    sim.setStatus(const ConnectionConnected());
    await tester.pumpAndSettle();
  }

  /// Closes the app like a process exit, after pending saves have run.
  Future<void> end() async {
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await sim.dispose();
    await progress.dispose();
  }
}

void main() {
  late InMemoryProgressStorageService storage;

  setUp(() {
    storage = InMemoryProgressStorageService();
  });

  /// First run (X-Plane run `run-1`): tick [marks], optionally set the last
  /// viewed checklist, quit.
  Future<void> firstFlight(
    WidgetTester tester, {
    Map<String, List<int>> marks = const {
      'Start': [0, 1],
    },
    String? lastViewed,
    String? runId = 'run-1',
  }) async {
    final run = _Run(tester, storage);
    await run.start(runId: runId);
    for (final entry in marks.entries) {
      for (final index in entry.value) {
        run.progress.toggle(entry.key, index);
      }
    }
    if (lastViewed != null) run.progress.setLastViewed(lastViewed);
    await run.end();
  }

  testWidgets(
    'the same X-Plane run restores marks and last viewed silently, and stays on Home',
    (tester) async {
      await firstFlight(tester, lastViewed: 'Start');
      final run = _Run(tester, storage);
      await run.start(runId: 'run-1');
      expect(run.progress.current.checked['Start'], {0, 1});
      expect(run.progress.lastViewed, 'Start');
      // Silent restore: the app stays on Home (it opens nothing by itself).
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ChecklistListScreen), findsNothing);
      expect(find.text('Use saved progress'), findsNothing);
      await run.end();
    },
  );

  testWidgets('a new X-Plane run asks, and using saved progress works', (
    tester,
  ) async {
    await firstFlight(tester);
    final run = _Run(tester, storage);
    await run.start(runId: 'run-2');
    expect(find.text('Use saved progress'), findsOneWidget);
    expect(run.progress.current.checked, isEmpty);
    await tester.tap(find.text('Use saved progress'));
    await tester.pumpAndSettle();
    expect(run.progress.current.checked['Start'], {0, 1});
    expect(find.byType(ChecklistListScreen), findsOneWidget);
    await run.end();
  });

  testWidgets('a new X-Plane run asks, and reset works', (tester) async {
    await firstFlight(tester);
    final run = _Run(tester, storage);
    await run.start(runId: 'run-2');
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(run.progress.current.checked, isEmpty);
    await run.end();
    final again = _Run(tester, storage);
    await again.start(runId: 'run-2');
    expect(find.text('Use saved progress'), findsNothing);
    expect(again.progress.current.checked, isEmpty);
    await again.end();
  });

  testWidgets('an unknown run id asks', (tester) async {
    await firstFlight(tester, runId: null);
    final run = _Run(tester, storage);
    await run.start(runId: null);
    expect(find.text('Use saved progress'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await run.end();
  });

  testWidgets('unreadable saved data starts clean', (tester) async {
    await firstFlight(tester);
    storage.records.clear();
    final run = _Run(tester, storage);
    await run.start(runId: 'run-1');
    expect(run.progress.current.checked, isEmpty);
    expect(find.text('Use saved progress'), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(ChecklistListScreen), findsNothing);
    await run.end();
  });

  testWidgets("an edited checklist file drops only the changed checklist's "
      'marks', (tester) async {
    await firstFlight(
      tester,
      marks: {
        'Start': [0],
        'Shutdown': [0],
      },
    );
    final run = _Run(tester, storage, text: _editedFile);
    await run.start(runId: 'run-1');
    expect(run.progress.current.checked.containsKey('Start'), isFalse);
    expect(run.progress.current.checked['Shutdown'], {0});
    await run.end();
  });

  testWidgets('after using saved progress, the next new run asks again', (
    tester,
  ) async {
    await firstFlight(tester);
    final run = _Run(tester, storage);
    await run.start(runId: 'run-2');
    await tester.tap(find.text('Use saved progress'));
    await tester.pumpAndSettle();
    await run.end();
    final again = _Run(tester, storage);
    await again.start(runId: 'run-3');
    expect(find.text('Use saved progress'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await again.end();
  });
}
