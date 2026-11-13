import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/colour_run.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('equal runs are equal and share a hashCode', () {
    const a = ColourRun('FLAPS', 'white');
    const b = ColourRun('FLAPS', 'white');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('runs differing in text or colour are not equal', () {
    const base = ColourRun('FLAPS', 'white');
    expect(base, isNot(const ColourRun('FLAP', 'white')));
    expect(base, isNot(const ColourRun('FLAPS', 'grey')));
    expect(base, isNot(const ColourRun('FLAPS')));
  });

  test('items with different runs are not equal', () {
    const plain = ChecklistItem(ChecklistItemType.check, 'A', 'B');
    const coloured = ChecklistItem(ChecklistItemType.check, 'A', 'B', [
      ColourRun('A', 'red'),
    ]);
    expect(plain, isNot(coloured));
    expect(
      coloured,
      const ChecklistItem(ChecklistItemType.check, 'A', 'B', [
        ColourRun('A', 'red'),
      ]),
    );
  });

  test('result runs are part of equality', () {
    const a = ChecklistItem(ChecklistItemType.check, 'A', 'B', [], [
      ColourRun('B', 'red'),
    ]);
    const b = ChecklistItem(ChecklistItemType.check, 'A', 'B');
    expect(a, isNot(b));
  });

  test('parts fall back to one default run, or none for empty text', () {
    const item = ChecklistItem(ChecklistItemType.check, 'A');
    expect(item.labelParts, const [ColourRun('A')]);
    expect(item.resultParts, isEmpty);
  });

  test('parts return the runs when there are some', () {
    const item = ChecklistItem(ChecklistItemType.check, 'AB', '', [
      ColourRun('A', 'red'),
      ColourRun('B'),
    ]);
    expect(item.labelParts, const [ColourRun('A', 'red'), ColourRun('B')]);
  });
}
