import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/services/local/model/stored_progress.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/checklist/attach_outcome.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_fingerprint.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/services/in_memory_progress_storage_service.dart';

// AC-20: fingerprint filtering on restore
// Task 0.15: the run id decides restore and reconnect

Checklist _list(String name, int checks) => Checklist(
  name: name,
  title: name,
  items: [
    for (var i = 0; i < checks; i++)
      ChecklistItem(ChecklistItemType.check, '$name item $i'),
  ],
);

ChecklistDocument _doc([List<Checklist>? lists]) => ChecklistDocument(
  checklists: lists ?? [_list('Start', 3), _list('Shutdown', 2)],
  warnings: const [],
);

AircraftIdentity _aircraft(String path) =>
    AircraftIdentity(icao: 'X', description: 'Plane $path', aircraftPath: path);

const _ac1 = 'ac1.acf';
const _ac2 = 'ac2.acf';

void main() {
  group('mode and skipped items', _modeAndSkipTests);
  late InMemoryProgressStorageService storage;
  late ChecklistProgressRepositoryImpl repo;

  ChecklistProgressRepositoryImpl build({
    InMemoryProgressStorageService? withStorage,
  }) => ChecklistProgressRepositoryImpl(storage: withStorage ?? storage);

  setUp(() {
    storage = InMemoryProgressStorageService();
    repo = build();
  });
  tearDown(() => repo.dispose());

  StoredProgress seed(
    String path,
    Map<String, List<int>> marks, {
    String? runId = 'run-1',
    String? lastViewed,
    ChecklistDocument? document,
  }) {
    final doc = document ?? _doc();
    final record = StoredProgress(
      lastViewed: lastViewed,
      runId: runId,
      checklists: {
        for (final e in marks.entries)
          e.key: StoredChecklistProgress(
            checked: e.value,
            fingerprint: fingerprintOf(
              doc.checklists.firstWhere((c) => c.name == e.key),
            ),
          ),
      },
    );
    storage.records[path] = record;
    return record;
  }

  Future<AttachOutcome> attach(
    String path, {
    String? runId = 'run-1',
    ChecklistDocument? document,
  }) =>
      repo.attach(document ?? _doc(), aircraft: _aircraft(path), runId: runId);

  group('persist on every change', () {
    test('toggle writes immediately', () async {
      await attach(_ac1);
      storage.writes.clear();
      repo.toggle('Start', 2);
      repo.toggle('Start', 0);
      await pumpEventQueue();
      final saved = storage.records[_ac1]!;
      expect(saved.checklists['Start']!.checked, [0, 2]);
      expect(saved.checklists['Start']!.fingerprint, isNotEmpty);
    });

    test('reset and resetAll write', () async {
      await attach(_ac1);
      repo.toggle('Start', 0);
      repo.toggle('Shutdown', 1);
      await pumpEventQueue();
      repo.reset('Start');
      await pumpEventQueue();
      expect(storage.records[_ac1]!.checklists.keys, ['Shutdown']);
      repo.resetAll();
      await pumpEventQueue();
      expect(storage.records[_ac1]!.checklists, isEmpty);
    });

    test('last viewed is written', () async {
      await attach(_ac1);
      repo.setLastViewed('Shutdown');
      await pumpEventQueue();
      expect(repo.lastViewed, 'Shutdown');
      expect(storage.records[_ac1]!.lastViewed, 'Shutdown');
    });

    test('no storage service means in-memory only', () async {
      final plain = ChecklistProgressRepositoryImpl();
      addTearDown(plain.dispose);
      final outcome = await plain.attach(_doc(), aircraft: _aircraft(_ac1));
      plain.toggle('Start', 1);
      await pumpEventQueue();
      expect(outcome, const AttachClean());
      expect(plain.current.isChecked('Start', 1), isTrue);
    });

    test('failed write keeps in-memory state and reports', () async {
      await attach(_ac1);
      await pumpEventQueue();
      final errors = <AppException>[];
      repo.persistenceErrors.listen(errors.add);
      storage.failWrites = true;
      repo.toggle('Start', 1);
      await pumpEventQueue();
      expect(repo.current.isChecked('Start', 1), isTrue);
      expect(errors, hasLength(1));
    });

    test('rapid toggles end with the final state on disk', () async {
      await attach(_ac1);
      for (var i = 0; i < 3; i++) {
        repo.toggle('Start', i);
      }
      repo.toggle('Start', 1);
      await pumpEventQueue();
      expect(storage.records[_ac1]!.checklists['Start']!.checked, [0, 2]);
    });

    test('toggle stamps the run id', () async {
      await attach(_ac1, runId: 'run-9');
      repo.toggle('Start', 0);
      await pumpEventQueue();
      expect(storage.records[_ac1]!.runId, 'run-9');
    });

    test('nothing is written while no aircraft is attached', () async {
      repo.toggle('Start', 0);
      repo.setLastViewed('Start');
      await pumpEventQueue();
      expect(storage.callCount, 0);
    });
  });

  group('attach executes the policy', () {
    test('no saved progress is clean', () async {
      expect(await attach(_ac1), const AttachClean());
      expect(repo.current.checked, isEmpty);
    });

    test(
      'the same run id restores silently and returns the last viewed name',
      () async {
        seed(_ac1, {
          'Start': [0, 1],
        }, lastViewed: 'Start');
        final outcome = await attach(_ac1);
        expect(outcome, const AttachRestored('Start'));
        expect(repo.current.isChecked('Start', 1), isTrue);
        expect(repo.lastViewed, 'Start');
      },
    );

    test(
      'a different run id returns needsPrompt and leaves progress empty',
      () async {
        seed(_ac1, {
          'Start': [0],
        });
        expect(await attach(_ac1, runId: 'run-2'), const AttachNeedsPrompt());
        expect(repo.current.checked, isEmpty);
      },
    );

    test('an unknown run id returns needsPrompt', () async {
      seed(_ac1, {
        'Start': [0],
      });
      expect(await attach(_ac1, runId: null), const AttachNeedsPrompt());
    });

    test('marks saved with no run id are asked about', () async {
      seed(_ac1, {
        'Start': [0],
      }, runId: null);
      expect(await attach(_ac1), const AttachNeedsPrompt());
    });

    test('the prompt changes nothing on disk', () async {
      final record = seed(_ac1, {
        'Start': [0],
      });
      await attach(_ac1, runId: 'run-2');
      await pumpEventQueue();
      expect(storage.records[_ac1], record);
      expect(storage.writes, isEmpty);
    });

    test('resolvePrompt(useSaved) restores and saves the new run id', () async {
      seed(_ac1, {
        'Start': [0, 2],
      }, lastViewed: 'Start');
      await attach(_ac1, runId: 'run-2');
      await repo.resolvePrompt(useSaved: true);
      await pumpEventQueue();
      expect(repo.current.isChecked('Start', 2), isTrue);
      expect(repo.lastViewed, 'Start');
      expect(storage.records[_ac1]!.runId, 'run-2');
    });

    test('resolvePrompt(reset) clears and persists', () async {
      seed(_ac1, {
        'Start': [0],
      });
      await attach(_ac1, runId: 'run-2');
      await repo.resolvePrompt(useSaved: false);
      await pumpEventQueue();
      expect(repo.current.checked, isEmpty);
      expect(storage.records[_ac1]!.checklists, isEmpty);
      expect(storage.records[_ac1]!.runId, 'run-2');
    });

    test('resolvePrompt without a pending prompt does nothing', () async {
      await attach(_ac1);
      repo.toggle('Start', 0);
      await repo.resolvePrompt(useSaved: false);
      expect(repo.current.isChecked('Start', 0), isTrue);
    });

    test(
      'app restart between prompt and answer gets the same prompt again',
      () async {
        seed(_ac1, {
          'Start': [0],
        });
        await attach(_ac1, runId: 'run-2');
        final second = build();
        addTearDown(second.dispose);
        expect(
          await second.attach(
            _doc(),
            aircraft: _aircraft(_ac1),
            runId: 'run-2',
          ),
          const AttachNeedsPrompt(),
        );
      },
    );

    test('attach saves the current run id', () async {
      seed(_ac1, {
        'Start': [0],
      });
      await attach(_ac1);
      await pumpEventQueue();
      expect(storage.records[_ac1]!.runId, 'run-1');
    });

    test('a saved record with no marks starts clean', () async {
      storage.records[_ac1] = const StoredProgress(lastViewed: 'Start');
      expect(await attach(_ac1), const AttachClean());
    });
  });

  group('fingerprint filtering on restore', () {
    test('unchanged checklist keeps marks', () async {
      seed(_ac1, {
        'Start': [1],
      });
      await attach(_ac1);
      expect(repo.current.isChecked('Start', 1), isTrue);
    });

    test('edited checklist loses only its own marks', () async {
      seed(_ac1, {
        'Start': [1],
        'Shutdown': [0],
      });
      final edited = _doc([
        Checklist(
          name: 'Start',
          title: 'Start',
          items: [
            const ChecklistItem(ChecklistItemType.check, 'changed'),
            const ChecklistItem(ChecklistItemType.check, 'Start item 1'),
            const ChecklistItem(ChecklistItemType.check, 'Start item 2'),
          ],
        ),
        _list('Shutdown', 2),
      ]);
      await attach(_ac1, document: edited);
      expect(repo.current.isChecked('Start', 1), isFalse);
      expect(repo.current.isChecked('Shutdown', 0), isTrue);
    });

    test('missing checklist is ignored', () async {
      seed(_ac1, {
        'Start': [1],
        'Shutdown': [0],
      });
      await attach(_ac1, document: _doc([_list('Start', 3)]));
      expect(repo.current.checked.keys, ['Start']);
    });

    test('new checklist starts clean', () async {
      seed(_ac1, {
        'Start': [1],
      });
      await attach(
        _ac1,
        document: _doc([_list('Start', 3), _list('Extra', 2)]),
      );
      expect(repo.current.checked.containsKey('Extra'), isFalse);
    });

    test('out-of-range index is not applied', () async {
      final doc = _doc();
      storage.records[_ac1] = StoredProgress(
        runId: 'run-1',
        checklists: {
          'Start': StoredChecklistProgress(
            checked: const [1, 7, 99],
            fingerprint: fingerprintOf(doc.checklists.first),
          ),
        },
      );
      await attach(_ac1);
      expect(repo.current.checked['Start'], {1});
    });

    test('counts never exceed totals after restore', () async {
      final doc = _doc();
      storage.records[_ac1] = StoredProgress(
        runId: 'run-1',
        checklists: {
          'Start': StoredChecklistProgress(
            checked: const [0, 1, 2, 3, 4, 5],
            fingerprint: fingerprintOf(doc.checklists.first),
          ),
        },
      );
      await attach(_ac1);
      final counts = repo.current.countsFor(doc.checklists.first);
      expect(counts.done, lessThanOrEqualTo(counts.total));
    });

    test('notes are not counted as marks', () async {
      final doc = _doc([
        Checklist(
          name: 'Start',
          title: 'Start',
          items: const [
            ChecklistItem(ChecklistItemType.note, 'note'),
            ChecklistItem(ChecklistItemType.check, 'a'),
          ],
        ),
      ]);
      storage.records[_ac1] = StoredProgress(
        runId: 'run-1',
        checklists: {
          'Start': StoredChecklistProgress(
            checked: const [0, 1],
            fingerprint: fingerprintOf(doc.checklists.first),
          ),
        },
      );
      await attach(_ac1, document: doc);
      expect(repo.current.checked['Start'], {1});
    });
  });

  group('attach without identity', () {
    test('attach without aircraft clears marks', () async {
      repo.toggle('Start', 0);
      expect(await repo.attach(_doc()), const AttachClean());
      expect(repo.current.checked, isEmpty);
    });

    test('attach without aircraft writes nothing', () async {
      await repo.attach(_doc());
      repo.toggle('Start', 0);
      await pumpEventQueue();
      expect(storage.callCount, 0);
    });

    test('loading a second file does not leak marks', () async {
      await repo.attach(_doc());
      repo.toggle('Start', 0);
      await repo.attach(_doc());
      expect(repo.current.checked, isEmpty);
    });

    test('attaching with no aircraft after one detaches from it', () async {
      await attach(_ac1);
      await repo.attach(_doc());
      repo.toggle('Start', 0);
      await pumpEventQueue();
      expect(storage.records[_ac1]?.checklists ?? {}, isEmpty);
    });
  });

  group('idempotent attach and reconnect', () {
    test('same aircraft attach twice keeps marks', () async {
      await attach(_ac1);
      repo.toggle('Start', 1);
      expect(await attach(_ac1), const AttachClean());
      expect(repo.current.isChecked('Start', 1), isTrue);
    });

    test('switching to another aircraft re-runs the rule', () async {
      seed(_ac2, {
        'Start': [2],
      }, lastViewed: 'Start');
      await attach(_ac1);
      repo.toggle('Start', 0);
      final outcome = await attach(_ac2);
      expect(outcome, const AttachRestored('Start'));
      expect(repo.current.checked['Start'], {2});
    });

    test('switching drops the first aircraft saved marks', () async {
      await attach(_ac1);
      repo.toggle('Start', 0);
      await pumpEventQueue();
      expect(storage.records[_ac1]!.checklists['Start']!.checked, [0]);
      await attach(_ac2);
      await pumpEventQueue();
      expect(storage.deletes, [_ac1]);
      expect(storage.records.containsKey(_ac1), isFalse);
    });

    test('switching away and back starts the first aircraft clean', () async {
      await attach(_ac1);
      repo.toggle('Start', 0);
      await attach(_ac2);
      repo.toggle('Start', 1);
      final outcome = await attach(_ac1);
      expect(outcome, const AttachClean());
      expect(repo.current.checked, isEmpty);
      await pumpEventQueue();
      expect(storage.deletes, [_ac1, _ac2]);
      expect(storage.records[_ac1]!.checklists, isEmpty);
    });

    test('a pending write of the old aircraft cannot undo the drop', () async {
      await attach(_ac1);
      repo.toggle('Start', 0);
      await attach(_ac2);
      await pumpEventQueue();
      expect(storage.records.containsKey(_ac1), isFalse);
    });

    test('the first attach deletes nothing', () async {
      seed(_ac2, {
        'Start': [1],
      });
      await attach(_ac1);
      await pumpEventQueue();
      expect(storage.deletes, isEmpty);
      expect(storage.records.containsKey(_ac2), isTrue);
    });

    test('reconnected with the same run id keeps marks', () async {
      await attach(_ac1);
      repo.toggle('Start', 0);
      expect(await repo.reconnected(runId: 'run-1'), const AttachKeep());
      expect(repo.current.isChecked('Start', 0), isTrue);
    });

    test(
      'reconnected with a new run id asks and keeps marks until answered',
      () async {
        await attach(_ac1);
        repo.toggle('Start', 0);
        expect(
          await repo.reconnected(runId: 'run-2'),
          const AttachNeedsPrompt(),
        );
        expect(repo.current.isChecked('Start', 0), isTrue);
        await repo.resolvePrompt(useSaved: false);
        expect(repo.current.checked, isEmpty);
      },
    );

    test('reconnected with a new run id and the answer to keep', () async {
      await attach(_ac1);
      repo.toggle('Start', 0);
      await repo.reconnected(runId: 'run-2');
      await repo.resolvePrompt(useSaved: true);
      await pumpEventQueue();
      expect(repo.current.isChecked('Start', 0), isTrue);
      expect(storage.records[_ac1]!.runId, 'run-2');
    });

    test('reconnected with a new run id and no marks does not ask', () async {
      await attach(_ac1);
      expect(await repo.reconnected(runId: 'run-2'), const AttachKeep());
    });

    test('reconnected with an unknown run id asks', () async {
      await attach(_ac1);
      repo.toggle('Start', 0);
      expect(await repo.reconnected(), const AttachNeedsPrompt());
    });

    test('reconnected with nothing attached keeps', () async {
      expect(await repo.reconnected(runId: 'run-1'), const AttachKeep());
    });

    test('after an answer the next reconnect with that run id keeps', () async {
      await attach(_ac1);
      repo.toggle('Start', 0);
      await repo.reconnected(runId: 'run-2');
      await repo.resolvePrompt(useSaved: true);
      expect(await repo.reconnected(runId: 'run-2'), const AttachKeep());
    });
  });
}

