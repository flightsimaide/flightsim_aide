import '../../models/checklist/calculate_line.dart';
import '../../models/checklist/calculated_value.dart';
import '../../models/checklist/lookup_table.dart';
import '../autocheck/condition_evaluator.dart';

/// Works out the value of a `sw_calculate` line from a [LookupTable] and the
/// current values of its input sources (`GRAMMAR.md` section 5c, T7).
///
/// The value is a multilinear interpolation between the grid points around the
/// inputs. An input beyond the range of its column is held at the nearest edge
/// and the result says so ([CalculatedValue.outsideTable]). An input with no
/// value, or one that is not a finite number, gives no value (N4). Pure.
class CalculateLineValueUseCase {
  /// Creates the use case.
  const CalculateLineValueUseCase([
    this._evaluator = const ConditionEvaluator(),
  ]);

  final ConditionEvaluator _evaluator;

  /// The value of [line] in [table] for the input values in [values], rounded
  /// to [CalculateLine.step].
  CalculatedValue calculate(
    LookupTable table,
    CalculateLine line,
    ValueLookup values,
  ) {
    final column = table.outputs.indexOf(line.column);
    if (column < 0) return const CalculatedValue.unavailable();
    final lows = <int>[];
    final fractions = <double>[];
    var outside = false;
    for (var i = 0; i < table.inputs.length; i++) {
      final x = _evaluator.evaluateExpr(table.inputs[i].source, values);
      if (x == null || !x.isFinite) return const CalculatedValue.unavailable();
      final axis = table.axes[i];
      final last = axis.length - 1;
      if (axis.length == 1) {
        outside = outside || x != axis.first;
        lows.add(0);
        fractions.add(0);
      } else if (x <= axis.first) {
        outside = outside || x < axis.first;
        lows.add(0);
        fractions.add(0);
      } else if (x >= axis.last) {
        outside = outside || x > axis.last;
        lows.add(last);
        fractions.add(0);
      } else {
        var low = 0;
        while (axis[low + 1] <= x) {
          low++;
        }
        lows.add(low);
        fractions.add((x - axis[low]) / (axis[low + 1] - axis[low]));
      }
    }
    // Each of the 2^n corners around the point, weighted by how near it is.
    final n = lows.length;
    var sum = 0.0;
    for (var corner = 0; corner < (1 << n); corner++) {
      var weight = 1.0;
      final at = <int>[];
      for (var i = 0; i < n; i++) {
        final upper = (corner >> i) & 1 == 1;
        weight *= upper ? fractions[i] : 1 - fractions[i];
        at.add(lows[i] + (upper && fractions[i] > 0 ? 1 : 0));
      }
      if (weight == 0) continue;
      sum += weight * table.rowAt(at).outputs[column];
    }
    return CalculatedValue(_round(sum, line.step), outsideTable: outside);
  }

  /// [value] rounded to a multiple of [step], without floating point noise
  /// (`0.1 * 369` is not `36.9`).
  static double _round(double value, double step) {
    final rounded = (value / step).roundToDouble() * step;
    return double.parse(rounded.toStringAsFixed(10));
  }
}
