import 'package:equatable/equatable.dart';

import 'dataref.dart';

/// A number-valued expression: the left side of a comparison and everything
/// to its right (`GRAMMAR.md` sections 8.3 and 8.4).
sealed class ValueExpr extends Equatable {
  /// Creates the node.
  const ValueExpr();

  /// The datarefs this expression reads, in order of appearance.
  Iterable<Dataref> get signals;
}

/// A literal number.
final class NumberExpr extends ValueExpr {
  /// Creates the node.
  const NumberExpr(this.value);

  /// The value.
  final double value;

  @override
  Iterable<Dataref> get signals => const [];

  @override
  List<Object?> get props => [value];
}

/// The current value of a dataref: the name before the colon, or `{name}`.
final class DatarefExpr extends ValueExpr {
  /// Creates the node.
  const DatarefExpr(this.dataref);

  /// The dataref.
  final Dataref dataref;

  @override
  Iterable<Dataref> get signals => [dataref];

  @override
  List<Object?> get props => [dataref];
}

/// Unary minus.
final class NegateExpr extends ValueExpr {
  /// Creates the node.
  const NegateExpr(this.operand);

  /// The operand.
  final ValueExpr operand;

  @override
  Iterable<Dataref> get signals => operand.signals;

  @override
  List<Object?> get props => [operand];
}

/// The arithmetic operators of the right side.
enum ArithmeticOp {
  /// `+`.
  add,

  /// `-`.
  subtract,

  /// `*`.
  multiply,

  /// `/`.
  divide,

  /// `**`.
  power,
}

/// `left op right`.
final class BinaryExpr extends ValueExpr {
  /// Creates the node.
  const BinaryExpr(this.op, this.left, this.right);

  /// The op.
  final ArithmeticOp op;

  /// The left.
  final ValueExpr left;

  /// The right.
  final ValueExpr right;

  @override
  Iterable<Dataref> get signals => [...left.signals, ...right.signals];

  @override
  List<Object?> get props => [op, left, right];
}

/// The casts `(int)`, `(float)` and `(double)`.
enum CastType {
  /// `(int)`: truncates toward zero.
  integer,

  /// `(float)`: rounds to single precision.
  single,

  /// `(double)`: no change.
  double,
}

/// `(type) operand`.
final class CastExpr extends ValueExpr {
  /// Creates the node.
  const CastExpr(this.type, this.operand);

  /// The type.
  final CastType type;

  /// The operand.
  final ValueExpr operand;

  @override
  Iterable<Dataref> get signals => operand.signals;

  @override
  List<Object?> get props => [type, operand];
}

/// The functions the grammar knows.
enum ConditionFunction {
  /// `round(x)`: the nearest integer.
  round,

  /// `step(x)`: 1 when x >= 0, else 0.
  step,

  /// `closer_than(a, b, eps)`: 1 when abs(a - b) < eps, else 0.
  closerThan,
}

/// `name(args)`.
final class CallExpr extends ValueExpr {
  /// Creates the node.
  const CallExpr(this.function, this.args);

  /// The function.
  final ConditionFunction function;

  /// The args.
  final List<ValueExpr> args;

  @override
  Iterable<Dataref> get signals => [for (final a in args) ...a.signals];

  @override
  List<Object?> get props => [function, args];
}

/// A condition on an item, a checklist's `sw_show` or a `sw_continue` link:
/// a tree of comparisons joined by and/or. There is no logical not (X4).
sealed class ItemCondition extends Equatable {
  /// Creates the node.
  const ItemCondition();

  /// Every dataref the condition needs, each once, in order of appearance.
  List<Dataref> get signals {
    final seen = <Dataref>{};
    return [
      for (final d in allSignals)
        if (seen.add(d)) d,
    ];
  }

  /// Every dataref read, with repeats, in order of appearance.
  Iterable<Dataref> get allSignals;

