import 'package:flightsim_aide/domain/use_cases/autocheck/numeric_equality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('numbersEqual (GRAMMAR O1: abs(a - b) < 1e-6)', () {
    final table = <(double, double, bool)>[
      (1, 1, true),
      (0.1 + 0.2, 0.3, true),
      (0.10000000149011612, 0.1, true), // a float 0.1 widened to a double
      (1.0000009, 1, true),
      (1.0000011, 1, false),
      (1, 1.0000009, true),
      (0, 0, true),
      (0, -0.0, true),
      (0, 1e-7, true),
      (0, 1e-6, false), // strictly below the tolerance
      (-5, -5.0000005, true),
      (100000, 100000.0000005, true),
      (1e12, 1e12 + 1, false),
      (double.infinity, double.infinity, true),
      (double.infinity, double.negativeInfinity, false),
      (double.nan, double.nan, false),
      (double.nan, 1, false),
    ];
    for (final (a, b, expected) in table) {
      test('$a and $b: $expected', () {
        expect(numbersEqual(a, b), expected);
        expect(numbersEqual(b, a), expected, reason: 'symmetric');
      });
    }
  });
}
