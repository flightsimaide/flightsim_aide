import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/flight_sim/dataref.dart';
import '../../models/flight_sim/item_condition.dart';
import 'numeric_equality.dart';

/// The result of evaluating a condition.
enum Tri {
  /// The condition holds.
  met,

  /// The condition does not hold.
  notMet,

  /// A value the condition needs is missing, so nothing can be said
  /// (`GRAMMAR.md` N4, decision D-63).
  unknown,
}

/// Where the evaluator reads dataref values from.
abstract interface class ValueLookup {
  /// The current number of [dataref], or null when the app has no value.
  double? valueOf(Dataref dataref);
}

/// A [ValueLookup] over a map keyed by wire name.
class MapValues implements ValueLookup {
  /// Creates a lookup; a name that is absent or null has no value.
  const MapValues(this.values);

  /// Numbers by wire name (`name` or `name[n]`).
  final Map<String, double?> values;

  @override
  double? valueOf(Dataref dataref) => values[dataref.wireName];
}

enum _Cross { none, init, trig }

/// The memory one condition needs between evaluations: the baseline of each
/// change operator and the state of each crossing (`GRAMMAR.md` O5, O6).
///
/// One [ConditionState] belongs to one condition of one checklist run. It
/// starts empty; the first evaluation is the activation moment that takes the
/// baselines. Create a new one to reset. Keys are the position of the atom in
/// the tree, so the same tree must be evaluated each time.
class ConditionState {
  /// Creates an empty state.
  ConditionState();

  final Map<int, double?> _baselines = {};
  final Map<int, _Cross> _crossings = {};
}

/// Evaluates conditions. Pure apart from the [ConditionState] it is given.
class ConditionEvaluator {
  /// Creates an evaluator.
  const ConditionEvaluator();

  /// Evaluates [condition] against [values], reading and updating [state].
  ///
  /// Every atom is evaluated at every call so the memory of the change and
  /// crossing atoms advances (`GRAMMAR.md` O9, app rule). A value that is
  /// missing makes the whole condition [Tri.unknown], even if another part
  /// would decide (N4): the condition is never partly evaluated.
  Tri evaluate(
    ItemCondition condition,
    ValueLookup values,
    ConditionState state,
  ) {
    final counter = _Counter();
    return _node(condition, values, state, counter);
  }

  Tri _node(
    ItemCondition c,
    ValueLookup values,
    ConditionState state,
    _Counter counter,
  ) {
    switch (c) {
      case AndCondition(:final parts):
        return _combine(parts, values, state, counter, all: true);
      case OrCondition(:final parts):
        return _combine(parts, values, state, counter, all: false);
      case CompareCondition(:final left, :final op, :final right):
        counter.next();
        final a = evaluateExpr(left, values);
        final b = evaluateExpr(right, values);
        if (a == null || b == null) return Tri.unknown;
        return _tri(switch (op) {
          CompareOp.equal => numbersEqual(a, b),
          CompareOp.notEqual => !numbersEqual(a, b),
          CompareOp.less => a < b,
          CompareOp.greater => a > b,
          CompareOp.lessOrEqual => a <= b,
          CompareOp.greaterOrEqual => a >= b,
        });
      case RangeCondition(:final left, :final low, :final high):
        counter.next();
        final x = evaluateExpr(left, values);
        final lo = evaluateExpr(low, values);
        final hi = evaluateExpr(high, values);
        if (x == null || lo == null || hi == null) return Tri.unknown;
        return _tri(lo <= x && x <= hi);
      case CrossingCondition(:final left, :final from, :final to):
        final key = counter.next();
        final x = evaluateExpr(left, values);
        final a = evaluateExpr(from, values);
        final b = evaluateExpr(to, values);
        if (x == null || a == null || b == null) return Tri.unknown;
        return _tri(_crossing(state, key, x, a, b));
      case ChangeCondition(:final left, :final op, :final amount):
        final key = counter.next();
        final x = evaluateExpr(left, values);
        final n = evaluateExpr(amount, values);
        // The baseline is the value at the first evaluation. With no value
        // then there is no baseline, for good (O6).
        if (!state._baselines.containsKey(key)) state._baselines[key] = x;
        if (x == null || n == null) return Tri.unknown;
        final base = state._baselines[key];
        if (base == null) return Tri.notMet;
        return _tri(switch (op) {
          ChangeOp.rise => x - base > n,
          ChangeOp.fall => base - x > n,
          ChangeOp.either => (x - base).abs() > n,
        });
    }
  }

  Tri _combine(
    List<ItemCondition> parts,
    ValueLookup values,
    ConditionState state,
    _Counter counter, {
    required bool all,
  }) {
    // Evaluate every part (no short circuit) so the memory advances.
    final results = [for (final p in parts) _node(p, values, state, counter)];
    if (results.contains(Tri.unknown)) return Tri.unknown;
    final met = all
        ? results.every((r) => r == Tri.met)
        : results.any((r) => r == Tri.met);
    return _tri(met);
  }

  /// The crossing state machine of the plugin (`checkTrig`, O5).
  bool _crossing(ConditionState state, int key, double x, double a, double b) {
    var s = state._crossings[key] ?? _Cross.none;
    if (a < b) {
      switch (s) {
        case _Cross.none || _Cross.trig:
          if (x <= a) s = _Cross.init;
        case _Cross.init:
          if (x >= b) s = _Cross.trig;
      }
    } else {
      switch (s) {
        case _Cross.none || _Cross.trig:
          if (x >= a) s = _Cross.init;
        case _Cross.init:
          if (x <= b) s = _Cross.trig;
      }
    }
    state._crossings[key] = s;
    return s == _Cross.trig;
  }

  /// The number an expression stands for, or null when a dataref it reads has
  /// no value.
  double? evaluateExpr(ValueExpr e, ValueLookup values) {
    switch (e) {
      case NumberExpr(:final value):
        return value;
      case DatarefExpr(:final dataref):
        return values.valueOf(dataref);
      case NegateExpr(:final operand):
        final v = evaluateExpr(operand, values);
        return v == null ? null : -v;
      case BinaryExpr(:final op, :final left, :final right):
        final a = evaluateExpr(left, values);
        final b = evaluateExpr(right, values);
        if (a == null || b == null) return null;
        return switch (op) {
          ArithmeticOp.add => a + b,
          ArithmeticOp.subtract => a - b,
          ArithmeticOp.multiply => a * b,
          ArithmeticOp.divide => a / b,
          ArithmeticOp.power => math.pow(a, b).toDouble(),
        };
      case CastExpr(:final type, :final operand):
        final v = evaluateExpr(operand, values);
        if (v == null) return null;
        return switch (type) {
          CastType.integer => v.isFinite ? v.truncateToDouble() : v,
          CastType.single => (Float32List(1)..[0] = v)[0],
          CastType.double => v,
        };
      case CallExpr(:final function, :final args):
        final v = [for (final a in args) evaluateExpr(a, values)];
        if (v.contains(null)) return null;
        return switch (function) {
          ConditionFunction.round =>
            v[0]!.isFinite ? v[0]!.roundToDouble() : v[0],
          ConditionFunction.step => v[0]! >= 0 ? 1.0 : 0.0,
          ConditionFunction.closerThan =>
            (v[0]! - v[1]!).abs() < v[2]! ? 1.0 : 0.0,
        };
    }
  }

  Tri _tri(bool met) => met ? Tri.met : Tri.notMet;
}

class _Counter {
  int _n = 0;
  int next() => _n++;
}
