import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('result defaults to empty', () {
    const item = ChecklistItem(ChecklistItemType.check, 'Battery');
    expect(item.result, '');
  });

  test('equal items are ==', () {
    const a = ChecklistItem(ChecklistItemType.check, 'Battery', 'ON');
    const b = ChecklistItem(ChecklistItemType.check, 'Battery', 'ON');
    expect(a, b);
  });

  test('different type is !=', () {
    const a = ChecklistItem(ChecklistItemType.check, 'Battery');
    const b = ChecklistItem(ChecklistItemType.note, 'Battery');
    expect(a, isNot(b));
  });

  test('note can have empty result', () {
    const note = ChecklistItem(ChecklistItemType.note, 'Be careful');
    expect(note.type, ChecklistItemType.note);
    expect(note.result, isEmpty);
  });
}
