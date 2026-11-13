import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flutter_test/flutter_test.dart';

// AC-35: manual wins (model half); an untick is not remembered (D-78)

void main() {
  group('the auto set', () {
    test('a fresh progress has it empty', () {
      final p = ChecklistProgress();
      expect(p.autoChecked, isEmpty);
      expect(p.isAutoChecked('A', 0), isFalse);
    });

    test('the sets are copied and read-only', () {
      final source = {
        0: <int>{1},
      };
      final p = ChecklistProgress.marks(
        checked: {'A': source[0]!},
        autoChecked: {
          'A': {1},
        },
      );
      source[0]!.add(5);
      expect(p.checked['A'], {1});
      expect(() => p.autoChecked['A']!.add(9), throwsUnsupportedError);
    });

    test('empty entries are dropped so equal progress is equal', () {
      expect(
        ChecklistProgress.marks(autoChecked: {'A': <int>{}}),
        ChecklistProgress(),
      );
    });

    test('the sets take part in equality', () {
      final a = ChecklistProgress.marks(
        checked: {
          'A': {1},
        },
        autoChecked: {
          'A': {1},
        },
      );
      final b = ChecklistProgress({
        'A': {1},
      });
      expect(a, isNot(b));
      expect(a.hashCode, isNot(b.hashCode));
    });
  });

  group('toggle transitions (AC-35)', () {
    // (start state) -> toggled -> (checked, auto)
    final cases = <String, (ChecklistProgress, List<bool>)>{
      'unchecked, never touched -> checked by hand': (
        ChecklistProgress(),
        [true, false],
      ),
      'checked by hand -> unchecked, not remembered (D-78)': (
        ChecklistProgress({
          'A': {0},
        }),
        [false, false],
      ),
      'auto-checked -> unchecked, no longer auto, not remembered': (
        ChecklistProgress().autoChecking('A', [0]),
        [false, false],
      ),
      'unticked -> checked by hand again, not auto': (
        ChecklistProgress().toggled('A', 0).toggled('A', 0),
        [true, false],
      ),
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        final (start, expected) = entry.value;
        final p = start.toggled('A', 0);
        expect([p.isChecked('A', 0), p.isAutoChecked('A', 0)], expected);
      });
    }

    test('toggling one item leaves the others alone', () {
      final p = ChecklistProgress().autoChecking('A', [0, 1]).toggled('A', 0);
      expect(p.isAutoChecked('A', 1), isTrue);
      expect(p.isChecked('A', 1), isTrue);
    });
  });

  group('autoChecking', () {
    test('checks and marks the items', () {
      final p = ChecklistProgress().autoChecking('A', [1, 3]);
      expect(p.checked['A'], {1, 3});
      expect(p.autoChecked['A'], {1, 3});
    });

    test('checks an item the user unticked (the cubit holds auto off)', () {
      final p = ChecklistProgress().toggled('A', 1).toggled('A', 1);
      final next = p.autoChecking('A', [1, 2]);
      expect(next.checked['A'], {1, 2});
    });

    test('does not mark an item the user already checked', () {
      final p = ChecklistProgress().toggled('A', 1).autoChecking('A', [1]);
      expect(p.isAutoChecked('A', 1), isFalse);
      expect(p.isChecked('A', 1), isTrue);
    });

    test('nothing to add returns the same instance', () {
      final p = ChecklistProgress({
        'A': {1},
      });
      expect(identical(p.autoChecking('A', [1]), p), isTrue);
      expect(identical(p.autoChecking('A', const []), p), isTrue);
    });

    test('never unchecks', () {
      final p = ChecklistProgress({
        'A': {0, 1},
      }).autoChecking('A', [2]);
      expect(p.checked['A'], {0, 1, 2});
    });
  });

  group('reset (6.6)', () {
    final marked = ChecklistProgress()
        .autoChecking('A', [0])
        .toggled('A', 1)
        .toggled('A', 1)
        .autoChecking('B', [0]);

    test('reset clears the sets of one checklist only', () {
      final p = marked.reset('A');
      expect(p.checked.containsKey('A'), isFalse);
      expect(p.autoChecked.containsKey('A'), isFalse);
      expect(p.isAutoChecked('B', 0), isTrue);
    });

    test('resetAll clears everything', () {
      expect(marked.resetAll(), ChecklistProgress());
    });

    test('after a reset auto-check can check the item again', () {
      final p = marked.reset('A').autoChecking('A', [1]);
      expect(p.isChecked('A', 1), isTrue);
    });
  });
}
