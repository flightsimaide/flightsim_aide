import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Checklist checklist() => Checklist(
    name: 'A',
    title: 'Alpha',
    items: [const ChecklistItem(ChecklistItemType.check, 'Battery', 'ON')],
  );

  test('equal ChecklistItems have equal hashCode', () {
    const a = ChecklistItem(ChecklistItemType.check, 'Battery', 'ON');
    const b = ChecklistItem(ChecklistItemType.check, 'Battery', 'ON');
    expect(a.hashCode, b.hashCode);
  });

  test('equal Checklists have equal hashCode', () {
    expect(checklist(), checklist());
    expect(checklist().hashCode, checklist().hashCode);
  });

  test('equal ChecklistDocuments have equal hashCode', () {
    ChecklistDocument make() => ChecklistDocument(
      checklists: [checklist()],
      warnings: const ['Line 1: oops'],
      sourceName: 'a.txt',
    );
    expect(make(), make());
    expect(make().hashCode, make().hashCode);
  });

  test('equal ChecklistProgress have equal hashCode', () {
    ChecklistProgress make() => ChecklistProgress({
      'A': {1, 2},
    });
    expect(make(), make());
    expect(make().hashCode, make().hashCode);
  });

  test('Set dedupes equal ChecklistItems', () {
    ChecklistItem item(ChecklistItemType type) =>
        ChecklistItem(type, 'Battery', 'ON');
    final items = {
      item(ChecklistItemType.check),
      item(ChecklistItemType.check),
      item(ChecklistItemType.note),
    };
    expect(items, hasLength(2));
  });

  test('Set dedupes equal Checklists', () {
    expect({checklist(), checklist()}, hasLength(1));
  });

  test('progress reached by different routes is equal', () {
    // Checked on by hand, then off by hand and then reset: back to empty.
    final viaToggle = ChecklistProgress().toggled('A', 1).toggled('A', 1);
    expect(viaToggle.reset('A'), ChecklistProgress());
    expect(viaToggle.reset('A').hashCode, ChecklistProgress().hashCode);
    final viaTwo = ChecklistProgress().toggled('A', 1).toggled('A', 2);
    final viaOther = ChecklistProgress().toggled('A', 2).toggled('A', 1);
    // The same checks reached in another order: the marks are equal, the
    // cursor is not (it follows the last tick, D-71).
    expect(viaTwo.checked, viaOther.checked);
    expect(viaTwo.cursorOf('A'), 2);
    expect(viaOther.cursorOf('A'), 1);
  });
}
