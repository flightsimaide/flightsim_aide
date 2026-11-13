import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flightsim_aide/domain/models/checklist/continue_link.dart';
import 'package:flightsim_aide/domain/models/flight_sim/dataref.dart';
import 'package:flightsim_aide/domain/models/flight_sim/item_condition.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/condition_evaluator.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/evaluate_item_conditions_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

// AC-34: auto-check never unchecks (met, then not met leaves the mark)
// AC-35: manual wins (domain half; an untick is not remembered, D-78)
// AC-36: an unknown value never checks an item (evaluator half)

CompareCondition _is(String name, double v) => CompareCondition(
  DatarefExpr(Dataref(name)),
  CompareOp.equal,
  NumberExpr(v),
);

ChecklistItem _check(String label, [ItemCondition? c]) =>
    ChecklistItem(ChecklistItemType.check, label, '', const [], const [], c);

ChecklistItem _note(String label, [ItemCondition? c]) =>
    ChecklistItem(ChecklistItemType.note, label, '', const [], const [], c);

Checklist _list(
  List<ChecklistItem> items, {
  List<ContinueLink> continues = const [],
  String name = 'Start',
}) => Checklist(name: name, title: name, items: items, continues: continues);

void main() {
  group('one-way auto-check', () {
    test('a met condition checks an unchecked item', () {
      final use = EvaluateItemConditionsUseCase();
      final list = _list([_check('gear', _is('g', 1)), _check('manual')]);
      final r = use.evaluate(
        checklist: list,
        values: const MapValues({'g': 1}),
        progress: ChecklistProgress(),
      );
      expect(r.toCheck, {0});
      expect(r.itemResults, {0: Tri.met});
    });

    test('met, then not met: the result changes but nothing unchecks', () {
      final use = EvaluateItemConditionsUseCase();
      final list = _list([_check('gear', _is('g', 1)), _check('manual')]);
      var progress = ChecklistProgress();
      var r = use.evaluate(
        checklist: list,
        values: const MapValues({'g': 1}),
        progress: progress,
      );
      progress = ChecklistProgress({'Start': r.toCheck});
      r = use.evaluate(
        checklist: list,
        values: const MapValues({'g': 0}),
        progress: progress,
      );
      expect(r.toCheck, isEmpty, reason: 'never an uncheck');
      expect(progress.isChecked('Start', 0), isTrue);
    });

    test('an unknown condition never checks', () {
      final use = EvaluateItemConditionsUseCase();
      final list = _list([_check('gear', _is('g', 1))]);
      final r = use.evaluate(
        checklist: list,
        values: const MapValues({}),
        progress: ChecklistProgress(),
      );
      expect(r.toCheck, isEmpty);
      expect(r.itemResults, {0: Tri.unknown});
    });

    test('notes are never checked, even with a condition', () {
      final use = EvaluateItemConditionsUseCase();
      final list = _list([_note('info', _is('g', 1)), _check('manual')]);
      final r = use.evaluate(
        checklist: list,
        values: const MapValues({'g': 1}),
        progress: ChecklistProgress(),
      );
      expect(r.toCheck, isEmpty);
      expect(r.itemResults, isEmpty);
    });

    test('an item that is already checked is not evaluated again', () {
      final use = EvaluateItemConditionsUseCase();
      final list = _list([_check('gear', _is('g', 1))]);
      final r = use.evaluate(
        checklist: list,
        values: const MapValues({'g': 1}),
        progress: ChecklistProgress({
          'Start': {0},
        }),
      );
      expect(r.toCheck, isEmpty);
      expect(r.itemResults, isEmpty);
    });
  });

  group('change conditions keep their baseline per item', () {
    test('the second evaluation sees the change', () {
      final use = EvaluateItemConditionsUseCase();
      final list = _list([
        _check(
          'alt',
          const ChangeCondition(
            DatarefExpr(Dataref('alt')),
            ChangeOp.rise,
            NumberExpr(100),
          ),
        ),
      ]);
      var r = use.evaluate(
        checklist: list,
        values: const MapValues({'alt': 1000}),
        progress: ChecklistProgress(),
      );
      expect(r.toCheck, isEmpty);
      r = use.evaluate(
        checklist: list,
        values: const MapValues({'alt': 1200}),
        progress: ChecklistProgress(),
      );
      expect(r.toCheck, {0});
    });

    test('reset starts a new baseline', () {
      final use = EvaluateItemConditionsUseCase();
      final list = _list([
        _check(
          'alt',
          const ChangeCondition(
            DatarefExpr(Dataref('alt')),
            ChangeOp.rise,
            NumberExpr(100),
          ),
        ),
      ]);
      use.evaluate(
        checklist: list,
        values: const MapValues({'alt': 1000}),
        progress: ChecklistProgress(),
      );
      use.reset();
      final r = use.evaluate(
        checklist: list,
        values: const MapValues({'alt': 1200}),
        progress: ChecklistProgress(),
      );
      expect(r.toCheck, isEmpty, reason: '1200 is the new baseline');
    });
  });

  group('continue', () {
    final all = ChecklistProgress({
      'A': {0},
    });

    test('no result while the checklist is not complete', () {
      final use = EvaluateItemConditionsUseCase();
      final a = _list(
        [_check('one'), _check('two')],
        name: 'A',
        continues: const [ContinueLink.named('B')],
      );
      final r = use.evaluate(
        checklist: a,
        values: const MapValues({}),
        progress: all,
        checklists: [
          a,
          _list([_check('x')], name: 'B'),
        ],
      );
      expect(r.continueTo, isNull);
    });

    test('completion counts the items this step checks', () {
      final use = EvaluateItemConditionsUseCase();
      final a = _list(
        [_check('one'), _check('two', _is('g', 1))],
        name: 'A',
        continues: const [ContinueLink.named('B')],
      );
      final r = use.evaluate(
        checklist: a,
        values: const MapValues({'g': 1}),
        progress: all,
        checklists: [
          a,
          _list([_check('x')], name: 'B'),
        ],
      );
      expect(r.toCheck, {1});
      expect(r.continueTo, 'B');
    });

    test('the first matching link wins, in order', () {
      final use = EvaluateItemConditionsUseCase();
      final a = _list(
        [_check('one')],
        name: 'A',
        continues: [
          ContinueLink.named('X', condition: _is('v', 1)),
          ContinueLink.named('Y', condition: _is('v', 2)),
          const ContinueLink.named('Z'),
        ],
      );
      String? go(double v) => use
          .evaluate(checklist: a, values: MapValues({'v': v}), progress: all)
          .continueTo;
      expect(go(1), 'X');
      expect(go(2), 'Y');
      expect(go(3), 'Z');
    });

    test('no link matching gives null', () {
      final use = EvaluateItemConditionsUseCase();
      final a = _list(
        [_check('one')],
        name: 'A',
        continues: [ContinueLink.named('X', condition: _is('v', 1))],
      );
      expect(
        use
            .evaluate(
              checklist: a,
              values: const MapValues({'v': 5}),
              progress: all,
            )
            .continueTo,
        isNull,
      );
    });

    test('an unknown link condition is not followed', () {
      final use = EvaluateItemConditionsUseCase();
      final a = _list(
        [_check('one')],
        name: 'A',
        continues: [
          ContinueLink.named('X', condition: _is('v', 1)),
          const ContinueLink.named('Z'),
        ],
      );
      expect(
        use
            .evaluate(checklist: a, values: const MapValues({}), progress: all)
            .continueTo,
        'Z',
      );
    });

    test('a bare link goes to the next checklist in file order', () {
      final use = EvaluateItemConditionsUseCase();
      final a = _list(
        [_check('one')],
        name: 'A',
        continues: const [ContinueLink.next()],
      );
      final r = use.evaluate(
        checklist: a,
        values: const MapValues({}),
        progress: all,
        checklists: [
          a,
          _list([_check('x')], name: 'B'),
        ],
      );
      expect(r.continueTo, 'B');
    });

    test('change conditions in a link never hold', () {
      final use = EvaluateItemConditionsUseCase();
      final a = _list(
        [_check('one')],
        name: 'A',
        continues: [
          const ContinueLink.named(
            'X',
            condition: ChangeCondition(
              DatarefExpr(Dataref('v')),
              ChangeOp.either,
              NumberExpr(0),
            ),
          ),
        ],
      );
      for (var i = 0; i < 3; i++) {
        expect(
          use
              .evaluate(
                checklist: a,
                values: MapValues({'v': 5.0 + i * 100}),
                progress: all,
              )
              .continueTo,
          isNull,
          reason: 'each evaluation starts from a fresh baseline (J3)',
        );
      }
    });
  });
}