  /// Whether the condition remembers something between evaluations: a change
  /// since a baseline, or a crossing. Such a condition cannot be judged from
  /// one value alone.
  bool get needsMemory => switch (this) {
    CrossingCondition() || ChangeCondition() => true,
    AndCondition(:final parts) ||
    OrCondition(:final parts) => parts.any((p) => p.needsMemory),
    CompareCondition() || RangeCondition() => false,
  };
}

/// The operators that compare two numbers.
enum CompareOp {
  /// `=` or `==` or no operator (within 1e-6).
  equal,

  /// `!` or `!=`.
  notEqual,

  /// `<`.
  less,

  /// `>`.
  greater,

  /// `<=`.
  lessOrEqual,

  /// `>=`.
  greaterOrEqual,
}

/// `left OP right` (also the plain `name:value`, which is equal).
final class CompareCondition extends ItemCondition {
  /// Creates the node.
  const CompareCondition(this.left, this.op, this.right);

  /// The left.
  final ValueExpr left;

  /// The op.
  final CompareOp op;

  /// The right.
  final ValueExpr right;

  @override
  Iterable<Dataref> get allSignals => [...left.signals, ...right.signals];

  @override
  List<Object?> get props => [left, op, right];
}

/// `left:low|high`: low <= left <= high, both ends included.
final class RangeCondition extends ItemCondition {
  /// Creates the node.
  const RangeCondition(this.left, this.low, this.high);

  /// The left.
  final ValueExpr left;

  /// The low.
  final ValueExpr low;

  /// The high.
  final ValueExpr high;

  @override
  Iterable<Dataref> get allSignals => [
    ...left.signals,
    ...low.signals,
    ...high.signals,
  ];

  @override
  List<Object?> get props => [left, low, high];
}

/// `left:from:to`: a crossing from beyond `from` to beyond `to` (O5). Needs
/// memory.
final class CrossingCondition extends ItemCondition {
  /// Creates the node.
  const CrossingCondition(this.left, this.from, this.to);

  /// The left.
  final ValueExpr left;

  /// The from.
  final ValueExpr from;

  /// The to.
  final ValueExpr to;

  @override
  Iterable<Dataref> get allSignals => [
    ...left.signals,
    ...from.signals,
    ...to.signals,
  ];

  @override
  List<Object?> get props => [left, from, to];
}

/// The change operators.
enum ChangeOp {
  /// `+>`: grew by more than the amount.
  rise,

  /// `-<`: shrank by more than the amount.
  fall,

  /// `><`: moved either way by more than the amount.
  either,
}

/// `left:+>n`, `-<n`, `><n`: change since the baseline (O6). Needs memory.
final class ChangeCondition extends ItemCondition {
  /// Creates the node.
  const ChangeCondition(this.left, this.op, this.amount);

  /// The left.
  final ValueExpr left;

  /// The op.
  final ChangeOp op;

  /// The amount.
  final ValueExpr amount;

  @override
  Iterable<Dataref> get allSignals => [...left.signals, ...amount.signals];

  @override
  List<Object?> get props => [left, op, amount];
}

/// All parts hold (`&&`).
final class AndCondition extends ItemCondition {
  /// Creates the node.
  AndCondition(List<ItemCondition> parts)
    : assert(parts.length >= 2),
      parts = List.unmodifiable(parts);

  /// The parts.
  final List<ItemCondition> parts;

  @override
  Iterable<Dataref> get allSignals => [for (final p in parts) ...p.allSignals];

  @override
  List<Object?> get props => [parts];
}

/// At least one part holds (`||`).
final class OrCondition extends ItemCondition {
  /// Creates the node.
  OrCondition(List<ItemCondition> parts)
    : assert(parts.length >= 2),
      parts = List.unmodifiable(parts);

  /// The parts.
  final List<ItemCondition> parts;

  @override
  Iterable<Dataref> get allSignals => [for (final p in parts) ...p.allSignals];

  @override
  List<Object?> get props => [parts];
}
