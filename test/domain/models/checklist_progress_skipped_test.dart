import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flutter_test/flutter_test.dart';

// Task 0.24: skipped items

final _list = Checklist(
  name: 'A',
  title: 'A',
  items: const [
    ChecklistItem(ChecklistItemType.note, 'note'),
    ChecklistItem(ChecklistItemType.check, 'one'),
    ChecklistItem(ChecklistItemType.check, 'two'),
    ChecklistItem(ChecklistItemType.check, 'three'),
  ],
);

void main() {
  test('skipping marks the item and moves the cursor past it', () {
    final p = ChecklistProgress().skipping('A', 1);
    expect(p.isSkipped('A', 1), isTrue);
    expect(p.isChecked('A', 1), isFalse);
    expect(p.cursorOf('A'), 2);
  });

  test('skipping never moves the cursor back and ignores checked items', () {
    final p = ChecklistProgress().toggled('A', 3).skipping('A', 1);
    expect(p.cursorOf('A'), 3);
    expect(p.toggled('A', 2).skipping('A', 2).isSkipped('A', 2), isFalse);
  });

  test('toggling a skipped item checks it and clears the skip', () {
    final p = ChecklistProgress().skipping('A', 1).toggled('A', 1);
    expect(p.isChecked('A', 1), isTrue);
    expect(p.isSkipped('A', 1), isFalse);
  });

  test('skipped items count towards completion, not the checked count', () {
    var p = ChecklistProgress().toggled('A', 1).skipping('A', 2);
    expect(p.countsFor(_list), (done: 1, total: 3, skipped: 1));
    expect(p.isComplete(_list), isFalse);
    p = p.skipping('A', 3);
    expect(p.countsFor(_list), (done: 1, total: 3, skipped: 2));
    expect(p.isComplete(_list), isTrue);
  });

  test('auto never checks a skipped item', () {
    final p = ChecklistProgress().skipping('A', 1).autoChecking('A', [1, 2]);
    expect(p.isChecked('A', 1), isFalse);
    expect(p.isChecked('A', 2), isTrue);
  });

  test('reset clears skipped items', () {
    expect(ChecklistProgress().skipping('A', 1).reset('A').skipped, isEmpty);
    expect(ChecklistProgress().skipping('A', 1).resetAll().skipped, isEmpty);
  });

  test('a cancelled tick brings back the skip it replaced', () {
    final before = ChecklistProgress().skipping('A', 1);
    final p = before
        .toggled('A', 1, disagrees: true)
        .tickCancelled('A', 1, before);
    expect(p.isSkipped('A', 1), isTrue);
    expect(p.isChecked('A', 1), isFalse);
  });

  test('disagreedCount counts checked items ticked against the sim', () {
    final p = ChecklistProgress()
        .toggled('A', 1, disagrees: true)
        .toggled('A', 2)
        .toggled('A', 3, disagrees: true);
    expect(p.disagreedCount(_list), 2);
    expect(ChecklistProgress().disagreedCount(_list), 0);
  });
}
