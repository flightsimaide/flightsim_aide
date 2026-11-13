import 'package:flutter_test/flutter_test.dart';

import '../../testing/fixtures/condition_fixtures.dart';

void main() {
  final cases = ConditionFixtures.all();

  test('the folder has a case for every form of the condition grammar', () {
    expect(
      cases.map((c) => c.name),
      containsAll([
        'plain_equal',
        'plain_not_equal',
        'plain_order',
        'plain_range',
        'plain_values',
        'change',
        'crossing',
        'arrays',
        'logic',
        'continue',
        'malformed',
      ]),
    );
  });

  for (final c in cases) {
    group(c.name, () {
      test('has checklist text with at least one checklist', () {
        expect(c.checklists, isNotEmpty);
        expect(c.checkItemCount, greaterThan(0));
      });

      test('values are numbers or null in at least one step', () {
        expect(c.steps, isNotEmpty);
        for (final step in c.steps) {
          for (final entry in step.entries) {
            expect(entry.value, anyOf(isNull, isA<num>()), reason: entry.key);
          }
        }
      });

      test('every expected index is a check item, in one list only', () {
        final all = [...c.met, ...c.notMet, ...c.unknown];
        expect(
          all.toSet().length,
          all.length,
          reason: 'an index is listed twice',
        );
        for (final i in all) {
          expect(i, inInclusiveRange(0, c.checkItemCount - 1));
        }
      });

      test('continue targets name real checklists', () {
        for (final entry in c.continueTargets.entries) {
          expect(c.checklists, contains(entry.key));
          if (entry.value != null) expect(c.checklists, contains(entry.value));
        }
      });

      test('has a source and a warnings list', () {
        expect(c.source, isNotEmpty);
        expect(c.warnings, isA<List<String>>());
      });
    });
  }

  test('only the malformed case expects condition warnings', () {
    for (final c in cases) {
      final has = c.warnings.any((w) => w.contains('condition not supported'));
      expect(has, c.name == 'malformed', reason: c.name);
    }
  });

  test('the loader refuses a case with a missing sibling file', () {
    expect(
      () => ConditionFixtures.all(directory: 'testing/fixtures/does_not_exist'),
      throwsA(isA<StateError>()),
    );
  });
}
