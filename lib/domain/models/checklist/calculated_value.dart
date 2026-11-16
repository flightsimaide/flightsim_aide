import 'package:equatable/equatable.dart';

/// An input of a table that is beyond the range of its column, so the value
/// was worked out for the nearest edge instead (`GRAMMAR.md` L8).
class LimitExceeded extends Equatable {
  /// Creates the record.
  const LimitExceeded({
    required this.name,
    required this.actual,
    required this.limit,
    required this.above,
    this.unit = '',
  });

  /// What to call the input (its label, or its column name).
  final String name;

  /// The unit of the input, empty if none.
  final String unit;

  /// The value the input has now.
  final double actual;

  /// The edge of the table that was used instead.
  final double limit;

  /// Whether [actual] is above the table ([limit] is its highest value), not
  /// below it.
  final bool above;

  @override
  List<Object?> get props => [name, unit, actual, limit, above];
}

/// What a `sw_calculate` line shows for the aircraft's state right now
/// (`GRAMMAR.md` section 5c). Worked out live; never saved.
class CalculatedValue extends Equatable {
  /// A value, rounded to the line's step. [limits] names each input that was
  /// beyond the table, so the value is the nearest edge's.
  const CalculatedValue(this.value, {this.limits = const []});

  /// No value: an input has none (the sim gives no value for it, or the link
  /// is down) or the table has no such column.
  const CalculatedValue.unavailable() : value = null, limits = const [];

  /// The number, or null when [isAvailable] is false.
  final double? value;

  /// The inputs that were beyond the range of the table, in column order.
  final List<LimitExceeded> limits;

  /// Whether there is a number to show.
  bool get isAvailable => value != null;

  /// Whether an input was beyond the table, so the value is not an
  /// interpolation but the nearest edge's.
  bool get outsideTable => limits.isNotEmpty;

  @override
  List<Object?> get props => [value, limits];
}
