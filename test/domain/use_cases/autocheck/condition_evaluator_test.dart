import 'package:flightsim_aide/domain/models/flight_sim/dataref.dart';
import 'package:flightsim_aide/domain/models/flight_sim/item_condition.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/condition_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

const _eval = ConditionEvaluator();

DatarefExpr _d(String name) => DatarefExpr(Dataref(name));
NumberExpr _n(double v) => NumberExpr(v);

Tri _once(ItemCondition c, Map<String, double?> values) =>
    _eval.evaluate(c, MapValues(values), ConditionState());

CompareCondition _cmp(String name, CompareOp op, double v) =>
    CompareCondition(_d(name), op, _n(v));

void main() {
  group('plain comparisons', () {
    final table = <(CompareOp, double, double, Tri)>[
      (CompareOp.equal, 5, 5, Tri.met),
      (CompareOp.equal, 5.0000005, 5, Tri.met),
      (CompareOp.equal, 5.000002, 5, Tri.notMet),
      (CompareOp.notEqual, 5, 5, Tri.notMet),
      (CompareOp.notEqual, 6, 5, Tri.met),
      (CompareOp.less, 4, 5, Tri.met),
      (CompareOp.less, 5, 5, Tri.notMet),
      (CompareOp.greater, 6, 5, Tri.met),
      (CompareOp.greater, 5, 5, Tri.notMet),
      (CompareOp.lessOrEqual, 5, 5, Tri.met),
      (CompareOp.lessOrEqual, 5.0000001, 5, Tri.notMet), // no tolerance (O3)
      (CompareOp.greaterOrEqual, 5, 5, Tri.met),
      (CompareOp.greaterOrEqual, 4.9999999, 5, Tri.notMet),
    ];
    for (final (op, x, v, expected) in table) {
      test('$x ${op.name} $v is ${expected.name}', () {
        expect(_once(_cmp('a', op, v), {'a': x}), expected);
      });
    }

    test('a missing value is unknown, never zero', () {
      expect(_once(_cmp('a', CompareOp.equal, 0), {}), Tri.unknown);
      expect(_once(_cmp('a', CompareOp.equal, 0), {'a': null}), Tri.unknown);
    });

    test('a missing right-side dataref is unknown', () {
      final c = CompareCondition(_d('a'), CompareOp.greater, _d('b'));
      expect(_once(c, {'a': 1}), Tri.unknown);
      expect(_once(c, {'a': 2, 'b': 1}), Tri.met);
    });
  });

  group('range', () {
    final range = RangeCondition(_d('a'), _n(10), _n(20));
    for (final (x, expected) in [
      (10.0, Tri.met),
      (15.0, Tri.met),
      (20.0, Tri.met),
      (9.9999999, Tri.notMet),
      (20.0000001, Tri.notMet),
    ]) {
      test('$x is ${expected.name}', () {
        expect(_once(range, {'a': x}), expected);
      });
    }

    test('low above high is never met', () {
      expect(
        _once(RangeCondition(_d('a'), _n(20), _n(10)), {'a': 15}),
        Tri.notMet,
      );
    });
  });

  group('right side', () {
    double? eval(ValueExpr e, [Map<String, double?> v = const {}]) =>
        _eval.evaluateExpr(e, MapValues(v));

    test('arithmetic and precedence', () {
      expect(
        eval(
          BinaryExpr(
            ArithmeticOp.add,
            _n(1),
            BinaryExpr(ArithmeticOp.multiply, _n(2), _n(3)),
          ),
        ),
        7,
      );
      expect(eval(BinaryExpr(ArithmeticOp.divide, _n(7), _n(2))), 3.5);
      expect(eval(BinaryExpr(ArithmeticOp.power, _n(2), _n(3))), 8);
      expect(eval(NegateExpr(_n(5))), -5);
    });

    test('casts', () {
      expect(eval(CastExpr(CastType.integer, _n(10.9))), 10);
      expect(eval(CastExpr(CastType.integer, _n(-10.9))), -10);
      expect(eval(CastExpr(CastType.single, _n(0.1))), isNot(0.1));
      expect(eval(CastExpr(CastType.single, _n(0.1)))!, closeTo(0.1, 1e-8));
      expect(eval(CastExpr(CastType.double, _n(0.1))), 0.1);
    });

    test('functions', () {
      expect(eval(CallExpr(ConditionFunction.round, [_n(2.6)])), 3);
      expect(eval(CallExpr(ConditionFunction.round, [_n(-2.5)])), -3);
      expect(eval(CallExpr(ConditionFunction.step, [_n(-1)])), 0);
      expect(eval(CallExpr(ConditionFunction.step, [_n(0)])), 1);
      expect(
        eval(CallExpr(ConditionFunction.closerThan, [_n(10), _n(11), _n(2)])),
        1,
      );
      expect(
        eval(CallExpr(ConditionFunction.closerThan, [_n(10), _n(12), _n(2)])),
        0,
      );
    });

    test('a missing dataref makes the expression null', () {
      expect(eval(BinaryExpr(ArithmeticOp.add, _n(1), _d('x'))), isNull);
      expect(eval(BinaryExpr(ArithmeticOp.add, _n(1), _d('x')), {'x': 2}), 3);
    });
  });

  group('and, or and unknown', () {
    final a = _cmp('a', CompareOp.equal, 1);
    final b = _cmp('b', CompareOp.equal, 1);
    final c = _cmp('c', CompareOp.equal, 1);

    test('and needs every part', () {
      expect(_once(AndCondition([a, b]), {'a': 1, 'b': 1}), Tri.met);
      expect(_once(AndCondition([a, b]), {'a': 1, 'b': 0}), Tri.notMet);
    });

    test('or needs one part', () {
      expect(_once(OrCondition([a, b]), {'a': 0, 'b': 1}), Tri.met);
      expect(_once(OrCondition([a, b]), {'a': 0, 'b': 0}), Tri.notMet);
    });

    test('one missing value makes the whole condition unknown, even if the '
        'other part decides (D-63)', () {
      expect(_once(OrCondition([a, b]), {'a': 1}), Tri.unknown);
      expect(_once(AndCondition([a, b]), {'a': 0}), Tri.unknown);
    });

    test('precedence is the tree: a || (b && c)', () {
      final tree = OrCondition([
        a,
        AndCondition([b, c]),
      ]);
      expect(_once(tree, {'a': 1, 'b': 0, 'c': 0}), Tri.met);
      expect(_once(tree, {'a': 0, 'b': 1, 'c': 1}), Tri.met);
      expect(_once(tree, {'a': 0, 'b': 1, 'c': 0}), Tri.notMet);
    });
  });

  group('change since activation (O6)', () {
    ChangeCondition change(ChangeOp op, [double n = 5]) =>
        ChangeCondition(_d('a'), op, _n(n));
    Tri step(ChangeCondition c, ConditionState s, double? v) =>
        _eval.evaluate(c, MapValues({'a': v}), s);

    test('the first evaluation is the baseline and is not met', () {
      final s = ConditionState();
      expect(step(change(ChangeOp.rise), s, 100), Tri.notMet);
    });

    test('rise is strict: exactly the amount is not met', () {
      final s = ConditionState();
      final c = change(ChangeOp.rise);
      step(c, s, 10);
      expect(step(c, s, 15), Tri.notMet);
      expect(step(c, s, 15.1), Tri.met);
    });

    test('fall and either', () {
      final f = ConditionState();
      step(change(ChangeOp.fall), f, 10);
      expect(step(change(ChangeOp.fall), f, 4), Tri.met);
      final e = ConditionState();
      step(change(ChangeOp.either), e, 10);
      expect(step(change(ChangeOp.either), e, 16), Tri.met);
      final e2 = ConditionState();
      step(change(ChangeOp.either), e2, 10);
      expect(step(change(ChangeOp.either), e2, 4), Tri.met);
    });

    test('the condition is not latched: back at the start it is not met', () {
      final s = ConditionState();
      final c = change(ChangeOp.rise);
      step(c, s, 10);
      expect(step(c, s, 16), Tri.met);
      expect(step(c, s, 10), Tri.notMet);
    });

    test('no value at the first evaluation means no baseline for good', () {
      final s = ConditionState();
      final c = change(ChangeOp.rise);
      expect(step(c, s, null), Tri.unknown);
      expect(step(c, s, 100), Tri.notMet);
    });

    test('a value that goes missing later is unknown', () {
      final s = ConditionState();
      final c = change(ChangeOp.rise);
      step(c, s, 10);
      expect(step(c, s, null), Tri.unknown);
    });

    test('a new state starts a new baseline', () {
      final c = change(ChangeOp.rise);
      final s1 = ConditionState();
      step(c, s1, 10);
      expect(step(c, s1, 20), Tri.met);
      expect(step(c, ConditionState(), 20), Tri.notMet);
    });
  });

  group('crossing a:b (O5)', () {
    CrossingCondition crossing(double a, double b) =>
        CrossingCondition(_d('x'), _n(a), _n(b));
    List<Tri> run(CrossingCondition c, List<double?> xs) {
      final s = ConditionState();
      return [
        for (final x in xs) _eval.evaluate(c, MapValues({'x': x}), s),
      ];
    }

    test('rising 10:20 needs to start at or below 10', () {
      expect(run(crossing(10, 20), [5, 15, 25]), [
        Tri.notMet,
        Tri.notMet,
        Tri.met,
      ]);
    });

    test('starting between the limits never arms', () {
      expect(run(crossing(10, 20), [15, 25]), [Tri.notMet, Tri.notMet]);
    });

    test('a dip to the first limit arms it', () {
      expect(run(crossing(10, 20), [15, 10, 25]), [
        Tri.notMet,
        Tri.notMet,
        Tri.met,
      ]);
    });

    test('falling 260:250', () {
      expect(run(crossing(260, 250), [270, 255, 245]), [
        Tri.notMet,
        Tri.notMet,
        Tri.met,
      ]);
    });

    test('stays met until it goes back to the first limit', () {
      expect(run(crossing(10, 20), [5, 25, 15, 25, 10, 15]), [
        Tri.notMet,
        Tri.met,
        Tri.met,
        Tri.met,
        Tri.notMet,
        Tri.notMet,
      ]);
    });

    test('no value is unknown and keeps the state', () {
      expect(run(crossing(10, 20), [5, null, 25]), [
        Tri.notMet,
        Tri.unknown,
        Tri.met,
      ]);
    });
  });

  test('every atom is evaluated each time, so a later atom keeps its memory', () {
    // (a == 1) || (b changes by more than 5): b's baseline starts at the first
    // call although the first part already decides.
    final c = OrCondition([
      _cmp('a', CompareOp.equal, 1),
      ChangeCondition(_d('b'), ChangeOp.rise, _n(5)),
    ]);
    final s = ConditionState();
    expect(_eval.evaluate(c, const MapValues({'a': 1, 'b': 10}), s), Tri.met);
    expect(_eval.evaluate(c, const MapValues({'a': 0, 'b': 20}), s), Tri.met);
  });
}
