import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/calculate_line.dart';
import 'package:flightsim_aide/domain/models/checklist/calculated_value.dart';
import 'package:flightsim_aide/domain/models/checklist/lookup_table.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/condition_evaluator.dart';
import 'package:flightsim_aide/domain/use_cases/calculate/calculate_line_value_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

// AC-56: a calculated value is a live interpolation of the table, held at the
// edge outside it, and absent while an input has no value.

const _useCase = CalculateLineValueUseCase();

/// A table with two inputs whose output is the plane 2x + 3y + 1, so the
/// interpolation is exact anywhere inside it.
const _plane = '''
sw_table:plane|x=sim/x, y=sim/y|z
sw_row:0,0|1
sw_row:0,100|301
sw_row:10,0|21
sw_row:10,100|321
sw_table_end
''';

LookupTable _table(String text, [String name = 'plane']) =>
    const AircraftWorkflowParser().parse(text).tables[name]!;

CalculatedValue _calc(
  LookupTable table,
  Map<String, double?> values, {
  String column = 'z',
  double step = 0.001,
}) => _useCase.calculate(
  table,
  CalculateLine(table: table.name, column: column, label: column, step: step),
  MapValues(values),
);

void main() {
  group('interpolation (AC-56)', () {
    final table = _table(_plane);

    test('gives the row value at a grid point', () {
      expect(_calc(table, {'sim/x': 0, 'sim/y': 0}), const CalculatedValue(1));
      expect(
        _calc(table, {'sim/x': 10, 'sim/y': 100}),
        const CalculatedValue(321),
      );
    });

    test('interpolates between grid points on every input', () {
      expect(
        _calc(table, {'sim/x': 5, 'sim/y': 50}),
        const CalculatedValue(161),
      );
      expect(
        _calc(table, {'sim/x': 2.5, 'sim/y': 10}),
        const CalculatedValue(36),
      );
    });

    test('uses the rows around the point on a column with many values', () {
      final t = _table(
        'sw_table:t|x=sim/x|y\n'
            'sw_row:20|150\nsw_row:0|0\nsw_row:10|100\nsw_table_end\n',
        't',
      );
      expect(_calc(t, {'sim/x': 5}, column: 'y'), const CalculatedValue(50));
      expect(_calc(t, {'sim/x': 15}, column: 'y'), const CalculatedValue(125));
      expect(_calc(t, {'sim/x': 10}, column: 'y'), const CalculatedValue(100));
    });

    test('reads the right output column', () {
      final t = _table(
        'sw_table:t|x=sim/x|a,b\nsw_row:0|1,10\nsw_row:10|3,30\nsw_table_end\n',
        't',
      );
      expect(_calc(t, {'sim/x': 5}, column: 'a'), const CalculatedValue(2));
      expect(_calc(t, {'sim/x': 5}, column: 'b'), const CalculatedValue(20));
    });

    test('an input may be an expression of datarefs', () {
      final t = _table(
        'sw_table:t|d={sim/a}-(10-{sim/b})|y\n'
            'sw_row:0|0\nsw_row:10|100\nsw_table_end\n',
        't',
      );
      // d = 8 - (10 - 7) = 5
      expect(
        _calc(t, {'sim/a': 8, 'sim/b': 7}, column: 'y'),
        const CalculatedValue(50),
      );
    });
  });

  group('outside the table (AC-56)', () {
    final table = _table(_plane);

    test('holds the input at the edge and says so', () {
      expect(
        _calc(table, {'sim/x': -5, 'sim/y': 0}),
        const CalculatedValue(1, outsideTable: true),
      );
      expect(
        _calc(table, {'sim/x': 5, 'sim/y': 500}),
        const CalculatedValue(311, outsideTable: true),
      );
    });

    test('exactly at the edge is inside', () {
      expect(
        _calc(table, {'sim/x': 10, 'sim/y': 0}),
        const CalculatedValue(21),
      );
    });

    test('a column with one value matches only that value', () {
      final t = _table('sw_table:t|x=sim/x|y\nsw_row:5|7\nsw_table_end\n', 't');
      expect(_calc(t, {'sim/x': 5}, column: 'y'), const CalculatedValue(7));
      expect(
        _calc(t, {'sim/x': 6}, column: 'y'),
        const CalculatedValue(7, outsideTable: true),
      );
    });
  });

  group('no value (AC-56)', () {
    final table = _table(_plane);

    test('an input with no value gives none', () {
      expect(_calc(table, {'sim/x': 5}), const CalculatedValue.unavailable());
      expect(
        _calc(table, {'sim/x': null, 'sim/y': 5}),
        const CalculatedValue.unavailable(),
      );
    });

    test('a value that is not a finite number gives none', () {
      expect(
        _calc(table, {'sim/x': double.nan, 'sim/y': 5}),
        const CalculatedValue.unavailable(),
      );
      expect(
        _calc(table, {'sim/x': double.infinity, 'sim/y': 5}),
        const CalculatedValue.unavailable(),
      );
    });

    test('a column the table has not gives none', () {
      expect(
        _calc(table, {'sim/x': 5, 'sim/y': 5}, column: 'nope'),
        const CalculatedValue.unavailable(),
      );
    });

    test('the unavailable value has no number', () {
      expect(const CalculatedValue.unavailable().isAvailable, isFalse);
      expect(const CalculatedValue(0).isAvailable, isTrue);
    });
  });

  group('rounding (AC-56)', () {
    final table = _table(_plane);

    test('rounds to the step of the line', () {
      final values = {'sim/x': 2.37, 'sim/y': 0.0}; // 2*2.37 + 1 = 5.74
      expect(_calc(table, values, step: 0.1).value, 5.7);
      expect(_calc(table, values, step: 1).value, 6);
      expect(_calc(table, values, step: 10).value, 10);
      expect(_calc(table, values, step: 0.01).value, 5.74);
    });

    test('leaves no floating point noise', () {
      final t = _table(
        'sw_table:t|x=sim/x|y\nsw_row:0|36.9\nsw_row:10|36.9\nsw_table_end\n',
        't',
      );
      expect(_calc(t, {'sim/x': 3}, column: 'y', step: 0.1).value, 36.9);
    });
  });

  group('LookupTable.rowAt', () {
    test('finds a row by its grid position', () {
      final table = _table(_plane);
      expect(table.rowAt([1, 0]).outputs, [21]);
      expect(table.rowAt([0, 1]).outputs, [301]);
    });
  });
}
