import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/flight_sim/dataref.dart';
import 'package:flightsim_aide/domain/models/flight_sim/item_condition.dart';
import 'package:flutter_test/flutter_test.dart';

const _parser = AircraftWorkflowParser();

void main() {
  // AC-66
  group('quoted names in a file (GRAMMAR.md N6)', () {
    test('an item, a continue link and a plain item together', () {
      final doc = _parser.parse(
        'sw_checklist:A\n'
        'sw_item:Battery 1|ON:"L:ELECTRICAL_Switch_BATTERY_Bus_1":1\n'
        'sw_item:Gen|ON:"A:GENERAL ENG MASTER ALTERNATOR:1, bool":1\n'
        "sw_item:Pilot's seat|SET:'L:SEAT, number':2\n"
        'sw_item:Gear|DOWN:sim/gear:1\n'
        'sw_continue:B:"L:next, bool":1\n'
        'sw_checklist:B\n'
        'sw_item:x|y',
      );
      expect(doc.warnings, isEmpty);
      final items = doc.checklists.first.items;
      expect(items[0].label, 'Battery 1');
      expect(items[0].result, 'ON');
      expect(
        items[0].condition,
        const CompareCondition(
          DatarefExpr(Dataref('L:ELECTRICAL_Switch_BATTERY_Bus_1')),
          CompareOp.equal,
          NumberExpr(1),
        ),
      );
      expect(
        items[1].condition,
        const CompareCondition(
          DatarefExpr(Dataref('A:GENERAL ENG MASTER ALTERNATOR:1, bool')),
          CompareOp.equal,
          NumberExpr(1),
        ),
      );
      expect(items[2].label, "Pilot's seat");
      expect(items[2].result, 'SET');
      expect(items[2].condition, isNotNull);
      expect(items[3].condition, isNotNull);
    });

    test('an item without a result and a quoted name', () {
      final doc = _parser.parse(
        'sw_checklist:A\nsw_item:Battery:"L:x, bool":1',
      );
      expect(doc.warnings, isEmpty);
      final item = doc.checklists.single.items.single;
      expect(item.label, 'Battery');
      expect(item.condition, isNotNull);
    });

    test('a bad quote warns and leaves the item manual', () {
      final doc = _parser.parse('sw_checklist:A\nsw_item:x|ON:"L:y:1');
      expect(doc.warnings.single, contains('unterminated quote'));
      expect(doc.checklists.single.items.single.condition, isNull);
    });
  });

  group('item conditions', () {
    test(
      'a condition fills ChecklistItem.condition; label and result stay',
      () {
        final doc = _parser.parse(
          'sw_checklist:A\nsw_item:Gear|DOWN:sim/gear:1\nsw_item:Brakes|SET',
        );
        final gear = doc.checklists.single.items[0];
        expect(gear.label, 'Gear');
        expect(gear.result, 'DOWN');
        expect(
          gear.condition,
          const CompareCondition(
            DatarefExpr(Dataref('sim/gear')),
            CompareOp.equal,
            NumberExpr(1),
          ),
        );
        expect(doc.checklists.single.items[1].condition, isNull);
        expect(doc.warnings, isEmpty);
      },
    );

    test('a range after the result is the condition, not a result', () {
      final doc = _parser.parse(
        'sw_checklist:A\nsw_item:Alt|OK:sim/alt:100|200',
      );
      expect(
        doc.checklists.single.items.single.condition,
        const RangeCondition(
          DatarefExpr(Dataref('sim/alt')),
          NumberExpr(100),
          NumberExpr(200),
        ),
      );
    });

    test('with no pipe the first colon starts the condition', () {
      final doc = _parser.parse('sw_checklist:A\nsw_item:Gear:sim/gear:1');
      final item = doc.checklists.single.items.single;
      expect(item.label, 'Gear');
      expect(item.condition, isNotNull);
    });

    test('a colon with nothing after it is no condition and no warning', () {
      final doc = _parser.parse('sw_checklist:A\nsw_item:Gear|OK:');
      expect(doc.checklists.single.items.single.condition, isNull);
      expect(doc.warnings, isEmpty);
    });

    test('a bad condition keeps the item manual and warns with the line', () {
      final doc = _parser.parse(
        'sw_checklist:A\n\nsw_item:Gear|OK:sim/gear:(1\nsw_item:Next|OK',
      );
      expect(doc.checklists.single.items, hasLength(2));
      expect(doc.checklists.single.items[0].condition, isNull);
      expect(doc.warnings, [
        'Line 3: condition not supported: unbalanced parentheses',
      ]);
    });

    test('an info line parses its condition but keeps no condition', () {
      final doc = _parser.parse(
        'sw_checklist:A\nsw_iteminfo:Note:sim/x:1\nsw_item:One|OK',
      );
      final note = doc.checklists.single.items.first;
      expect(note.type, ChecklistItemType.note);
      expect(note.condition, isNull);
      expect(doc.warnings, isEmpty);
    });

    test('an info line with a bad condition warns', () {
      final doc = _parser.parse(
        'sw_checklist:A\nsw_iteminfo:Note:sim/x:(1\nsw_item:One|OK',
      );
      expect(doc.warnings, [
        'Line 2: condition not supported: unbalanced parentheses',
      ]);
    });

    test('the condition makes two equal items different', () {
      final a = _parser.parse('sw_checklist:A\nsw_item:Gear|OK:x:1');
      final b = _parser.parse('sw_checklist:A\nsw_item:Gear|OK:x:2');
      expect(
        a.checklists.single.items.single,
        isNot(b.checklists.single.items.single),
      );
    });
  });

  group('conditional sw_continue', () {
    test('the condition after the second colon fills the link', () {
      final doc = _parser.parse(
        'sw_checklist:A\nsw_item:One|OK\nsw_continue:B:sim/x:1\n'
        'sw_checklist:B\nsw_item:Two|OK',
      );
      final link = doc.checklists.first.continues.single;
      expect(link.target, 'B');
      expect(link.condition, isNotNull);
    });

    test('a link without a condition has none', () {
      final doc = _parser.parse(
        'sw_checklist:A\nsw_item:One|OK\nsw_continue:B\n'
        'sw_checklist:B\nsw_item:Two|OK',
      );
      expect(doc.checklists.first.continues.single.condition, isNull);
    });

    test('a link with a bad condition is dropped with a warning', () {
      final doc = _parser.parse(
        'sw_checklist:A\nsw_item:One|OK\nsw_continue:B:sim/x:(1\n'
        'sw_checklist:B\nsw_item:Two|OK',
      );
      expect(doc.checklists.first.continues, isEmpty);
      expect(doc.warnings, [
        'Line 3: condition not supported: unbalanced parentheses',
      ]);
    });
  });
}
