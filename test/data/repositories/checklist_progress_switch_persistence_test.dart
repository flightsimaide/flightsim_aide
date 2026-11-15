import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/services/local/model/stored_progress.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/checklist/attach_outcome.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/services/in_memory_progress_storage_service.dart';

// Switch blocks (D-82): the switch positions are saved with the progress.
// Rows: 0 Before, 1 Use GPU (switch), 2 GPU, 3 GPU power, 4 After.
const _text = '''
sw_checklist:Start
sw_item:Before|ON
sw_enable_start:Use GPU
sw_item:GPU|ON
sw_item:GPU power|ON
sw_enable_end
sw_item:After|ON
''';

const _aircraft = AircraftIdentity(
  icao: 'X',
  description: 'Plane',
  aircraftPath: 'a.acf',
);

void main() {
  late ChecklistDocument document;
  late InMemoryProgressStorageService storage;
  late ChecklistProgressRepositoryImpl repo;

  setUp(() {
    document = const AircraftWorkflowParser().parse(_text);
    storage = InMemoryProgressStorageService();
    repo = ChecklistProgressRepositoryImpl(storage: storage);
  });
  tearDown(() => repo.dispose());

  Future<AttachOutcome> attach() =>
      repo.attach(document, aircraft: _aircraft, runId: 'run-1');

  test('turning a switch on is saved, with no tick yet', () async {
    await attach();
    repo.setOption(document.checklists.single, 1, on: true);
    await pumpEventQueue();
    expect(storage.records['a.acf']!.checklists['Start']!.enabled, [1]);
  });

  test(
    'turning it off is saved and the entry goes when nothing is left',
    () async {
      await attach();
      repo.setOption(document.checklists.single, 1, on: true);
      repo.setOption(document.checklists.single, 1, on: false);
      await pumpEventQueue();
      expect(storage.records['a.acf']!.checklists, isEmpty);
    },
  );

  test('a saved switch comes back with the ticks it was saved with', () async {
    final checklist = document.checklists.single;
    storage.records['a.acf'] = StoredProgress(
      runId: 'run-1',
      checklists: {
        'Start': StoredChecklistProgress(
          checked: const [2],
          enabled: const [1],
          fingerprint: fingerprintOf(checklist),
        ),
      },
    );
    final outcome = await attach();
    expect(outcome, isA<AttachRestored>());
    expect(repo.current.isOptionOn('Start', 1), isTrue);
    expect(repo.current.isChecked('Start', 2), isTrue);
    expect(repo.current.countsFor(checklist).total, 5);
  });

  test('a saved file without switches restores them all off', () async {
    final checklist = document.checklists.single;
    storage.records['a.acf'] = StoredProgress(
      runId: 'run-1',
      checklists: {
        'Start': StoredChecklistProgress(
          checked: const [0],
          fingerprint: fingerprintOf(checklist),
        ),
      },
    );
    await attach();
    expect(repo.current.isOptionOn('Start', 1), isFalse);
    expect(repo.current.countsFor(checklist).total, 3);
  });

  test('a saved switch on a row that is not a switch is ignored', () async {
    final checklist = document.checklists.single;
    storage.records['a.acf'] = StoredProgress(
      runId: 'run-1',
      checklists: {
        'Start': StoredChecklistProgress(
          checked: const [0],
          enabled: const [0, 2, 99],
          fingerprint: fingerprintOf(checklist),
        ),
      },
    );
    await attach();
    expect(repo.current.enabled, isEmpty);
  });

  test('a changed checklist drops its saved switches', () async {
    storage.records['a.acf'] = const StoredProgress(
      runId: 'run-1',
      checklists: {
        'Start': StoredChecklistProgress(
          checked: [0],
          enabled: [1],
          fingerprint: 'not-the-fingerprint',
        ),
      },
    );
    await attach();
    expect(repo.current.isOptionOn('Start', 1), isFalse);
  });

  test('Reset keeps the saved switch and resetAll drops it', () async {
    await attach();
    repo.setOption(document.checklists.single, 1, on: true);
    repo.toggle('Start', 2);
    repo.reset('Start');
    await pumpEventQueue();
    expect(storage.records['a.acf']!.checklists['Start']!.enabled, [1]);
    repo.resetAll();
    await pumpEventQueue();
    expect(storage.records['a.acf']!.checklists, isEmpty);
  });
}
