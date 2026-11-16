import 'package:equatable/equatable.dart';

/// A `sw_calculate` line: one value read out of a lookup table for the
/// current aircraft state and shown under the item above it (`GRAMMAR.md`
/// section 5c). It is looked up live and never saved.
class CalculateLine extends Equatable {
  /// Creates a line; [step] is what the shown value is rounded to.
  const CalculateLine({
    required this.table,
    required this.column,
    required this.label,
    this.unit = '',
    this.step = 1,
  }) : assert(step > 0);

  /// The table name, lower case.
  final String table;

  /// The output column name, lower case.
  final String column;

  /// The text before the value; the column name when the line gave none.
  final String label;

  /// The text after the value, empty if none.
  final String unit;

  /// The value is rounded to a multiple of this (`0.1`, `1`, `10`).
  final double step;

  @override
  List<Object?> get props => [table, column, label, unit, step];
}
