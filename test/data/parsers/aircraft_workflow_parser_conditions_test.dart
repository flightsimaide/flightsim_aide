import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/flight_sim/dataref.dart';
import 'package:flightsim_aide/domain/models/flight_sim/item_condition.dart';
import 'package:flutter_test/flutter_test.dart';

const _parser = AircraftWorkflowParser();

void main() {
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
