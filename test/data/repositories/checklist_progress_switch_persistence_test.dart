import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/services/local/model/stored_progress.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/checklist/attach_outcome.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_fingerprint.dart';
import 'package:flightsim_aide/domain/models/checklist/switch_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/services/in_memory_progress_storage_service.dart';

// Switches (D-82): the positions that differ from the default are saved with
// the progress, by id. Rows: 0 Before, 1 Use GPU (switch, default OFF),
// 2 GPU, 3 GPU power (ON branch), 4 After.
const _text = '''
sw_checklist:Start
sw_item:Before|ON
sw_switch:Use GPU|gpu|OFF
sw_item:GPU|ON
sw_item:GPU power|ON
sw_end
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
  late SwitchDef gpu;

  setUp(() {
    document = const AircraftWorkflowParser().parse(_text);
    gpu = document.checklists.single.items[1].switchDef!;
    storage = InMemoryProgressStorageService();
    repo = ChecklistProgressRepositoryImpl(storage: storage);
  });
  tearDown(() => repo.dispose());

  Future<AttachOutcome> attach() =>
      repo.attach(document, aircraft: _aircraft, runId: 'run-1');

  void flip({required bool on}) =>
      repo.setSwitch(document.checklists, gpu, on: on);

  test('a position that differs from the default is saved, by id', () async {
    await attach();
    flip(on: true);
    await pumpEventQueue();
    expect(storage.records['a.acf']!.switches, {'gpu': true});
  });

  test('back at the default, nothing is kept', () async {
    await attach();
    flip(on: true);
    flip(on: false);
    await pumpEventQueue();
    expect(storage.records['a.acf']!.checklists, isEmpty);
    expect(storage.records['a.acf']!.switches, isEmpty);
  });

  test('a saved switch comes back with the ticks it was saved with', () async {
    final checklist = document.checklists.single;
    storage.records['a.acf'] = StoredProgress(
      runId: 'run-1',
      switches: const {'gpu': true},
      checklists: {
        'Start': StoredChecklistProgress(
          checked: const [2],
          fingerprint: fingerprintOf(checklist),
        ),
      },
    );
    final outcome = await attach();
    expect(outcome, isA<AttachRestored>());
    expect(repo.current.isSwitchOn(gpu), isTrue);
    expect(repo.current.isChecked('Start', 2), isTrue);
    expect(repo.current.countsFor(checklist).total, 5);
  });

  test(
    'a saved file without switches restores them all at the default',
    () async {
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
      expect(repo.current.isSwitchOn(gpu), isFalse);
      expect(repo.current.countsFor(checklist).total, 3);
    },
  );

  test(
    'a saved switch the file does not define, or at its default, goes',
    () async {
      final checklist = document.checklists.single;
      storage.records['a.acf'] = StoredProgress(
        runId: 'run-1',
        switches: const {'nope': true, 'gpu': false},
        checklists: {
          'Start': StoredChecklistProgress(
            checked: const [0],
            fingerprint: fingerprintOf(checklist),
          ),
        },
      );
      await attach();
      expect(repo.current.switches, isEmpty);
    },
  );

  test('a switch saved alone, with no ticks, is not brought back', () async {
    storage.records['a.acf'] = const StoredProgress(
      runId: 'run-1',
      switches: {'gpu': true},
    );
    final outcome = await attach();
    expect(outcome, isA<AttachClean>());
    expect(repo.current.isSwitchOn(gpu), isFalse);
  });

  test('a changed checklist drops its marks', () async {
    storage.records['a.acf'] = const StoredProgress(
      runId: 'run-1',
      switches: {'gpu': true},
      checklists: {
        'Start': StoredChecklistProgress(
          checked: [0],
          fingerprint: 'not-the-fingerprint',
        ),
      },
    );
    await attach();
    expect(repo.current.checked, isEmpty, reason: 'the marks are dropped');
  });

  test('Reset keeps the saved switch and resetAll drops it', () async {
    await attach();
    flip(on: true);
    repo.toggle('Start', 2);
    repo.reset('Start');
    await pumpEventQueue();
    expect(storage.records['a.acf']!.switches, {'gpu': true});
    repo.resetAll();
    await pumpEventQueue();
    expect(storage.records['a.acf']!.checklists, isEmpty);
    expect(storage.records['a.acf']!.switches, isEmpty);
  });
}
