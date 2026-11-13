import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flightsim_aide/domain/models/flight_sim/dataref.dart';
import 'package:flightsim_aide/domain/models/flight_sim/item_condition.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/condition_evaluator.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/evaluate_item_conditions_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

// AC-33: auto checks the item it is waiting on, in order (domain half)
// AC-34: auto never unchecks and never goes back (D-71)
// AC-35: manual wins; the cursor follows the pilot (domain half)

CompareCondition _is(String name, double v) => CompareCondition(
  DatarefExpr(Dataref(name)),
  CompareOp.equal,
  NumberExpr(v),
);

ChangeCondition _rises(String name, double by) =>
    ChangeCondition(DatarefExpr(Dataref(name)), ChangeOp.rise, NumberExpr(by));

ChecklistItem _check(String label, [ItemCondition? c]) =>
    ChecklistItem(ChecklistItemType.check, label, '', const [], const [], c);

ChecklistItem _note(String label) =>
    ChecklistItem(ChecklistItemType.note, label);

Checklist _list(List<ChecklistItem> items) =>
    Checklist(name: 'Start', title: 'Start', items: items);

/// Four conditioned items a, b, c, d on datarefs a, b, c, d (each wanting 1).
Checklist _abcd() => _list([
  _check('a', _is('a', 1)),
  _check('b', _is('b', 1)),
  _check('c', _is('c', 1)),
  _check('d', _is('d', 1)),
]);

ChecklistProgress _progress({Set<int> checked = const {}, int cursor = 0}) =>
    ChecklistProgress.marks(
      checked: {'Start': checked},
      cursor: {'Start': cursor},
    );

