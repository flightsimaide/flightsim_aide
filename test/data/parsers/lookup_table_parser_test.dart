import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/calculate_line.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/lookup_table.dart';
import 'package:flightsim_aide/domain/models/flight_sim/dataref.dart';
import 'package:flightsim_aide/domain/models/flight_sim/item_condition.dart';
import 'package:flutter_test/flutter_test.dart';

const _parser = AircraftWorkflowParser();

const _head = '''
sw_checklist:CRUISE
sw_item:Max cruise power|SET
''';

const _table = '''
sw_table:cruise|isa={sim/oat}-(15-0.00198*{sim/alt}), alt=sim/alt, w=sim/weight|torque, ff
sw_row:0,0,3000|36.9,600
sw_row:0,0,4000|36.9,610
sw_row:0,2000,3000|36.9,590
sw_row:0,2000,4000|36.9,600
sw_row:10,0,3000|35.0,580
sw_row:10,0,4000|35.0,590
sw_row:10,2000,3000|34.0,570
sw_row:10,2000,4000|34.0,580
sw_table_end
''';

void main() {
  // AC-55
  group('lookup tables (GRAMMAR.md section 5c)', () {
    test('reads a table, its input sources and its rows', () {
      final doc = _parser.parse('$_head$_table');
      expect(doc.warnings, isEmpty);
      final table = doc.tables['cruise']!;
      expect(table.name, 'cruise');
      expect(table.inputs.map((i) => i.name), ['isa', 'alt', 'w']);
      expect(table.outputs, ['torque', 'ff']);
      expect(table.rows, hasLength(8));
      expect(table.rows.first.inputs, [0, 0, 3000]);
      expect(table.rows.first.outputs, [36.9, 600]);
      expect(table.axes, [
        [0, 10],
        [0, 2000],
        [3000, 4000],
      ]);
    });

    test('a bare dataref and an expression become value expressions', () {
      final table = _parser.parse('$_head$_table').tables['cruise']!;
      expect(table.inputs[1].source, const DatarefExpr(Dataref('sim/alt')));
      expect(table.inputs[0].source, isA<BinaryExpr>());
      expect(table.signals, [
        const Dataref('sim/oat'),
        const Dataref('sim/alt'),
        const Dataref('sim/weight'),
      ]);
    });

    test('an input column may carry a label and a unit', () {
      final doc = _parser.parse(
        '${_head}sw_table:t|alt(Altitude, ft)=sim/a, w(Weight)=sim/w, '
        'isa( , C)=sim/i, plain=sim/p|y\n'
        'sw_row:0,0,0,0|1\nsw_table_end\n',
      );
      expect(doc.warnings, isEmpty);
      final inputs = doc.tables['t']!.inputs;
      expect(inputs.map((i) => i.name), ['alt', 'w', 'isa', 'plain']);
      expect(inputs.map((i) => i.label), ['Altitude', 'Weight', '', '']);
      expect(inputs.map((i) => i.unit), ['ft', '', 'C', '']);
      expect(inputs.map((i) => i.title), [
        'Altitude',
        'Weight',
        'isa',
        'plain',
      ]);
    });

    test('a comma inside a function call is not split off the label', () {
      final doc = _parser.parse(
        '${_head}sw_table:t|d(Delta, x)=round({sim/a}/closer_than(1,2,3))|y\n'
        'sw_row:0|1\nsw_table_end\n',
      );
      expect(doc.warnings, isEmpty);
      expect(doc.tables['t']!.inputs.single.label, 'Delta');
      expect(doc.tables['t']!.inputs.single.unit, 'x');
    });

    test('an array element can be a source', () {
      final doc = _parser.parse(
        '${_head}sw_table:t|x=sim/arr[2]|y\nsw_row:1|2\nsw_table_end\n',
      );
      expect(doc.warnings, isEmpty);
      expect(
        doc.tables['t']!.inputs.single.source,
        const DatarefExpr(Dataref('sim/arr', 2)),
      );
    });

    test('a table adds no checklist and no item', () {
      final doc = _parser.parse('$_head$_table');
      expect(doc.checklists, hasLength(1));
      expect(doc.checklists.single.items, hasLength(1));
    });

    test('a table may stand before the checklists', () {
      final doc = _parser.parse('$_table$_head');
      expect(doc.warnings, isEmpty);
      expect(doc.tables, hasLength(1));
      expect(doc.checklists, hasLength(1));
    });

    test('names are lower-cased', () {
      final doc = _parser.parse(
        '${_head}sw_table:Cruise|X=sim/a|Y\nsw_row:1|2\nsw_table_end\n'
        'sw_calculate:CRUISE|Y\n',
      );
      expect(doc.warnings, isEmpty);
      expect(doc.tables.keys, ['cruise']);
    });
  });

  group('sw_calculate', () {
    test('attaches to the check item above it, in order', () {
      final doc = _parser.parse(
        '$_head'
        'sw_calculate:cruise|torque|Torque|psi|0.1\n'
        'sw_calculate:cruise|ff\n'
        '$_table',
      );
      expect(doc.warnings, isEmpty);
      final item = doc.checklists.single.items.single;
      expect(item.calculations, const [
        CalculateLine(
          table: 'cruise',
          column: 'torque',
          label: 'Torque',
          unit: 'psi',
          step: 0.1,
        ),
        CalculateLine(table: 'cruise', column: 'ff', label: 'ff'),
      ]);
    });

    test('a details line may sit between the item and the line', () {
      final doc = _parser.parse(
        '$_head'
        'sw_item_details:More\n'
        'sw_calculate:cruise|torque\n'
        '$_table',
      );
      expect(doc.warnings, isEmpty);
      final items = doc.checklists.single.items;
      expect(items[0].calculations, hasLength(1));
      expect(items[1].type, ChecklistItemType.details);
    });

    test('keeps the gate and the condition of its item', () {
      final doc = _parser.parse(
        'sw_checklist:C\n'
        'sw_switch:Switch|s|OFF\n'
        'sw_item:Power|SET:sim/x:1\n'
        'sw_calculate:cruise|torque\n'
        'sw_end\n'
        '$_table',
      );
      expect(doc.warnings, isEmpty);
      final power = doc.checklists.single.items[1];
      expect(power.calculations, hasLength(1));
      expect(power.gate, isNotNull);
      expect(power.condition, isNotNull);
    });

    test('an unknown table or column warns and is dropped', () {
      final doc = _parser.parse(
        '$_head'
        'sw_calculate:nothere|torque\n'
        'sw_calculate:cruise|nothere\n'
        '$_table',
      );
      expect(doc.warnings, [
        'Line 3: sw_calculate names the unknown table "nothere"; ignored',
        'Line 4: table "cruise" has no output column "nothere"; '
            'sw_calculate ignored',
      ]);
      expect(doc.checklists.single.items.single.calculations, isEmpty);
    });

    test('an input column is not an output', () {
      final doc = _parser.parse('$_head${_table}sw_calculate:cruise|alt\n');
      expect(doc.warnings, hasLength(1));
      expect(doc.warnings.single, contains('no output column "alt"'));
    });

    test('with no check item above it warns', () {
      final doc = _parser.parse(
        'sw_checklist:C\n'
        'sw_calculate:cruise|torque\n'
        'sw_item:A|B\n'
        'sw_remark:Note\n'
        'sw_calculate:cruise|torque\n'
        '$_table',
      );
      expect(doc.warnings, [
        'Line 2: sw_calculate is not under a check item; ignored',
        'Line 5: sw_calculate is not under a check item; ignored',
      ]);
    });

    test('before any checklist warns', () {
      final doc = _parser.parse('sw_calculate:cruise|torque\n');
      expect(doc.warnings.first, 'Line 1: item before any checklist');
    });

    test('bad parts warn', () {
      final doc = _parser.parse(
        '${_head}sw_calculate:cruise\n'
        'sw_calculate:cruise|torque|T|psi|zero\n'
        'sw_calculate:cruise|ff|F|lb|-2\n'
        '$_table',
      );
      expect(doc.warnings, [
        'Line 3: sw_calculate needs table|column; ignored',
        'Line 4: sw_calculate rounding must be a number above 0; 1 assumed',
        'Line 5: sw_calculate rounding must be a number above 0; 1 assumed',
      ]);
      expect(doc.checklists.single.items.single.calculations, hasLength(2));
    });
  });

  group('table faults', () {
    test('a row outside a table warns', () {
      final doc = _parser.parse('${_head}sw_row:1|2\n');
      expect(doc.warnings, ['Line 3: sw_row outside sw_table; ignored']);
    });

    test('sw_table_end without a table warns', () {
      final doc = _parser.parse('${_head}sw_table_end\n');
      expect(doc.warnings, ['Line 3: sw_table_end without sw_table']);
    });

    test('a row with the wrong count or a non-number is skipped', () {
      final doc = _parser.parse(
        '${_head}sw_table:t|x=sim/a|y\n'
        'sw_row:1,2|3\n'
        'sw_row:1|3,4\n'
        'sw_row:one|3\n'
        'sw_row:1\n'
        'sw_row:1|3\n'
        'sw_table_end\n',
      );
      expect(doc.warnings, [
        'Line 4: sw_row has 2 input and 1 output values; table "t" needs 1 '
            'and 1; row skipped',
        'Line 5: sw_row has 1 input and 2 output values; table "t" needs 1 '
            'and 1; row skipped',
        'Line 6: sw_row needs numbers as in,in|out,out; row skipped',
        'Line 7: sw_row needs numbers as in,in|out,out; row skipped',
      ]);
      expect(doc.tables['t']!.rows, hasLength(1));
    });

    test('a table with a missing grid point is ignored', () {
      final doc = _parser.parse(
        '${_head}sw_table:t|x=sim/a,y=sim/b|z\n'
        'sw_row:0,0|1\n'
        'sw_row:0,5|2\n'
        'sw_row:1,0|3\n'
        'sw_table_end\n',
      );
      expect(doc.warnings, [
        'Line 3: sw_table "t" has no row for (1.0,5.0); ignored',
      ]);
      expect(doc.tables, isEmpty);
    });

    test('a table with two rows for one point is ignored', () {
      final doc = _parser.parse(
        '${_head}sw_table:t|x=sim/a|z\n'
        'sw_row:0|1\n'
        'sw_row:0|2\n'
        'sw_table_end\n',
      );
      expect(doc.warnings, [
        'Line 3: sw_table "t" has two rows for (0.0); ignored',
      ]);
    });

    test('a table with no rows is ignored', () {
      final doc = _parser.parse('${_head}sw_table:t|x=sim/a|z\nsw_table_end\n');
      expect(doc.warnings, ['Line 3: sw_table "t" has no rows; ignored']);
    });

    test('a table with no sw_table_end is closed at the next other line', () {
      final doc = _parser.parse(
        '${_head}sw_table:t|x=sim/a|z\n'
        'sw_row:0|1\n'
        'sw_item:After|OK\n',
      );
      expect(doc.warnings, [
        'Line 3: sw_table "t" has no sw_table_end; closed there',
      ]);
      expect(doc.tables, hasLength(1));
      expect(doc.checklists.single.items, hasLength(2));
    });

    test('a table open at the end of the file is closed there', () {
      final doc = _parser.parse('${_head}sw_table:t|x=sim/a|z\nsw_row:0|1\n');
      expect(doc.warnings, [
        'Line 3: sw_table "t" has no sw_table_end; closed there',
      ]);
      expect(doc.tables, hasLength(1));
    });

    test('a second table of the same name keeps the first', () {
      final doc = _parser.parse(
        '$_head$_table'
        'sw_table:cruise|x=sim/a|z\n'
        'sw_row:1|2\n'
        'sw_table_end\n',
      );
      expect(doc.warnings, [
        'Line 13: duplicate table "cruise"; first definition kept',
      ]);
      expect(doc.tables['cruise']!.outputs, ['torque', 'ff']);
    });

    for (final (text, reason) in [
      ('sw_table:t|x=sim/a', 'sw_table needs name|inputs|outputs; ignored'),
      ('sw_table:|x=sim/a|y', 'sw_table has a bad name ""; ignored'),
      (
        'sw_table:t|sim/a|y',
        'sw_table "t" has a bad or repeated input column "sim/a"; ignored',
      ),
      (
        'sw_table:t|x=sim/a,x=sim/b|y',
        'sw_table "t" has a bad or repeated input column "x"; ignored',
      ),
      (
        'sw_table:t|x=sim/a|x',
        'sw_table "t" has a bad or repeated output column "x"; ignored',
      ),
      ('sw_table:t|x={sim/a|y', 'sw_table "t" input "x":'),
      ('sw_table:t||y', 'sw_table "t" has a bad or repeated input column'),
      (
        'sw_table:t|x(Altitude=sim/a|y',
        'sw_table "t" has a bad or repeated input column "x(Altitude"',
      ),
    ]) {
      test('a bad start line is ignored with its rows: $text', () {
        final doc = _parser.parse(
          '$_head$text\nsw_row:1|2\nsw_table_end\nsw_calculate:t|y\n',
        );
        expect(doc.warnings.first, startsWith('Line 3: '));
        expect(doc.warnings.first, contains(reason));
        expect(doc.tables, isEmpty);
        // The rows and the end line of a rejected table add no warning.
        expect(doc.warnings.where((w) => w.contains('sw_row')), isEmpty);
        expect(doc.warnings.where((w) => w.contains('sw_table_end')), isEmpty);
      });
    }

    test('too many input columns are refused', () {
      final doc = _parser.parse(
        '${_head}sw_table:t|a=sim/a,b=sim/b,c=sim/c,d=sim/d,e=sim/e|y\n'
        'sw_row:1,2,3,4,5|1\n'
        'sw_table_end\n',
      );
      expect(doc.warnings.first, contains('needs 1 to 4 input columns'));
      expect(doc.tables, isEmpty);
    });

    test('a comma inside a function call does not split the inputs', () {
      final doc = _parser.parse(
        '${_head}sw_table:t|d=round({sim/a}/closer_than(1,2,3))|y\n'
        'sw_row:0|1\n'
        'sw_table_end\n',
      );
      expect(doc.warnings, isEmpty);
      expect(doc.tables['t']!.inputs.single.name, 'd');
    });
  });

  group('LookupTable.problem', () {
    TableRow row(List<double> i) => TableRow(i, const [0]);

    test('a complete grid has no problem', () {
      expect(
        LookupTable.problem(2, [
          row([0, 0]),
          row([0, 1]),
          row([1, 0]),
          row([1, 1]),
        ]),
        isNull,
      );
    });

    test('names the first missing point', () {
      expect(
        LookupTable.problem(2, [
          row([0, 0]),
          row([0, 1]),
          row([1, 0]),
        ]),
        'has no row for (1.0,1.0)',
      );
    });

    test('rows may come in any order', () {
      expect(
        LookupTable.problem(1, [
          row([2]),
          row([0]),
          row([1]),
        ]),
        isNull,
      );
    });

    test('too many rows', () {
      final rows = [
        for (var i = 0; i <= LookupTable.maxRows; i++) row([i.toDouble()]),
      ];
      expect(LookupTable.problem(1, rows), contains('more than'));
    });
  });
}
