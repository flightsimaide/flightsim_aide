import 'dart:math';

import 'package:flightsim_aide/data/parsers/condition_expression_parser.dart';
import 'package:flightsim_aide/domain/models/flight_sim/dataref.dart';
import 'package:flightsim_aide/domain/models/flight_sim/item_condition.dart';
import 'package:flutter_test/flutter_test.dart';

const _parser = ConditionExpressionParser();

DatarefExpr _d(String name, [int? index]) => DatarefExpr(Dataref(name, index));
NumberExpr _n(double v) => NumberExpr(v);

ItemCondition _ok(String text) {
  final r = _parser.parse(text);
  expect(r.reason, isNull, reason: text);
  return r.condition!;
}

String _reason(String text) {
  final r = _parser.parse(text);
  expect(r.condition, isNull, reason: text);
  return r.reason!;
}

void main() {
  group('plain comparisons', () {
    final table = <String, ItemCondition>{
      'a/b:5': CompareCondition(_d('a/b'), CompareOp.equal, _n(5)),
      'a/b:=5': CompareCondition(_d('a/b'), CompareOp.equal, _n(5)),
      'a/b:==5': CompareCondition(_d('a/b'), CompareOp.equal, _n(5)),
      'a/b:!5': CompareCondition(_d('a/b'), CompareOp.notEqual, _n(5)),
      'a/b:!=5': CompareCondition(_d('a/b'), CompareOp.notEqual, _n(5)),
      'a/b:<5': CompareCondition(_d('a/b'), CompareOp.less, _n(5)),
      'a/b:>5': CompareCondition(_d('a/b'), CompareOp.greater, _n(5)),
      'a/b:<=5': CompareCondition(_d('a/b'), CompareOp.lessOrEqual, _n(5)),
      'a/b:>=5': CompareCondition(_d('a/b'), CompareOp.greaterOrEqual, _n(5)),
      'a/b:-5': CompareCondition(_d('a/b'), CompareOp.equal, _n(-5)),
      'a/b:+5': CompareCondition(_d('a/b'), CompareOp.equal, _n(5)),
      'a/b:>.5': CompareCondition(_d('a/b'), CompareOp.greater, _n(0.5)),
      'a/b:1e2': CompareCondition(_d('a/b'), CompareOp.equal, _n(100)),
      'a/b:<1.0e-3': CompareCondition(_d('a/b'), CompareOp.less, _n(0.001)),
      ' a/b : > 5 ': CompareCondition(_d('a/b'), CompareOp.greater, _n(5)),
    };
    table.forEach((text, expected) {
      test(text, () => expect(_ok(text), expected));
    });
  });

  group('range, crossing and change', () {
    test('range a|b', () {
      expect(_ok('x:10|20'), RangeCondition(_d('x'), _n(10), _n(20)));
      expect(_ok('x:10 | 20'), RangeCondition(_d('x'), _n(10), _n(20)));
    });

    test('crossing a:b', () {
      expect(_ok('x:10:20'), CrossingCondition(_d('x'), _n(10), _n(20)));
      expect(_ok('x:260:250'), CrossingCondition(_d('x'), _n(260), _n(250)));
    });

    test('change operators', () {
      expect(_ok('x:+>5'), ChangeCondition(_d('x'), ChangeOp.rise, _n(5)));
      expect(_ok('x:-<5'), ChangeCondition(_d('x'), ChangeOp.fall, _n(5)));
      expect(_ok('x:><0'), ChangeCondition(_d('x'), ChangeOp.either, _n(0)));
    });
  });

  group('the right side', () {
    test('another dataref', () {
      expect(
        _ok('x:>{y}'),
        CompareCondition(_d('x'), CompareOp.greater, _d('y')),
      );
      expect(
        _ok('x:{y[2]}'),
        CompareCondition(_d('x'), CompareOp.equal, _d('y', 2)),
      );
    });

    test('arithmetic precedence', () {
      expect(
        _ok('x:1+2*3'),
        CompareCondition(
          _d('x'),
          CompareOp.equal,
          BinaryExpr(
            ArithmeticOp.add,
            _n(1),
            BinaryExpr(ArithmeticOp.multiply, _n(2), _n(3)),
          ),
        ),
      );
      expect(
        _ok('x:(1+2)*3'),
        CompareCondition(
          _d('x'),
          CompareOp.equal,
          BinaryExpr(
            ArithmeticOp.multiply,
            BinaryExpr(ArithmeticOp.add, _n(1), _n(2)),
            _n(3),
          ),
        ),
      );
      expect(
        _ok('x:2**3'),
        CompareCondition(
          _d('x'),
          CompareOp.equal,
          BinaryExpr(ArithmeticOp.power, _n(2), _n(3)),
        ),
      );
      expect(
        _ok('x:-(2+3)'),
        CompareCondition(
          _d('x'),
          CompareOp.equal,
          NegateExpr(BinaryExpr(ArithmeticOp.add, _n(2), _n(3))),
        ),
      );
    });

    test('casts and functions', () {
      expect(
        _ok('x:(int)10.9'),
        CompareCondition(
          _d('x'),
          CompareOp.equal,
          CastExpr(CastType.integer, _n(10.9)),
        ),
      );
      expect(
        _ok('x:round(2.6)'),
        CompareCondition(
          _d('x'),
          CompareOp.equal,
          CallExpr(ConditionFunction.round, [_n(2.6)]),
        ),
      );
      expect(
        _ok('1:closer_than({a},{b},2)'),
        CompareCondition(
          _n(1),
          CompareOp.equal,
          CallExpr(ConditionFunction.closerThan, [_d('a'), _d('b'), _n(2)]),
        ),
      );
    });
  });

  group('names', () {
    test('an array element', () {
      expect(
        _ok('sim/a/b[3]:1'),
        CompareCondition(_d('sim/a/b', 3), CompareOp.equal, _n(1)),
      );
    });

    test('blanks inside the name are kept, around it trimmed', () {
      expect(
        _ok('  my data ref  :1'),
        CompareCondition(_d('my data ref'), CompareOp.equal, _n(1)),
      );
    });
  });

  group('logic', () {
    final a = CompareCondition(_d('a'), CompareOp.equal, _n(1));
    final b = CompareCondition(_d('b'), CompareOp.equal, _n(2));
    final c = CompareCondition(_d('c'), CompareOp.equal, _n(3));

    test('and, or', () {
      expect(_ok('a:1&&b:2'), AndCondition([a, b]));
      expect(_ok('a:1||b:2'), OrCondition([a, b]));
      expect(_ok('(a:1) && (b:2)'), AndCondition([a, b]));
    });

    test('and binds tighter than or', () {
      expect(
        _ok('a:1||b:2&&c:3'),
        OrCondition([
          a,
          AndCondition([b, c]),
        ]),
      );
      expect(
        _ok('a:1&&b:2||c:3'),
        OrCondition([
          AndCondition([a, b]),
          c,
        ]),
      );
    });

    test('parentheses override it and nest', () {
      expect(
        _ok('(a:1||b:2)&&c:3'),
        AndCondition([
          OrCondition([a, b]),
          c,
        ]),
      );
      expect(
        _ok('((a:1)||(b:2))&&(c:3)'),
        AndCondition([
          OrCondition([a, b]),
          c,
        ]),
      );
    });

    test('three parts stay flat', () {
      expect(_ok('a:1&&b:2&&c:3'), AndCondition([a, b, c]));
    });

    test('the relational form :(a OP b)', () {
      expect(
        _ok(':({a}=={b})'),
        CompareCondition(_d('a'), CompareOp.equal, _d('b')),
      );
      expect(
        _ok(':({a}<{b})&&({a}>1)'),
        AndCondition([
          CompareCondition(_d('a'), CompareOp.less, _d('b')),
          CompareCondition(_d('a'), CompareOp.greater, _n(1)),
        ]),
      );
    });
  });

  group('array ranges name[a..b] (app extension, all elements)', () {
    CompareCondition el(
      int i, [
      CompareOp op = CompareOp.equal,
      double v = 0,
    ]) => CompareCondition(_d('a/b', i), op, _n(v));

    test('expands to all elements joined with and', () {
      expect(_ok('a/b[0..2]:0'), AndCondition([el(0), el(1), el(2)]));
    });

    test('one element range is the plain element', () {
      expect(_ok('a/b[3..3]:0'), el(3));
    });

    test('the operator applies to each element', () {
      expect(
        _ok('a/b[1..2]:>5'),
        AndCondition([
          el(1, CompareOp.greater, 5),
          el(2, CompareOp.greater, 5),
        ]),
      );
    });

    test('works inside a longer condition', () {
      expect(
        _ok('(a/b[0..1]:0)&&(c:1)'),
        AndCondition([
          AndCondition([el(0), el(1)]),
          CompareCondition(_d('c'), CompareOp.equal, _n(1)),
        ]),
      );
    });

    test('range and change forms expand per element', () {
      expect(
        _ok('a/b[0..1]:1|2'),
        AndCondition([
          RangeCondition(_d('a/b', 0), _n(1), _n(2)),
          RangeCondition(_d('a/b', 1), _n(1), _n(2)),
        ]),
      );
      expect(
        _ok('a/b[0..1]:+>1'),
        AndCondition([
          ChangeCondition(_d('a/b', 0), ChangeOp.rise, _n(1)),
          ChangeCondition(_d('a/b', 1), ChangeOp.rise, _n(1)),
        ]),
      );
    });

    test('signals list every element', () {
      expect(_ok('a/b[0..2]:0').signals.map((d) => d.wireName).toList(), [
        'a/b[0]',
        'a/b[1]',
        'a/b[2]',
      ]);
    });

    test('128 elements is allowed, 129 is not', () {
      expect(_ok('a/b[0..127]:0'), isA<AndCondition>());
      expect(
        _reason('a/b[0..128]:0'),
        'range "0..128" has more than 128 elements',
      );
    });

    test('a backwards or malformed range is an error', () {
      expect(_reason('a/b[2..0]:0'), 'range "2..0" is backwards');
      expect(_reason('a/b[0..]:0'), 'unexpected text "a/b[0..]"');
      expect(_reason('a/b[..2]:0'), 'unexpected text "a/b[..2]"');
      expect(_reason('a/b[x..2]:0'), 'unexpected text "a/b[x..2]"');
    });

    test('a range on the right side is not supported', () {
      expect(_reason('x:{a/b[0..2]}'), isNotEmpty);
    });
  });

  group('empty and malformed', () {
    test('empty or blank text is no condition and no error', () {
      for (final text in ['', '   ', '\t']) {
        final r = _parser.parse(text);
        expect(r.condition, isNull);
        expect(r.failed, isFalse);
      }
    });

    final table = <String, String>{
      '(a:1': 'unbalanced parentheses',
      'a:1)': 'unbalanced parentheses',
      '((a:1)': 'unbalanced parentheses',
      'a:>': 'missing value',
      'a:': 'missing value',
      '()': 'unexpected ")"',
      'a:1 foo': 'unexpected text "foo"',
      'a:~5': 'unexpected text "~5"',
      'a:frob(1)': 'unknown function "frob"',
      '(a:1)&&': 'missing condition after "&&"',
      'a:1||': 'missing condition after "||"',
      'a': 'missing ":" after the name',
      'a:round()': 'wrong number of arguments for "round"',
      'a:closer_than(1,2)': 'wrong number of arguments for "closer_than"',
      'a[x]:1': 'unexpected text "a[x]"',
      'a:{b': 'unexpected text "{b"',
    };
    table.forEach((text, reason) {
      test('"$text" gives "$reason"', () => expect(_reason(text), reason));
    });
  });

  group('rare forms', () {
    test('nested relational groups', () {
      final c = _ok(':(({a}=={b})&&({a}>1))');
      expect(c, isA<AndCondition>());
    });

    test('a relational group without an operator is an error', () {
      expect(_reason(':({a})'), 'unexpected text "{a}"');
    });

    test('relational text that is not a group is an error', () {
      expect(_reason(':x'), 'unexpected text "x"');
    });

    test('an atom with no name is an error', () {
      expect(_reason('a:1&&:5'), 'unexpected text ":5"');
    });

    test('a negative number with blanks before a power', () {
      expect(
        _ok('x:- 2 ** 2'),
        CompareCondition(
          _d('x'),
          CompareOp.equal,
          NegateExpr(BinaryExpr(ArithmeticOp.power, _n(2), _n(2))),
        ),
      );
    });

    test('float and double casts and a blank before a call', () {
      expect(
        _ok('x:(float)1.5'),
        CompareCondition(
          _d('x'),
          CompareOp.equal,
          CastExpr(CastType.single, _n(1.5)),
        ),
      );
      expect(
        _ok('x:(double)1.5'),
        CompareCondition(
          _d('x'),
          CompareOp.equal,
          CastExpr(CastType.double, _n(1.5)),
        ),
      );
      expect(
        _ok('x:round (2.6)'),
        CompareCondition(
          _d('x'),
          CompareOp.equal,
          CallExpr(ConditionFunction.round, [_n(2.6)]),
        ),
      );
    });

    test('a bad dataref in braces is an error', () {
      expect(_reason('x:{a[x]}'), 'unexpected text "{a[x]}"');
    });
  });

  test('200 random strings never throw and always end', () {
    final random = Random(42);
    const alphabet = 'ab/:|&()[]{}<>=!+-*.0123456789 ~,_rounstepclsx';
    for (var n = 0; n < 200; n++) {
      final text = String.fromCharCodes([
        for (var i = 0; i < random.nextInt(40); i++)
          alphabet.codeUnitAt(random.nextInt(alphabet.length)),
      ]);
      final r = _parser.parse(text);
      expect(
        r.condition != null || r.reason != null || text.trim().isEmpty,
        isTrue,
        reason: text,
      );
    }
  });

  test('deeply nested parentheses end', () {
    final open = '(' * 400;
    final close = ')' * 400;
    final r = _parser.parse('${open}a:1$close');
    expect(r.condition != null || r.reason != null, isTrue);
  });

  // AC-66
  group('quoted names (GRAMMAR.md N6)', () {
    test('a quoted name keeps its colons, commas and spaces', () {
      expect(
        _ok('"A:GENERAL ENG MASTER ALTERNATOR:1, bool":1'),
        CompareCondition(
          _d('A:GENERAL ENG MASTER ALTERNATOR:1, bool'),
          CompareOp.equal,
          _n(1),
        ),
      );
    });

    test('single and double quotes both work, the other kind is text', () {
      expect(
        _ok("'L:ELECTRICAL_Switch_BATTERY_Bus_1':1"),
        CompareCondition(
          _d('L:ELECTRICAL_Switch_BATTERY_Bus_1'),
          CompareOp.equal,
          _n(1),
        ),
      );
      expect(
        _ok('"L:it\'s":0'),
        CompareCondition(_d("L:it's"), CompareOp.equal, _n(0)),
      );
    });

    test('every operator form follows a quoted name', () {
      expect(
        _ok('"A:PLANE ALTITUDE, feet":>5000'),
        CompareCondition(
          _d('A:PLANE ALTITUDE, feet'),
          CompareOp.greater,
          _n(5000),
        ),
      );
      expect(_ok('"L:x":10|20'), RangeCondition(_d('L:x'), _n(10), _n(20)));
      expect(_ok('"L:x":10:20'), CrossingCondition(_d('L:x'), _n(10), _n(20)));
      expect(
        _ok('"L:x":+>5'),
        ChangeCondition(_d('L:x'), ChangeOp.rise, _n(5)),
      );
    });

    test('blanks around the quotes are skipped', () {
      expect(_ok(' "L:x" : 1 '), _ok('"L:x":1'));
    });

    test('quoted names join with && and || and sit in parentheses', () {
      expect(
        _ok('("L:a":1)&&("L:b, bool":0)||(plain/c:2)'),
        OrCondition([
          AndCondition([
            CompareCondition(_d('L:a'), CompareOp.equal, _n(1)),
            CompareCondition(_d('L:b, bool'), CompareOp.equal, _n(0)),
          ]),
          CompareCondition(_d('plain/c'), CompareOp.equal, _n(2)),
        ]),
      );
    });

    test('a quoted name on the right side, bare or in braces', () {
      final expected = CompareCondition(
        _d('x'),
        CompareOp.greater,
        _d('A:AMBIENT TEMPERATURE, celsius'),
      );
      expect(_ok('x:>"A:AMBIENT TEMPERATURE, celsius"'), expected);
      expect(_ok('x:>{"A:AMBIENT TEMPERATURE, celsius"}'), expected);
      expect(
        _ok("x:>{ 'L:y' }+1"),
        CompareCondition(
          _d('x'),
          CompareOp.greater,
          BinaryExpr(ArithmeticOp.add, _d('L:y'), _n(1)),
        ),
      );
    });

    test('a quoted name in the relational form', () {
      expect(
        _ok(':("L:a"=="L:b")'),
        CompareCondition(_d('L:a'), CompareOp.equal, _d('L:b')),
      );
    });

    test('unquoted names are read as before', () {
      expect(_ok("it's/odd:1"), isA<CompareCondition>());
    });

    test('bad quotes are named, never partly used', () {
      expect(_reason('"L:x:1'), 'unterminated quote');
      expect(_reason("'L:x:1"), 'unterminated quote');
      expect(_reason('"":1'), 'empty name in quotes');
      expect(_reason('" ":1'), 'empty name in quotes');
      expect(_reason('"L:x"'), 'missing ":" after the name');
      expect(_reason('"L:x"y:1'), 'missing ":" after the name');
      expect(_reason('"L:x[1]":1'), 'square brackets in a quoted name');
      expect(_reason('"L:x[1..2]":1'), 'square brackets in a quoted name');
      expect(_reason('x:>{"L:y"'), startsWith('unexpected text'));
    });

    test('parseValue reads a bare quoted name', () {
      final r = _parser.parseValue('"A:AMBIENT TEMPERATURE, celsius"');
      expect(r.failed, isFalse);
      expect(r.value, _d('A:AMBIENT TEMPERATURE, celsius'));
      expect(_parser.parseValue('"L:x" - 1').value, isA<BinaryExpr>());
      expect(_parser.parseValue('"L:x').failed, isTrue);
    });
  });
}
