import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/services/local/model/stored_progress.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/checklist/attach_outcome.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_fingerprint.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/services/in_memory_progress_storage_service.dart';

// AC-35: manual wins in the repository: auto, manual uncheck, auto again stays unchecked
// AC-43: both sets are saved and restored
// AC-44: restored marks stay, evaluation only adds, a reset starts over

Checklist _list(String name, int checks) => Checklist(
  name: name,
  title: name,
  items: [
    for (var i = 0; i < checks; i++)
      ChecklistItem(ChecklistItemType.check, '$name item $i'),
  ],
);

final _doc = ChecklistDocument(
  checklists: [_list('Start', 4), _list('Shutdown', 2)],
  warnings: const [],
);

const _ac = 'ac.acf';
final _aircraft = const AircraftIdentity(
  icao: 'X',
  description: 'Plane',
  aircraftPath: _ac,
);

void main() {
  late InMemoryProgressStorageService storage;
  late ChecklistProgressRepositoryImpl repo;

  setUp(() {
    storage = InMemoryProgressStorageService();
    repo = ChecklistProgressRepositoryImpl(storage: storage);
  });
  tearDown(() => repo.dispose());

  Future<AttachOutcome> attach({String? runId = 'run-1'}) =>
      repo.attach(_doc, aircraft: _aircraft, runId: runId);

  group('autoCheck (6.3)', () {
    test('marks the items checked and auto-checked and emits once', () async {
      final seen = [];
      repo.progress.listen(seen.add);
      repo.autoCheck('Start', [1, 2]);
      await pumpEventQueue();
      expect(repo.current.checked['Start'], {1, 2});
      expect(repo.current.autoChecked['Start'], {1, 2});
      expect(seen, hasLength(1));
    });

    test('nothing new emits nothing', () async {
      repo.autoCheck('Start', [1]);
      final seen = [];
      repo.progress.listen(seen.add);
      repo.autoCheck('Start', [1]);
      repo.autoCheck('Start', const []);
      await pumpEventQueue();
      expect(seen, isEmpty);
    });

    test('an untick is not remembered (D-78): the cubit holds auto off', () {
      repo.autoCheck('Start', [1]);
      repo.toggle('Start', 1);
      expect(repo.current.isChecked('Start', 1), isFalse);
    });

    test('checking by hand after an untick is not auto', () {
      repo.autoCheck('Start', [1]);
      repo.toggle('Start', 1);
      repo.toggle('Start', 1);
      expect(repo.current.isChecked('Start', 1), isTrue);
      expect(repo.current.isAutoChecked('Start', 1), isFalse);
    });

    test(
      'the checked and auto sets are saved, nothing is kept for unticks',
      () async {
        await attach();
        repo.autoCheck('Start', [1, 2]);
        repo.toggle('Start', 2);
        await pumpEventQueue();
        final saved = storage.records[_ac]!.checklists['Start']!;
        expect(saved.checked, [1]);
        expect(saved.autoChecked, [1]);
      },
    );
  });

  group('restore (6.5)', () {
    StoredProgress seed({
      List<int> checked = const [],
      List<int> auto = const [],
      String fingerprint = '',
    }) => storage.records[_ac] = StoredProgress(
      runId: 'run-1',
      checklists: {
        'Start': StoredChecklistProgress(
          checked: checked,
          autoChecked: auto,
          fingerprint: fingerprint.isEmpty
              ? fingerprintOf(_doc.checklists.first)
              : fingerprint,
        ),
      },
    );

    test('a restore brings back checks and auto marks', () async {
      seed(checked: [0, 1], auto: [1]);
      final outcome = await attach();
      expect(outcome, isA<AttachRestored>());
      expect(repo.current.checked['Start'], {0, 1});
      expect(repo.current.autoChecked['Start'], {1});
    });

    test('evaluation after a restore only adds', () async {
      seed(checked: [0]);
      await attach();
      repo.autoCheck('Start', [0, 2, 3]);
      expect(repo.current.checked['Start'], {0, 2, 3});
      expect(repo.current.autoChecked['Start'], {2, 3});
    });

    test('a changed checklist drops all its marks (fingerprint)', () async {
      seed(checked: [0], auto: [0], fingerprint: 'old');
      await attach();
      expect(repo.current.checked, isEmpty);
    });

    test(
      'an auto mark on an unchecked item and a bad index are dropped',
      () async {
        seed(checked: [0], auto: [0, 1, 99]);
        await attach();
        expect(repo.current.autoChecked['Start'], {0});
      },
    );

    test('a version 1 style record (no sets) restores the checks', () async {
      seed(checked: [2]);
      await attach();
      expect(repo.current.checked['Start'], {2});
      expect(repo.current.autoChecked, isEmpty);
    });
  });

  group('reset (6.6)', () {
    test('reset and resetAll clear the sets, so a met item checks again', () {
      repo.autoCheck('Start', [0]);
      repo.toggle('Start', 0);
      repo.reset('Start');
      repo.autoCheck('Start', [0]);
      expect(repo.current.isChecked('Start', 0), isTrue);

      repo.toggle('Start', 0);
      repo.resetAll();
      expect(repo.current.checked, isEmpty);
      repo.autoCheck('Start', [0]);
      expect(repo.current.isAutoChecked('Start', 0), isTrue);
    });

    test('attaching another aircraft clears the sets', () async {
      await attach();
      repo.autoCheck('Start', [0]);
      repo.toggle('Start', 1);
      await repo.attach(
        _doc,
        aircraft: const AircraftIdentity(
          icao: 'Y',
          description: 'Other',
          aircraftPath: 'other.acf',
        ),
        runId: 'run-1',
      );
      expect(repo.current.autoChecked, isEmpty);
    });
  });
}
