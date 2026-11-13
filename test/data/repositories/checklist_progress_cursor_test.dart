import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/services/local/model/stored_progress.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_fingerprint.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/services/in_memory_progress_storage_service.dart';

// AC-35: the cursor follows the pilot and is kept (D-71, repository half)
// AC-43: the cursor and the disagreed marks are saved and restored

Checklist _list(String name, int checks) => Checklist(
  name: name,
  title: name,
  items: [
    for (var i = 0; i < checks; i++)
      ChecklistItem(ChecklistItemType.check, '$name item $i'),
    const ChecklistItem(ChecklistItemType.note, 'a note'),
  ],
);

final _doc = ChecklistDocument(
  checklists: [_list('Start', 4), _list('Shutdown', 2)],
  warnings: const [],
);

const _ac = 'ac.acf';
const _aircraft = AircraftIdentity(
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

  Future<void> attach() => repo.attach(_doc, aircraft: _aircraft, runId: 'r');

  group('toggle and autoCheck pass the new arguments on', () {
    test('toggle with disagrees marks the item and moves the cursor', () {
      repo.toggle('Start', 2, disagrees: true);
      expect(repo.current.isChecked('Start', 2), isTrue);
      expect(repo.current.isDisagreed('Start', 2), isTrue);
      expect(repo.current.cursorOf('Start'), 2);
    });

    test('toggle without the flag keeps the original call working', () {
      repo.toggle('Start', 1);
      expect(repo.current.isChecked('Start', 1), isTrue);
      expect(repo.current.isDisagreed('Start', 1), isFalse);
    });

    test('autoCheck with a cursor moves it forward and emits once', () async {
      final seen = [];
      repo.progress.listen(seen.add);
      repo.autoCheck('Start', [0, 1], cursor: 2);
      await pumpEventQueue();
      expect(repo.current.cursorOf('Start'), 2);
      expect(seen, hasLength(1));
    });

    test('autoCheck that only moves the cursor still emits', () async {
      final seen = [];
      repo.progress.listen(seen.add);
      repo.autoCheck('Start', const [], cursor: 3);
      await pumpEventQueue();
      expect(repo.current.cursorOf('Start'), 3);
      expect(seen, hasLength(1));
    });

    test('autoCheck with nothing new emits nothing', () async {
      repo.autoCheck('Start', [0], cursor: 1);
      final seen = [];
      repo.progress.listen(seen.add);
      repo.autoCheck('Start', [0], cursor: 1);
      repo.autoCheck('Start', const [], cursor: 0);
      await pumpEventQueue();
      expect(seen, isEmpty);
    });

    test('reset puts the cursor at the top and clears the marks', () {
      repo.toggle('Start', 2, disagrees: true);
      repo.reset('Start');
      expect(repo.current.cursorOf('Start'), 0);
      expect(repo.current.disagreed, isEmpty);
    });
  });

  group('persistence', () {
    test('the cursor and the marks are saved', () async {
      await attach();
      repo.toggle('Start', 2, disagrees: true);
      await pumpEventQueue();
      final saved = storage.records[_ac]!.checklists['Start']!;
      expect(saved.cursor, 2);
      expect(saved.disagreed, [2]);
    });

    test('a cursor with nothing checked is still saved', () async {
      await attach();
      repo.autoCheck('Start', const [], cursor: 3);
      await pumpEventQueue();
      expect(storage.records[_ac]!.checklists['Start']!.cursor, 3);
    });

    StoredProgress seed({
      List<int> checked = const [],
      List<int> disagreed = const [],
      int cursor = 0,
      String? fingerprint,
    }) => storage.records[_ac] = StoredProgress(
      runId: 'r',
      checklists: {
        'Start': StoredChecklistProgress(
          checked: checked,
          disagreed: disagreed,
          cursor: cursor,
          fingerprint: fingerprint ?? fingerprintOf(_doc.checklists.first),
        ),
      },
    );

    test('a restore brings the cursor and the marks back', () async {
      seed(checked: [0, 2], disagreed: [2], cursor: 3);
      await attach();
      expect(repo.current.cursorOf('Start'), 3);
      expect(repo.current.isDisagreed('Start', 2), isTrue);
    });

    test('a cursor past the end is clamped to the item count', () async {
      seed(checked: [0], cursor: 99);
      await attach();
      expect(
        repo.current.cursorOf('Start'),
        _doc.checklists.first.items.length,
      );
    });

    test('a disagreed mark on an unchecked or bad index is dropped', () async {
      seed(checked: [0], disagreed: [0, 1, 99]);
      await attach();
      expect(repo.current.disagreed['Start'], {0});
    });

    test('a changed checklist drops the cursor and the marks', () async {
      seed(checked: [0], disagreed: [0], cursor: 2, fingerprint: 'old');
      await attach();
      expect(repo.current.cursorOf('Start'), 0);
      expect(repo.current.disagreed, isEmpty);
    });

    test(
      'a saved version 2 style record restores with the cursor at 0',
      () async {
        seed(checked: [0, 1]);
        await attach();
        expect(repo.current.checked['Start'], {0, 1});
        expect(repo.current.cursorOf('Start'), 0);
      },
    );
  });
}
