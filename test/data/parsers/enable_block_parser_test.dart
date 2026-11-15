import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flutter_test/flutter_test.dart';

ChecklistDocument parse(String body) =>
    const AircraftWorkflowParser().parse(body);

List<ChecklistItem> items(String body) =>
    parse('sw_checklist:A\n$body').checklists.single.items;

void main() {
  group('sw_enable_start and sw_enable_end (GRAMMAR.md G1 to G8)', () {
    test('items between the two lines get the index of the switch row', () {
      final list = items('''
sw_item:Before|ON
sw_enable_start:Use GPU
sw_item:GPU|CONNECT
sw_item:GPU power|ON
sw_enable_end
sw_item:After|ON
''');
      expect(list.map((i) => i.type), [
        ChecklistItemType.check,
        ChecklistItemType.option,
        ChecklistItemType.check,
        ChecklistItemType.check,
        ChecklistItemType.check,
      ]);
      expect(list[1].label, 'Use GPU');
      expect(list.map((i) => i.gate), [null, null, 1, 1, null]);
    });

    test('sw_enable_end makes no item', () {
      final list = items('sw_enable_start:X\nsw_item:A\nsw_enable_end\n');
      expect(list, hasLength(2));
    });

    test('notes, headings and details inside the block are gated too', () {
      final list = items('''
sw_enable_start:Use GPU
sw_item_heading:Ground power
sw_item:GPU|CONNECT
sw_item_details:Check the cable
sw_remark:Note
sw_enable_end
''');
      expect(list.skip(1).map((i) => i.gate), [0, 0, 0, 0]);
    });

    test('a gated item keeps its condition', () {
      final list = items(
        'sw_enable_start:X\nsw_item:GPU|ON:a/gpu:1\nsw_enable_end\n',
      );
      expect(list[1].condition, isNotNull);
      expect(list[1].gate, 0);
    });

    test('the switch row has a label and no result, condition or gate', () {
      final row = items('sw_enable_start:Use GPU\nsw_enable_end').single;
      expect(row.result, '');
      expect(row.condition, isNull);
      expect(row.gate, isNull);
    });

    test('two blocks in one checklist have their own switch rows', () {
      final list = items('''
sw_enable_start:One
sw_item:a
sw_enable_end
sw_enable_start:Two
sw_item:b
sw_enable_end
''');
      expect(list.map((i) => i.gate), [null, 0, null, 2]);
    });

    test('keywords ignore case (K1) and sw_enable_end may have a colon', () {
      final list = items(
        'SW_ENABLE_START:X\nsw_item:a\nSW_ENABLE_END:\nsw_item:b',
      );
      expect(list.map((i) => i.gate), [null, 0, null]);
    });

    test('colour markers work in the label', () {
      final doc = parse(
        'sw_define_colour:red:1,0,0\n'
        'sw_checklist:A\n'
        'sw_enable_start:Use \\red\\GPU\n'
        'sw_enable_end',
      );
      final row = doc.checklists.single.items.single;
      expect(row.label, 'Use GPU');
      expect(row.labelRuns, isNotEmpty);
      expect(doc.warnings, isEmpty);
    });

    test('a clean block gives no warning', () {
      final doc = parse(
        'sw_checklist:A\nsw_enable_start:X\nsw_item:a\nsw_enable_end',
      );
      expect(doc.warnings, isEmpty);
    });
  });

  group('warnings', () {
    test('a start inside a block is ignored; the outer block carries on', () {
      final doc = parse('''
sw_checklist:A
sw_enable_start:Outer
sw_enable_start:Inner
sw_item:a
sw_enable_end
sw_item:b
''');
      final list = doc.checklists.single.items;
      expect(list.map((i) => i.type), [
        ChecklistItemType.option,
        ChecklistItemType.check,
        ChecklistItemType.check,
      ]);
      expect(list.map((i) => i.gate), [null, 0, null]);
      expect(doc.warnings, [
        'Line 3: sw_enable_start inside another block; ignored',
      ]);
    });

    test('an end with no start warns and does nothing', () {
      final doc = parse('sw_checklist:A\nsw_item:a\nsw_enable_end\nsw_item:b');
      expect(doc.checklists.single.items.map((i) => i.gate), [null, null]);
      expect(doc.warnings, ['Line 3: sw_enable_end without sw_enable_start']);
    });

    test('an unclosed block ends at the next checklist, with a warning', () {
      final doc = parse('''
sw_checklist:A
sw_enable_start:X
sw_item:a
sw_checklist:B
sw_item:b
''');
      expect(doc.checklists[0].items.map((i) => i.gate), [null, 0]);
      expect(doc.checklists[1].items.single.gate, isNull);
      expect(doc.warnings, [
        'Line 2: sw_enable_start has no sw_enable_end; '
            'closed at the end of the checklist',
      ]);
    });

    test('an unclosed block ends at the end of the file, with a warning', () {
      final doc = parse('sw_checklist:A\nsw_enable_start:X\nsw_item:a');
      expect(doc.checklists.single.items.map((i) => i.gate), [null, 0]);
      expect(doc.warnings, hasLength(1));
      expect(doc.warnings.single, startsWith('Line 2: sw_enable_start has no'));
    });

    test('a start with no label is ignored and its items are not gated', () {
      final doc = parse(
        'sw_checklist:A\nsw_enable_start:\nsw_item:a\nsw_enable_end',
      );
      expect(doc.checklists.single.items.single.gate, isNull);
      expect(doc.warnings, [
        'Line 2: sw_enable_start has no label; ignored',
        'Line 4: sw_enable_end without sw_enable_start',
      ]);
    });

    test('a bare sw_enable_start is a start with no label', () {
      final doc = parse('sw_checklist:A\nsw_enable_start\nsw_item:a');
      expect(
        doc.warnings.first,
        'Line 2: sw_enable_start has no label; ignored',
      );
    });

    test('text after the label warns and is ignored', () {
      final doc = parse(
        'sw_checklist:A\nsw_enable_start:Use GPU:a/gpu:1\nsw_item:a\nsw_enable_end',
      );
      expect(doc.checklists.single.items.first.label, 'Use GPU');
      expect(doc.warnings, [
        'Line 2: sw_enable_start takes a label only; the rest is ignored',
      ]);
    });

    test('start and end before any checklist warn', () {
      final doc = parse(
        'sw_enable_start:X\nsw_enable_end\nsw_checklist:A\nsw_item:a',
      );
      expect(doc.warnings, [
        'Line 1: item before any checklist',
        'Line 2: item before any checklist',
      ]);
    });
  });

  test('a checklist of only a switch row is kept', () {
    final doc = parse('sw_checklist:A\nsw_enable_start:X\nsw_enable_end');
    expect(doc.checklists, hasLength(1));
  });

  test('a bare sw_continue before a start counts as followed by an item', () {
    final doc = parse('''
sw_checklist:A
sw_item:a
sw_continue:B
sw_enable_start:X
sw_enable_end
sw_checklist:B
sw_item:b
''');
    expect(
      doc.warnings,
      contains('Line 3: sw_continue should be at the end of its checklist'),
    );
  });
}
