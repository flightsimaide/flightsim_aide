import 'package:flightsim_aide/domain/models/flight_sim/dataref.dart';
import 'package:flightsim_aide/domain/models/flight_sim/item_condition.dart';
import 'package:flutter_test/flutter_test.dart';

DatarefExpr _d(String name, [int? index]) => DatarefExpr(Dataref(name, index));

void main() {
  group('equality', () {
    test('the same tree is equal', () {
      expect(
        CompareCondition(_d('a'), CompareOp.equal, const NumberExpr(1)),
        CompareCondition(_d('a'), CompareOp.equal, const NumberExpr(1)),
      );
    });

    test('a different operator or operand is not', () {
      final base = CompareCondition(
        _d('a'),
        CompareOp.equal,
        const NumberExpr(1),
      );
      expect(
        base,
        isNot(CompareCondition(_d('a'), CompareOp.less, const NumberExpr(1))),
      );
      expect(
        base,
        isNot(CompareCondition(_d('a'), CompareOp.equal, const NumberExpr(2))),
      );
    });

    test('and and or keep their parts and are different kinds', () {
      final a = CompareCondition(_d('a'), CompareOp.equal, const NumberExpr(1));
      final b = CompareCondition(_d('b'), CompareOp.equal, const NumberExpr(1));
      expect(AndCondition([a, b]), AndCondition([a, b]));
      expect(AndCondition([a, b]), isNot(OrCondition([a, b])));
      expect(AndCondition([a, b]), isNot(AndCondition([b, a])));
    });
  });

  group('signals', () {
    test('a plain comparison needs its dataref', () {
      expect(
        CompareCondition(_d('a'), CompareOp.equal, const NumberExpr(1)).signals,
        [const Dataref('a')],
      );
    });

    test('a right-side dataref, a function and a cast count', () {
      final c = CompareCondition(
        _d('a'),
        CompareOp.greater,
        BinaryExpr(
          ArithmeticOp.add,
          CastExpr(CastType.integer, _d('b')),
          CallExpr(ConditionFunction.closerThan, [
            _d('c'),
            _d('d'),
            const NumberExpr(2),
          ]),
        ),
      );
      expect(c.signals.map((d) => d.wireName), ['a', 'b', 'c', 'd']);
    });

    test('duplicates are dropped and the order is first appearance', () {
      final c = OrCondition([
        CompareCondition(_d('b'), CompareOp.equal, const NumberExpr(1)),
        AndCondition([
          CompareCondition(_d('a'), CompareOp.equal, const NumberExpr(1)),
          RangeCondition(_d('b'), const NumberExpr(0), const NumberExpr(5)),
        ]),
      ]);
      expect(c.signals, [const Dataref('b'), const Dataref('a')]);
    });

    test('array elements are separate signals', () {
      final c = AndCondition([
        CompareCondition(_d('a', 0), CompareOp.equal, const NumberExpr(1)),
        CompareCondition(_d('a', 1), CompareOp.equal, const NumberExpr(1)),
      ]);
      expect(c.signals, [const Dataref('a', 0), const Dataref('a', 1)]);
    });

    test('change and crossing need their left side', () {
      expect(
        ChangeCondition(_d('a'), ChangeOp.rise, const NumberExpr(5)).signals,
        [const Dataref('a')],
      );
      expect(CrossingCondition(_d('a'), const NumberExpr(1), _d('b')).signals, [
        const Dataref('a'),
        const Dataref('b'),
      ]);
    });
  });
}
