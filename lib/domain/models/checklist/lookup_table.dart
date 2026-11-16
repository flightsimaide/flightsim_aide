import 'package:equatable/equatable.dart';

import '../flight_sim/dataref.dart';
import '../flight_sim/item_condition.dart';

/// An input column of a [LookupTable]: a name and the value of the aircraft
/// state it is matched against (`GRAMMAR.md` section 5c).
class TableInput extends Equatable {
  /// Creates an input column. [label] and [unit] are for the messages that
  /// name this input (`GRAMMAR.md` L1); both may be empty.
  const TableInput(this.name, this.source, {this.label = '', this.unit = ''});

  /// The column name, lower case.
  final String name;

  /// The name shown to the pilot (`Altitude`), empty when the file gave none.
  final String label;

  /// The unit of the input (`ft`), empty when the file gave none.
  final String unit;

  /// What to call the input in a message: [label], or [name] without one.
  String get title => label.isEmpty ? name : label;

  /// The live value this column is matched with: a dataref or an arithmetic
  /// expression of datarefs.
  final ValueExpr source;

  @override
  List<Object?> get props => [name, source, label, unit];
}

/// One `sw_row` line: the input values and the output values.
class TableRow extends Equatable {
  /// Creates a row.
  const TableRow(this.inputs, this.outputs);

  /// One value per input column.
  final List<double> inputs;

  /// One value per output column.
  final List<double> outputs;

  @override
  List<Object?> get props => [inputs, outputs];
}

/// A table of numbers defined by `sw_table`, `sw_row` and `sw_table_end`. It is
/// never shown; `sw_calculate` lines read values out of it.
///
/// The input values of the rows form a complete grid: every combination of the
/// distinct values of the input columns has exactly one row. [problem] says
/// why a set of rows is not one.
class LookupTable extends Equatable {
  /// Creates a table. Check the rows with [problem] first; the grid axes are
  /// worked out from them.
  LookupTable({
    required this.name,
    required List<TableInput> inputs,
    required List<String> outputs,
    required List<TableRow> rows,
  }) : inputs = List.unmodifiable(inputs),
       outputs = List.unmodifiable(outputs),
       rows = List.unmodifiable(rows),
       axes = List.unmodifiable([
         for (var i = 0; i < inputs.length; i++) _axis(rows, i),
       ]);

  /// The most input columns a table may have.
  static const maxInputs = 4;

  /// The most rows a table may have.
  static const maxRows = 20000;

  /// The table name, lower case.
  final String name;

  /// The input columns, in the order of the values of every row.
  final List<TableInput> inputs;

  /// The output column names, in the order of the values of every row.
  final List<String> outputs;

  /// The rows, in file order.
  final List<TableRow> rows;

  /// For each input column, its distinct row values in increasing order.
  final List<List<double>> axes;

  /// The row at grid position [index], one position per input column (the
  /// position of the value in [axes]). Only for a table whose rows passed
  /// [problem]; throws [StateError] for a point with no row.
  TableRow rowAt(List<int> index) {
    var at = 0;
    for (var i = 0; i < axes.length; i++) {
      at = at * axes[i].length + index[i];
    }
    return _grid[at] ?? (throw StateError('no row at $index'));
  }

  late final List<TableRow?> _grid = _buildGrid();

  List<TableRow?> _buildGrid() {
    var size = 1;
    for (final axis in axes) {
      size *= axis.length;
    }
    final grid = List<TableRow?>.filled(size, null);
    for (final row in rows) {
      var at = 0;
      for (var i = 0; i < axes.length; i++) {
        at = at * axes[i].length + axes[i].indexOf(row.inputs[i]);
      }
      grid[at] = row;
    }
    return grid;
  }

  /// Whether [column] is an output column of this table.
  bool hasOutput(String column) => outputs.contains(column);

  /// Every dataref the inputs read, each once, in order of appearance.
  List<Dataref> get signals {
    final seen = <Dataref>{};
    return [
      for (final input in inputs)
        for (final d in input.source.signals)
          if (seen.add(d)) d,
    ];
  }

  static List<double> _axis(List<TableRow> rows, int column) {
    final values = {for (final row in rows) row.inputs[column]}.toList()
      ..sort();
    return values;
  }

  /// Why [rows] do not form a complete grid over [inputCount] input columns,
  /// or null when they do. Reports the first fault found.
  static String? problem(int inputCount, List<TableRow> rows) {
    if (rows.isEmpty) return 'has no rows';
    if (rows.length > maxRows) return 'has more than $maxRows rows';
    final axes = [for (var i = 0; i < inputCount; i++) _axis(rows, i)];
    var expected = 1;
    for (final axis in axes) {
      expected *= axis.length;
    }
    final seen = <String>{};
    for (final row in rows) {
      final key = row.inputs.join(',');
      if (!seen.add(key)) return 'has two rows for ($key)';
    }
    if (rows.length == expected) return null;
    // Some combination of the axis values has no row: name the first one.
    final index = List<int>.filled(inputCount, 0);
    while (true) {
      final key = [for (var i = 0; i < inputCount; i++) axes[i][index[i]]];
      if (!seen.contains(key.join(','))) {
        return 'has no row for (${key.join(',')})';
      }
      var column = inputCount - 1;
      while (column >= 0 && ++index[column] == axes[column].length) {
        index[column] = 0;
        column--;
      }
      if (column < 0) return 'is not a complete grid';
    }
  }

  @override
  List<Object?> get props => [name, inputs, outputs, rows];
}
