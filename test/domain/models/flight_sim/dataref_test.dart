import 'package:flightsim_aide/domain/models/flight_sim/dataref.dart';
import 'package:flightsim_aide/domain/models/flight_sim/dataref_value.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Dataref', () {
    test('a scalar has the plain wire name', () {
      expect(const Dataref('sim/a/b').wireName, 'sim/a/b');
      expect(const Dataref('sim/a/b').index, isNull);
    });

    test('name[3] round-trips', () {
      final d = Dataref.tryParse('sim/a/b[3]');
      expect(d, const Dataref('sim/a/b', 3));
      expect(d!.wireName, 'sim/a/b[3]');
      expect(Dataref.tryParse(d.wireName), d);
    });

    test('equality is by name and index', () {
      expect(const Dataref('a', 1), const Dataref('a', 1));
      expect(const Dataref('a', 1), isNot(const Dataref('a', 2)));
      expect(const Dataref('a'), isNot(const Dataref('a', 0)));
    });

    test('blanks around the text are trimmed', () {
      expect(Dataref.tryParse('  a/b  '), const Dataref('a/b'));
    });

    test('a malformed bracket form is refused', () {
      for (final bad in [
        '',
        'a[',
        'a]',
        'a[]',
        'a[x]',
        'a[-1]',
        'a[1]x',
        'a[1][2]',
        '[1]',
        'a[1234567]',
      ]) {
        expect(Dataref.tryParse(bad), isNull, reason: bad);
      }
    });
  });

  group('DatarefValue', () {
    final at = DateTime.utc(2026, 11, 4);

    test('a number is known', () {
      final v = DatarefValue(1.5, at);
      expect(v.isKnown, isTrue);
      expect(v.number, 1.5);
      expect(v.sampledAt, at);
    });

    test('unknown has no number, not zero', () {
      const v = DatarefValue.unknown();
      expect(v.isKnown, isFalse);
      expect(v.number, isNull);
    });

    test('equality', () {
      expect(DatarefValue(1, at), DatarefValue(1, at));
      expect(DatarefValue(1, at), isNot(DatarefValue(2, at)));
      expect(const DatarefValue.unknown(), const DatarefValue.unknown());
    });
  });
}