void main() {
  late EvaluateItemConditionsUseCase use;
  setUp(() => use = EvaluateItemConditionsUseCase());

  AutoCheckResult run(
    Checklist list,
    Map<String, double?> values, [
    ChecklistProgress? progress,
  ]) => use.evaluate(
    checklist: list,
    values: MapValues(values),
    progress: progress ?? ChecklistProgress(),
  );

  group('opening a checklist', () {
    test('items that are already true tick in sequence from the top', () {
      final r = run(_abcd(), {'a': 1, 'b': 1, 'c': 0, 'd': 1});
      expect(r.toCheck, {0, 1}, reason: 'd is true but c stops the run');
      expect(r.cursor, 2, reason: 'waiting at c');
    });

    test('a false first item ticks nothing, even if later ones are true', () {
      final r = run(_abcd(), {'a': 0, 'b': 1, 'c': 1, 'd': 1});
      expect(r.toCheck, isEmpty);
      expect(r.cursor, 0);
    });

    test('every item true ticks them all and the cursor passes the end', () {
      final r = run(_abcd(), {'a': 1, 'b': 1, 'c': 1, 'd': 1});
      expect(r.toCheck, {0, 1, 2, 3});
      expect(r.cursor, 4);
    });

    test('notes are passed over', () {
      final list = _list([
        _note('heading'),
        _check('a', _is('a', 1)),
        _note('remark'),
        _check('b', _is('b', 1)),
      ]);
      final r = run(list, {'a': 1, 'b': 1});
      expect(r.toCheck, {1, 3});
    });

    test('an unknown value at the pointer stops the run', () {
      final r = run(_abcd(), {'a': 1, 'b': null, 'c': 1, 'd': 1});
      expect(r.toCheck, {0});
      expect(r.cursor, 1);
    });
  });

  group('a manual item', () {
    test('an item with no condition stops auto and nothing below ticks', () {
      final list = _list([
        _check('a', _is('a', 1)),
        _check('manual'),
        _check('c', _is('c', 1)),
      ]);
      final r = run(list, {'a': 1, 'c': 1});
      expect(r.toCheck, {0});
      expect(r.cursor, 1);
    });

    test('once the pilot ticks it, auto goes on from the next item', () {
      final list = _list([
        _check('a', _is('a', 1)),
        _check('manual'),
        _check('c', _is('c', 1)),
      ]);
      final r = run(list, {
        'a': 1,
        'c': 1,
      }, _progress(checked: {0, 1}, cursor: 1));
      expect(r.toCheck, {2});
    });
  });

  group('while the pilot works (AC-33)', () {
    test('a flip ticks only the item auto is waiting on', () {
      final first = run(_abcd(), {'a': 1, 'b': 0, 'c': 0, 'd': 0});
      expect(first.toCheck, {0});
      final progress = _progress(checked: {0}, cursor: first.cursor);
      // d flips first: nothing happens, auto still waits at b
      final second = run(_abcd(), {'a': 1, 'b': 0, 'c': 0, 'd': 1}, progress);
      expect(second.toCheck, isEmpty);
      expect(second.cursor, 1);
      // then b flips: b ticks, then c is false so it stops
      final third = run(_abcd(), {'a': 1, 'b': 1, 'c': 0, 'd': 1}, progress);
      expect(third.toCheck, {1});
      expect(third.cursor, 2);
    });

    test('items that were true early tick at once when auto reaches them', () {
      final progress = _progress(checked: {0}, cursor: 1);
      final r = run(_abcd(), {'a': 1, 'b': 1, 'c': 1, 'd': 1}, progress);
      expect(r.toCheck, {1, 2, 3});
    });
  });

  group('following the pilot (AC-35)', () {
    test('a jump ahead: auto waits at the item after the one ticked', () {
      // The pilot ticked c by hand: cursor 2, a and b skipped.
      final progress = _progress(checked: {2}, cursor: 2);
      final r = run(_abcd(), {'a': 1, 'b': 1, 'c': 1, 'd': 0}, progress);
      expect(r.toCheck, isEmpty, reason: 'a and b are behind the pointer');
      expect(r.cursor, 3, reason: 'waiting at d');
    });

    test('a jump ahead then d becomes true: d ticks', () {
      final progress = _progress(checked: {2}, cursor: 2);
      final r = run(_abcd(), {'a': 0, 'b': 0, 'c': 1, 'd': 1}, progress);
      expect(r.toCheck, {3});
    });

    test(
      'backing up: the pilot ticks a skipped item and the pointer follows',
      () {
        // c and d were ticked, a was skipped, b skipped; the pilot ticks b: cursor 1.
        final progress = _progress(checked: {1, 2, 3}, cursor: 1);
        final r = run(_abcd(), {'a': 1, 'b': 1, 'c': 1, 'd': 1}, progress);
        expect(
          r.toCheck,
          isEmpty,
          reason: 'a is behind the cursor and stays open',
        );
      },
    );

    test('auto never goes back to a skipped item', () {
      final progress = _progress(checked: {2}, cursor: 2);
      final r = run(_abcd(), {'a': 1, 'b': 1, 'c': 1, 'd': 0}, progress);
      expect(r.toCheck.contains(0), isFalse);
      expect(r.toCheck.contains(1), isFalse);
    });

    test('auto never unchecks anything', () {
      final progress = _progress(checked: {0, 1}, cursor: 2);
      final r = run(_abcd(), {'a': 0, 'b': 0, 'c': 0, 'd': 0}, progress);
      expect(r.toCheck, isEmpty);
    });
  });

  group('change conditions take their baseline at the pointer (D-58)', () {
    Checklist alt() => _list([
      _check('gear', _is('g', 1)),
      _check('climb', _rises('alt', 100)),
    ]);

    test('values seen before the item is the pointer do not count', () {
      // gear is false: the pointer is on it, climb is not evaluated at all.
      run(alt(), {'g': 0, 'alt': 1000});
      run(alt(), {'g': 0, 'alt': 5000});
      // gear goes true: climb becomes the pointer and takes 5000 as its baseline.
      var r = run(alt(), {'g': 1, 'alt': 5000});
      expect(r.toCheck, {0});
      r = run(alt(), {'g': 1, 'alt': 5050}, _progress(checked: {0}, cursor: 1));
      expect(r.toCheck, isEmpty);
      r = run(alt(), {'g': 1, 'alt': 5200}, _progress(checked: {0}, cursor: 1));
      expect(r.toCheck, {1});
    });
  });

  group('the condition of a manually ticked item (the red warning)', () {
    test('a false plain condition is not met', () {
      final t = use.conditionOf(
        checklist: _abcd(),
        index: 1,
        values: const MapValues({'b': 0}),
      );
      expect(t, Tri.notMet);
    });

    test('a true plain condition is met', () {
      final t = use.conditionOf(
        checklist: _abcd(),
        index: 1,
        values: const MapValues({'b': 1}),
      );
      expect(t, Tri.met);
    });

    test('a missing value is unknown', () {
      final t = use.conditionOf(
        checklist: _abcd(),
        index: 1,
        values: const MapValues({'b': null}),
      );
      expect(t, Tri.unknown);
    });

    test('an item with no condition, a note or a bad index is unknown', () {
      final list = _list([_check('manual'), _note('n')]);
      const values = MapValues({});
      expect(
        use.conditionOf(checklist: list, index: 0, values: values),
        Tri.unknown,
      );
      expect(
        use.conditionOf(checklist: list, index: 1, values: values),
        Tri.unknown,
      );
      expect(
        use.conditionOf(checklist: list, index: 9, values: values),
        Tri.unknown,
      );
      expect(
        use.conditionOf(checklist: list, index: -1, values: values),
        Tri.unknown,
      );
    });

    test(
      'a change condition that has no baseline yet is unknown, not false',
      () {
        final list = _list([_check('climb', _rises('alt', 100))]);
        final t = use.conditionOf(
          checklist: list,
          index: 0,
          values: const MapValues({'alt': 1000}),
        );
        expect(t, Tri.unknown);
      },
    );

    test(
      'a change condition that was the pointer is judged by its baseline',
      () {
        final list = _list([_check('climb', _rises('alt', 100))]);
        run(list, {'alt': 1000});
        expect(
          use.conditionOf(
            checklist: list,
            index: 0,
            values: const MapValues({'alt': 1010}),
          ),
          Tri.notMet,
        );
        expect(
          use.conditionOf(
            checklist: list,
            index: 0,
            values: const MapValues({'alt': 1500}),
          ),
          Tri.met,
        );
      },
    );

    test('asking does not create a baseline for later', () {
      final list = _list([_check('climb', _rises('alt', 100))]);
      use.conditionOf(
        checklist: list,
        index: 0,
        values: const MapValues({'alt': 1000}),
      );
      // The first real evaluation still takes its own baseline, at 2000.
      final r = run(list, {'alt': 2000});
      expect(r.toCheck, isEmpty);
      final r2 = run(list, {'alt': 2200});
      expect(r2.toCheck, {0});
    });
  });

  group('needsMemory', () {
    test('only the change and crossing forms, alone or inside and/or', () {
      expect(_is('a', 1).needsMemory, isFalse);
      expect(_rises('a', 1).needsMemory, isTrue);
      expect(
        const CrossingCondition(
          DatarefExpr(Dataref('a')),
          NumberExpr(1),
          NumberExpr(2),
        ).needsMemory,
        isTrue,
      );
      expect(
        const RangeCondition(
          DatarefExpr(Dataref('a')),
          NumberExpr(1),
          NumberExpr(2),
        ).needsMemory,
        isFalse,
      );
      expect(AndCondition([_is('a', 1), _rises('b', 1)]).needsMemory, isTrue);
      expect(OrCondition([_is('a', 1), _is('b', 1)]).needsMemory, isFalse);
    });
  });
}
