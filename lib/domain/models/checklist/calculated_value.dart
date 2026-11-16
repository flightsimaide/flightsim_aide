import 'package:equatable/equatable.dart';

/// What a `sw_calculate` line shows for the aircraft's state right now
/// (`GRAMMAR.md` section 5c). Worked out live; never saved.
class CalculatedValue extends Equatable {
  /// A value, rounded to the line's step. [outsideTable] is true when an input
  /// was beyond the table's range, so the value is the nearest edge's.
  const CalculatedValue(this.value, {this.outsideTable = false});

  /// No value: an input has none (the sim gives no value for it, or the link
  /// is down) or the table has no such column.
  const CalculatedValue.unavailable() : value = null, outsideTable = false;

  /// The number, or null when [isAvailable] is false.
  final double? value;

  /// Whether an input was outside the range of the table, so the value is not
  /// an interpolation but the nearest edge's.
  final bool outsideTable;

  /// Whether there is a number to show.
  bool get isAvailable => value != null;

  @override
  List<Object?> get props => [value, outsideTable];
}