// Task 0.24: skipped items and the saved auto/manual mode
void _modeAndSkipTests() {
  late InMemoryProgressStorageService storage;
  late ChecklistProgressRepositoryImpl repo;

  setUp(() {
    storage = InMemoryProgressStorageService();
    repo = ChecklistProgressRepositoryImpl(storage: storage);
  });
  tearDown(() => repo.dispose());

  Future<AttachOutcome> attach(String path, {String? runId = 'run-1'}) =>
      repo.attach(_doc(), aircraft: _aircraft(path), runId: runId);

  test('skip is saved and comes back on restore', () async {
    await attach(_ac1);
    repo.skip('Start', 1);
    await pumpEventQueue();
    expect(storage.records[_ac1]!.checklists['Start']!.skipped, [1]);
    final again = ChecklistProgressRepositoryImpl(storage: storage);
    addTearDown(again.dispose);
    final outcome = await again.attach(
      _doc(),
      aircraft: _aircraft(_ac1),
      runId: 'run-1',
    );
    expect(outcome, isA<AttachRestored>());
    expect(again.current.isSkipped('Start', 1), isTrue);
  });

  test('the Reset mode is never saved', () async {
    await attach(_ac1);
    await pumpEventQueue();
    storage.writes.clear();
    repo.setManual('Start', manual: true);
    await pumpEventQueue();
    expect(repo.isManual('Start'), isTrue);
    expect(storage.writes, isEmpty);
    repo.setManual('Start', manual: false);
    expect(repo.isManual('Start'), isFalse);
  });

  test('loading another aircraft ends the Reset mode', () async {
    await attach(_ac1);
    repo.setManual('Start', manual: true);
    await attach(_ac2);
    expect(repo.isManual('Start'), isFalse);
  });

  test('the saved-progress question ends the Reset mode', () async {
    await attach(_ac1);
    repo.toggle('Start', 0);
    await pumpEventQueue();
    repo.setManual('Start', manual: true);
    final again = ChecklistProgressRepositoryImpl(storage: storage);
    addTearDown(again.dispose);
    again.setManual('Start', manual: true);
    final outcome = await again.attach(
      _doc(),
      aircraft: _aircraft(_ac1),
      runId: 'other-run',
    );
    expect(outcome, isA<AttachNeedsPrompt>());
    expect(again.isManual('Start'), isFalse);
  });

  test('the Reset mode survives a reconnect with the same run id', () async {
    await attach(_ac1);
    repo.toggle('Start', 0);
    repo.setManual('Start', manual: true);
    expect(await repo.reconnected(runId: 'run-1'), isA<AttachKeep>());
    expect(repo.isManual('Start'), isTrue);
  });
}
