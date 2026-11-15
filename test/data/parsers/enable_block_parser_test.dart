import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/switch_gate.dart';
import 'package:flutter_test/flutter_test.dart';

// Switch blocks (GRAMMAR.md section 5b): sw_switch, sw_if, sw_else, sw_end.

ChecklistDocument parse(String body) =>
    const AircraftWorkflowParser().parse(body);

List<ChecklistItem> items(String body) =>
    parse('sw_checklist:A\n$body').checklists.single.items;

/// The gate of each item as `id/on`, `id/off` or null.
List<String?> gates(List<ChecklistItem> list) => [
  for (final i in list)
    i.gate == null ? null : '${i.gate!.id}/${i.gate!.whenOn ? 'on' : 'off'}',
];

void main() {
  group('sw_switch ... sw_end (G1 to G4)', () {
    test('the switch row has a label, an id and a default', () {
      final row = items('sw_switch:Use GPU|gpu|ON\nsw_end').single;
      expect(row.type, ChecklistItemType.option);
      expect(row.label, 'Use GPU');
      expect(row.switchDef, const SwitchDef('gpu', defaultOn: true));
      expect(row.result, '');
      expect(row.condition, isNull);
      expect(row.gate, isNull);
    });

    test('the default is OFF when it is left out', () {
      final row = items('sw_switch:Use GPU|gpu\nsw_end').single;
      expect(row.switchDef, const SwitchDef('gpu'));
      expect(row.switchDef!.defaultOn, isFalse);
    });

    test('ON and OFF ignore case, and so do the id and the keyword', () {
      final list = items(
        'SW_SWITCH:A|GPU|off\nsw_end\nsw_switch:B|x|On\nsw_end',
      );
      expect(list[0].switchDef, const SwitchDef('gpu'));
      expect(list[1].switchDef, const SwitchDef('x', defaultOn: true));
    });

    test(
      'the items before sw_else are the ON branch, after it the OFF one',
      () {
        final list = items('''
sw_item:Before|ON
sw_switch:Use GPU|gpu|OFF
sw_item:GPU|CONNECT
sw_item:GPU power|ON
sw_else
sw_item:Unplug|CHECK
sw_end
sw_item:After|ON
''');
        expect(gates(list), [null, null, 'gpu/on', 'gpu/on', 'gpu/off', null]);
        expect(list.map((i) => i.type), [
          ChecklistItemType.check,
          ChecklistItemType.option,
          ChecklistItemType.check,
          ChecklistItemType.check,
          ChecklistItemType.check,
          ChecklistItemType.check,
        ]);
      },
    );

    test('a gate carries the default of its switch', () {
      final list = items('sw_switch:X|a|ON\nsw_item:i\nsw_end');
      expect(
        list[1].gate,
        const SwitchGate(SwitchDef('a', defaultOn: true), whenOn: true),
      );
    });

    test('sw_else and sw_end make no item', () {
      expect(items('sw_switch:X|a\nsw_item:A\nsw_else\nsw_end'), hasLength(2));
    });

    test('notes, headings and details inside a branch are gated too', () {
      final list = items('''
sw_switch:Use GPU|gpu
sw_item_heading:Ground power
sw_item:GPU|CONNECT
sw_item_details:Check the cable
sw_else
sw_remark:Note
sw_end
''');
      expect(gates(list), [null, 'gpu/on', 'gpu/on', 'gpu/on', 'gpu/off']);
    });

    test('a gated item keeps its condition', () {
      final list = items('sw_switch:X|a\nsw_item:GPU|ON:a/gpu:1\nsw_end');
      expect(list[1].condition, isNotNull);
      expect(list[1].gate?.id, 'a');
    });

    test('a switch may have no items, and a checklist of only it is kept', () {
      final doc = parse('sw_checklist:A\nsw_switch:X|a\nsw_end');
      expect(doc.checklists, hasLength(1));
      expect(doc.warnings, isEmpty);
    });

    test('sw_end and sw_else may be written with a trailing colon', () {
      final list = items(
        'sw_switch:X|a\nsw_else:\nsw_item:b\nsw_end:\nsw_item:c',
      );
      expect(gates(list), [null, 'a/off', null]);
    });

    test('colour markers work in the label', () {
      final doc = parse(
        'sw_define_colour:red:1,0,0\n'
        'sw_checklist:A\n'
        'sw_switch:Use \\red\\GPU|gpu\n'
        'sw_end',
      );
      final row = doc.checklists.single.items.single;
      expect(row.label, 'Use GPU');
      expect(row.labelRuns, isNotEmpty);
      expect(doc.warnings, isEmpty);
    });
  });

  group('sw_if|id|state (G5)', () {
    const text = '''
sw_checklist:A
sw_switch:Use GPU|gpu|ON
sw_end
sw_checklist:B
sw_item:Before
sw_if|gpu|ON
sw_item:Disconnect
sw_else
sw_item:Nothing
sw_end
sw_if|gpu|OFF
sw_item:Off first
sw_else
sw_item:On second
sw_end
''';

    test('shows no row, only its blocks, and uses the shared default', () {
      final doc = parse(text);
      final b = doc.checklists[1].items;
      expect(b.map((i) => i.type), everyElement(ChecklistItemType.check));
      expect(gates(b), [null, 'gpu/on', 'gpu/off', 'gpu/off', 'gpu/on']);
      expect(b[1].gate?.switchDef, const SwitchDef('gpu', defaultOn: true));
      expect(doc.warnings, isEmpty);
    });

    test('the state is the position of the first branch; ON when missing', () {
      final list = items('sw_switch:X|a\nsw_end\nsw_if|a\nsw_item:i\nsw_end');
      expect(list[1].gate?.whenOn, isTrue);
    });

    test('the keyword ignores case and an if may come before its switch', () {
      final doc = parse('''
sw_checklist:A
SW_IF|gpu|off
sw_item:early
sw_end
sw_checklist:B
sw_switch:Use GPU|gpu|ON
sw_end
''');
      final early = doc.checklists[0].items.single;
      expect(early.gate?.whenOn, isFalse);
      expect(early.gate?.switchDef.defaultOn, isTrue);
      expect(doc.warnings, isEmpty);
    });

    test('an unknown switch warns and its items are always shown', () {
      final doc = parse('sw_checklist:A\nsw_if|nope|ON\nsw_item:a\nsw_end');
      expect(doc.checklists.single.items.single.gate, isNull);
      expect(doc.warnings, [
        'Line 2: sw_if names the unknown switch "nope"; its items are always '
            'shown',
      ]);
    });

    test('a bad state warns and ON is assumed', () {
      final doc = parse(
        'sw_checklist:A\nsw_switch:X|a\nsw_end\nsw_if|a|maybe\nsw_item:i\nsw_end',
      );
      expect(doc.checklists.single.items.last.gate?.whenOn, isTrue);
      expect(doc.warnings, [
        'Line 4: sw_if state must be ON or OFF; ON assumed',
      ]);
    });

    test('a bad state on sw_switch warns and OFF is assumed', () {
      final doc = parse('sw_checklist:A\nsw_switch:X|a|maybe\nsw_end');
      expect(doc.checklists.single.items.single.switchDef!.defaultOn, isFalse);
      expect(doc.warnings, [
        'Line 2: sw_switch state must be ON or OFF; OFF assumed',
      ]);
    });
  });

  group('warnings (G6 to G9)', () {
    test('a block inside a block is ignored; the outer block carries on', () {
      final doc = parse('''
sw_checklist:A
sw_switch:Outer|o
sw_if|o|ON
sw_item:a
sw_else
sw_end
sw_item:b
sw_end
sw_item:c
''');
      final list = doc.checklists.single.items;
      expect(gates(list), [null, 'o/on', 'o/on', null]);
      expect(doc.warnings, ['Line 3: sw_if inside another block; ignored']);
    });

    test('a second switch inside a block is ignored with its row', () {
      final doc = parse('''
sw_checklist:A
sw_switch:Outer|o
sw_switch:Inner|i
sw_item:a
sw_end
sw_end
''');
      expect(doc.checklists.single.items, hasLength(2));
      expect(doc.warnings, ['Line 3: sw_switch inside another block; ignored']);
    });

    test('an end with no block warns and does nothing', () {
      final doc = parse('sw_checklist:A\nsw_item:a\nsw_end\nsw_item:b');
      expect(gates(doc.checklists.single.items), [null, null]);
      expect(doc.warnings, ['Line 3: sw_end without sw_if or sw_switch']);
    });

    test('an else with no block warns and does nothing', () {
      final doc = parse('sw_checklist:A\nsw_item:a\nsw_else\nsw_item:b');
      expect(gates(doc.checklists.single.items), [null, null]);
      expect(doc.warnings, ['Line 3: sw_else without sw_if or sw_switch']);
    });

    test(
      'a second else warns and is ignored; items stay in the OFF branch',
      () {
        final doc = parse(
          'sw_checklist:A\nsw_switch:X|a\nsw_else\nsw_item:i\nsw_else\nsw_item:j\nsw_end',
        );
        expect(gates(doc.checklists.single.items), [null, 'a/off', 'a/off']);
        expect(doc.warnings, ['Line 5: second sw_else in a block; ignored']);
      },
    );

    test('an unclosed block ends at the next checklist, with a warning', () {
      final doc = parse('''
sw_checklist:A
sw_switch:X|a
sw_item:a
sw_checklist:B
sw_item:b
''');
      expect(gates(doc.checklists[0].items), [null, 'a/on']);
      expect(doc.checklists[1].items.single.gate, isNull);
      expect(doc.warnings, [
        'Line 2: sw_switch has no sw_end; closed at the end of the checklist',
      ]);
    });

    test('an unclosed sw_if ends at the end of the file, with a warning', () {
      final doc = parse(
        'sw_checklist:A\nsw_switch:X|a\nsw_end\nsw_if|a|ON\nsw_item:a',
      );
      expect(doc.warnings, [
        'Line 4: sw_if has no sw_end; closed at the end of the checklist',
      ]);
    });

    test('a switch with no label is ignored and its items are not gated', () {
      final doc = parse('sw_checklist:A\nsw_switch:|a\nsw_item:a\nsw_end');
      expect(doc.checklists.single.items.single.gate, isNull);
      expect(doc.warnings, ['Line 2: sw_switch has no label; ignored']);
    });

    test('a switch with no id is ignored and its end is swallowed', () {
      final doc = parse('sw_checklist:A\nsw_switch:X\nsw_item:a\nsw_end');
      expect(doc.checklists.single.items.single.gate, isNull);
      expect(doc.warnings, ['Line 2: sw_switch has no switch id; ignored']);
    });

    test('a bare sw_switch and a bare sw_if are starts with nothing', () {
      final doc = parse(
        'sw_checklist:A\nsw_switch\nsw_end\nsw_if\nsw_item:a\nsw_end',
      );
      expect(doc.warnings, [
        'Line 2: sw_switch has no label; ignored',
        'Line 4: sw_if has no switch id; ignored',
      ]);
      expect(doc.checklists.single.items.single.gate, isNull);
    });

    test('a repeated switch id keeps the first and shows no second row', () {
      final doc = parse('''
sw_checklist:A
sw_switch:One|a|ON
sw_end
sw_switch:Two|a|OFF
sw_item:b
sw_end
''');
      final list = doc.checklists.single.items;
      expect(
        list.where((i) => i.type == ChecklistItemType.option),
        hasLength(1),
      );
      expect(list.last.gate?.whenOn, isTrue);
      expect(list.last.gate?.switchDef.defaultOn, isTrue);
      expect(doc.warnings, [
        'Line 4: duplicate switch "a"; first definition kept, no switch row',
      ]);
    });

    test('extra parts warn and are ignored', () {
      final doc = parse('sw_checklist:A\nsw_switch:X|a|ON|more\nsw_end');
      expect(doc.warnings, ['Line 2: sw_switch has extra parts; ignored']);
    });

    test('blocks before any checklist warn', () {
      final doc = parse(
        'sw_switch:X|a\nsw_else\nsw_end\nsw_if|a\nsw_checklist:A\nsw_item:a',
      );
      expect(doc.warnings, [
        'Line 1: item before any checklist',
        'Line 2: item before any checklist',
        'Line 3: item before any checklist',
        'Line 4: item before any checklist',
      ]);
    });

    test('the old sw_enable_start and sw_enable_end are unknown keywords', () {
      final doc = parse(
        'sw_checklist:A\nsw_enable_start:X\nsw_item:a\nsw_enable_end',
      );
      expect(doc.checklists.single.items, hasLength(1));
      expect(doc.warnings, [
        'Line 2: unknown keyword "sw_enable_start"',
        'Line 4: unrecognized line',
      ]);
    });
  });

  test('a bare sw_continue before a block counts as followed by an item', () {
    for (final start in ['sw_switch:X|a', 'sw_if|a|ON']) {
      final doc = parse('''
sw_checklist:A
sw_item:a
sw_continue:B
$start
sw_end
sw_checklist:B
sw_item:b
''');
      expect(
        doc.warnings,
        contains('Line 3: sw_continue should be at the end of its checklist'),
        reason: start,
      );
    }
  });
}
