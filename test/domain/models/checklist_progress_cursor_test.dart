import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flutter_test/flutter_test.dart';

// AC-35: the cursor follows the pilot's ticks and auto-check never moves it
// back (D-71, model half)
// AC-34: a manual tick against the dataref is remembered as disagreed

void main() {
  group('the cursor (6.8)', () {
    test('a fresh progress has the cursor at the top', () {
      final p = ChecklistProgress();
      expect(p.cursorOf('A'), 0);
      expect(p.cursor, isEmpty);
    });

    test('a manual tick sets the cursor to that item', () {
      final p = ChecklistProgress().toggled('A', 4);
      expect(p.cursorOf('A'), 4);
    });

    test('a manual tick of an earlier item moves the cursor back', () {
      final p = ChecklistProgress().toggled('A', 6).toggled('A', 2);
      expect(p.cursorOf('A'), 2);
    });

    test('an untick backs the cursor up to just below the nearest tick', () {
      // Nothing above: back to the top.
      final p = ChecklistProgress().toggled('A', 4).toggled('A', 4);
      expect(p.isChecked('A', 4), isFalse);
      expect(p.cursorOf('A'), 0);
      // Item 1 is ticked above item 5: the cursor goes to 2.
      final q = ChecklistProgress()
          .toggled('A', 1)
          .toggled('A', 5)
          .toggled('A', 5);
      expect(q.cursorOf('A'), 2);
      // Unticking item 1 with 5 still ticked: nothing above it, so the top.
      final r = ChecklistProgress()
          .toggled('A', 1)
          .toggled('A', 5)
          .toggled('A', 1);
      expect(r.cursorOf('A'), 0);
    });

    test('a skipped item above counts as passed when backing up', () {
      final p = ChecklistProgress()
          .skipping('A', 1)
          .toggled('A', 3)
          .toggled('A', 3);
      expect(p.cursorOf('A'), 2);
    });

    test('the cursor is kept per checklist', () {
      final p = ChecklistProgress().toggled('A', 3).toggled('B', 1);
      expect(p.cursorOf('A'), 3);
      expect(p.cursorOf('B'), 1);
    });

    test('auto-check can move the cursor forward', () {
      final p = ChecklistProgress().autoChecking('A', [0, 1], cursor: 2);
      expect(p.cursorOf('A'), 2);
    });

    test('auto-check never moves the cursor back', () {
      final p = ChecklistProgress().toggled('A', 5).autoChecking('A', [
        6,
      ], cursor: 2);
      expect(p.cursorOf('A'), 5);
    });

    test('auto-check without a cursor leaves it alone', () {
      final p = ChecklistProgress().toggled('A', 3).autoChecking('A', [4]);
      expect(p.cursorOf('A'), 3);
    });

    test('auto-check that checks nothing still may move the cursor', () {
      final p = ChecklistProgress().autoChecking('A', const [], cursor: 3);
      expect(p.cursorOf('A'), 3);
    });

    test('reset puts the cursor back at the top', () {
      final p = ChecklistProgress().toggled('A', 4).toggled('B', 2).reset('A');
      expect(p.cursorOf('A'), 0);
      expect(p.cursorOf('B'), 2);
      expect(ChecklistProgress().toggled('A', 4).resetAll().cursor, isEmpty);
    });

    test('a cursor of 0 is the same as none, so equal progress is equal', () {
      expect(ChecklistProgress.marks(cursor: {'A': 0}), ChecklistProgress());
    });

    test('the cursor takes part in equality', () {
      final a = ChecklistProgress.marks(
        checked: {
          'A': {1},
        },
        cursor: {'A': 1},
      );
      final b = ChecklistProgress({
        'A': {1},
      });
      expect(a, isNot(b));
    });

    test('a negative cursor is kept at the top', () {
      expect(ChecklistProgress.marks(cursor: {'A': -3}).cursorOf('A'), 0);
    });

    test('the cursor map is read-only', () {
      final p = ChecklistProgress().toggled('A', 1);
      expect(() => p.cursor['A'] = 9, throwsUnsupportedError);
    });
  });

  group('disagreed marks (6.9)', () {
    test('a fresh progress has none', () {
      final p = ChecklistProgress();
      expect(p.disagreed, isEmpty);
      expect(p.isDisagreed('A', 0), isFalse);
    });

    test('a tick marked as disagreeing is remembered', () {
      final p = ChecklistProgress().toggled('A', 2, disagrees: true);
      expect(p.isChecked('A', 2), isTrue);
      expect(p.isDisagreed('A', 2), isTrue);
    });

    test('a tick that agrees or is unknown has no mark', () {
      final p = ChecklistProgress().toggled('A', 2);
      expect(p.isChecked('A', 2), isTrue);
      expect(p.isDisagreed('A', 2), isFalse);
    });

    test('an untick removes the mark', () {
      final p = ChecklistProgress()
          .toggled('A', 2, disagrees: true)
          .toggled('A', 2);
      expect(p.isChecked('A', 2), isFalse);
      expect(p.isDisagreed('A', 2), isFalse);
    });

    test('the disagrees flag is ignored when the toggle unchecks', () {
      final p = ChecklistProgress()
          .toggled('A', 2)
          .toggled('A', 2, disagrees: true);
      expect(p.isChecked('A', 2), isFalse);
      expect(p.isDisagreed('A', 2), isFalse);
    });

    test('reset clears the marks of that checklist only', () {
      final p = ChecklistProgress()
          .toggled('A', 1, disagrees: true)
          .toggled('B', 1, disagrees: true)
          .reset('A');
      expect(p.isDisagreed('A', 1), isFalse);
      expect(p.isDisagreed('B', 1), isTrue);
      expect(
        ChecklistProgress()
            .toggled('A', 1, disagrees: true)
            .resetAll()
            .disagreed,
        isEmpty,
      );
    });

    test('a disagreed mark is only kept for a checked item', () {
      final p = ChecklistProgress.marks(
        checked: {
          'A': {1},
        },
        disagreed: {
          'A': {1, 7},
        },
      );
      expect(p.isDisagreed('A', 1), isTrue);
      expect(p.isDisagreed('A', 7), isFalse, reason: 'item 7 is not checked');
    });

    test('the marks are copied, read-only and part of equality', () {
      final source = <int>{1};
      final a = ChecklistProgress.marks(
        checked: {
          'A': {1},
        },
        disagreed: {'A': source},
      );
      source.add(9);
      expect(a.disagreed['A'], {1});
      expect(() => a.disagreed['A']!.add(5), throwsUnsupportedError);
      expect(
        a,
        isNot(
          ChecklistProgress({
            'A': {1},
          }),
        ),
      );
    });

    test('auto-check does not mark an item as disagreed', () {
      final p = ChecklistProgress().autoChecking('A', [3]);
      expect(p.isDisagreed('A', 3), isFalse);
    });
  });

  group('backing out of a tick (cancelled warning)', () {
    test('the item is unchecked as if never ticked', () {
      final before = ChecklistProgress().toggled('A', 1);
      final ticked = before.toggled('A', 4, disagrees: true);
      final back = ticked.tickCancelled('A', 4, before);
      expect(back.isChecked('A', 4), isFalse);
      expect(back.isDisagreed('A', 4), isFalse);
      expect(back.cursorOf('A'), 1);
      expect(back, before);
    });

    test('the cursor goes back even if auto moved it on after the tick', () {
      final before = ChecklistProgress();
      final ticked = before.toggled('A', 3, disagrees: true).autoChecking('A', [
        4,
      ], cursor: 5);
      final back = ticked.tickCancelled('A', 3, before);
      expect(back.cursorOf('A'), 0);
      expect(back.isChecked('A', 4), isTrue, reason: 'auto kept its own tick');
    });

    test('an item above the old cursor gets the cursor, so auto waits on it', () {
      // The pilot ticked item 5 earlier, so the cursor is at 5; items above it
      // are still open. Ticking item 2 against the sim and cancelling must
      // leave the cursor at 2, or auto would walk on past the open item.
      final before = ChecklistProgress().toggled('A', 5);
      expect(before.cursorOf('A'), 5);
      final ticked = before.toggled('A', 2, disagrees: true);
      final back = ticked.tickCancelled('A', 2, before);
      expect(back.isChecked('A', 2), isFalse);
      expect(back.cursorOf('A'), 2);
    });

    test('other checklists and other items are untouched', () {
      final before = ChecklistProgress().toggled('B', 0);
      final ticked = before.toggled('A', 0).toggled('A', 1, disagrees: true);
      final back = ticked.tickCancelled('A', 1, before);
      expect(back.isChecked('A', 0), isTrue);
      expect(back.isChecked('B', 0), isTrue);
    });
  });
}
