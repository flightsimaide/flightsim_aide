import 'dart:math';

import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Op = ({String name, int index});

void main() {
  const check = ChecklistItem(ChecklistItemType.check, 'c');
  const note = ChecklistItem(ChecklistItemType.note, 'n');
  final model = [
    for (final name in ['A', 'B', 'C'])
      Checklist(name: name, title: name, items: [check, note, check, check]),
  ];

  Map<String, Set<int>> snapshot(ChecklistProgress p) => {
    for (final e in p.checked.entries) e.key: {...e.value},
  };

  test('toggle is an involution over random sequences', () {
    final random = Random(42);
    for (var run = 0; run < 500; run++) {
      // Indexes run past the end of the lists on purpose.
      final ops = <_Op>[
        for (var i = 0; i < 1 + random.nextInt(30); i++)
          (
            name: model[random.nextInt(model.length)].name,
            index: random.nextInt(6),
          ),
      ];
      final start = ChecklistProgress({
        'A': {0},
        'B': {2, 3},
      });
      final startSnapshot = snapshot(start);

      final states = [start];
      for (final op in ops) {
        states.add(states.last.toggled(op.name, op.index));
      }
      final snapshots = states.map(snapshot).toList();

      // (b) done never exceeds total in any state.
      for (final state in states) {
        for (final list in model) {
          final counts = state.countsFor(list);
          expect(counts.done <= counts.total, isTrue);
        }
      }

      // (a) undoing every operation in reverse order returns to the start.
      var undone = states.last;
      for (final op in ops.reversed) {
        undone = undone.toggled(op.name, op.index);
      }
      // The checked marks return.
      expect(snapshot(undone), snapshot(start));

      // (c) no state was mutated by later operations.
      expect(snapshot(start), startSnapshot);
      for (var i = 0; i < states.length; i++) {
        expect(snapshot(states[i]), snapshots[i]);
      }
    }
  });
}
