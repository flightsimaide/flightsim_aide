import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty progress has nothing checked', () {
    final p = ChecklistProgress();
    expect(p.isChecked('A', 0), isFalse);
  });

  test('isChecked true for a seeded index', () {
    final p = ChecklistProgress({
      'A': {1},
    });
    expect(p.isChecked('A', 1), isTrue);
    expect(p.isChecked('A', 0), isFalse);
    expect(p.isChecked('B', 1), isFalse);
  });

  test('constructor copies the map', () {
    final seed = <String, Set<int>>{
      'A': {1},
    };
    final p = ChecklistProgress(seed);
    seed['A']!.add(2);
    seed['B'] = {0};
    expect(p.isChecked('A', 2), isFalse);
    expect(p.isChecked('B', 0), isFalse);
  });

  group('toggled', () {
    test('toggle on checks', () {
      final p = ChecklistProgress().toggled('A', 2);
      expect(p.isChecked('A', 2), isTrue);
    });

    test('toggle twice unchecks', () {
      final p = ChecklistProgress().toggled('A', 2).toggled('A', 2);
      expect(p.isChecked('A', 2), isFalse);
      // D-78: the untick is not remembered.
      expect(p.checked, isEmpty);
    });

    test('original instance is unchanged', () {
      final original = ChecklistProgress();
      original.toggled('A', 0);
      expect(original.isChecked('A', 0), isFalse);
    });

    test('toggling one checklist leaves another alone', () {
      final p = ChecklistProgress({
        'B': {1},
      }).toggled('A', 0);
      expect(p.isChecked('B', 1), isTrue);
      expect(p.isChecked('A', 0), isTrue);
    });

    test('checked sets are not shared between instances', () {
      final a = ChecklistProgress({
        'A': {1},
      });
      final b = a.toggled('A', 2);
      expect(a.checked['A'], {1});
      expect(b.checked['A'], {1, 2});
      expect(identical(a.checked['A'], b.checked['A']), isFalse);
    });

    test('the checked getter is read-only', () {
      final p = ChecklistProgress({
        'A': {1},
      });
      expect(() => p.checked['A']!.add(9), throwsUnsupportedError);
      expect(() => p.checked['B'] = {0}, throwsUnsupportedError);
    });
  });

  group('reset', () {
    final seeded = ChecklistProgress({
      'A': {0, 1},
      'B': {2},
    });

    test('reset clears only that checklist', () {
      final p = seeded.reset('A');
      expect(p.isChecked('A', 0), isFalse);
      expect(p.isChecked('B', 2), isTrue);
    });

    test('reset on an unknown name is a no-op', () {
      expect(seeded.reset('Z'), seeded);
    });

    test('resetAll clears all', () {
      expect(seeded.resetAll(), ChecklistProgress());
    });

    test('original unchanged after reset', () {
      seeded.reset('A');
      seeded.resetAll();
      expect(seeded.isChecked('A', 0), isTrue);
      expect(seeded.isChecked('B', 2), isTrue);
    });
  });

  group('countsFor', () {
    const check = ChecklistItem(ChecklistItemType.check, 'c');
    const note = ChecklistItem(ChecklistItemType.note, 'n');
    Checklist list(List<ChecklistItem> items) =>
        Checklist(name: 'A', title: 'A', items: items);

    test('counts exclude notes from total', () {
      final c = list([note, check, check, note]);
      expect(ChecklistProgress().countsFor(c), (done: 0, total: 2, skipped: 0));
    });

    test('0 of 0 for a notes-only checklist', () {
      final c = list([note, note]);
      expect(ChecklistProgress().countsFor(c), (done: 0, total: 0, skipped: 0));
    });

    test('a checked index that points at a note is not counted', () {
      final c = list([note, check]);
      final p = ChecklistProgress({
        'A': {0, 1},
      });
      expect(p.countsFor(c), (done: 1, total: 1, skipped: 0));
    });

    test('an out-of-range checked index is not counted', () {
      final c = list([check]);
      final p = ChecklistProgress({
        'A': {0, 5, -1},
      });
      expect(p.countsFor(c), (done: 1, total: 1, skipped: 0));
    });

    test('done never exceeds total', () {
      final c = list([check, note]);
      final p = ChecklistProgress({
        'A': {0, 1, 2, 3, 4},
      });
      final counts = p.countsFor(c);
      expect(counts.done <= counts.total, isTrue);
    });
  });

  group('isComplete', () {
    const check = ChecklistItem(ChecklistItemType.check, 'c');
    const note = ChecklistItem(ChecklistItemType.note, 'n');
    Checklist list(List<ChecklistItem> items) =>
        Checklist(name: 'A', title: 'A', items: items);

    test('complete when all check items are checked', () {
      final c = list([note, check, check]);
      final p = ChecklistProgress({
        'A': {1, 2},
      });
      expect(p.isComplete(c), isTrue);
    });

    test('not complete when one is missing', () {
      final c = list([check, check]);
      final p = ChecklistProgress({
        'A': {0},
      });
      expect(p.isComplete(c), isFalse);
    });

    test('notes-only checklist is never complete', () {
      final c = list([note, note]);
      final p = ChecklistProgress({
        'A': {0, 1},
      });
      expect(p.isComplete(c), isFalse);
      expect(ChecklistProgress().isComplete(c), isFalse);
    });

    test('unchecking after completion makes it incomplete', () {
      final c = list([check, check]);
      final done = ChecklistProgress({
        'A': {0, 1},
      });
      expect(done.isComplete(c), isTrue);
      expect(done.toggled('A', 1).isComplete(c), isFalse);
    });
  });
}
