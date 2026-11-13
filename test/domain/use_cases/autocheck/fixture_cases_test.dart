import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flightsim_aide/domain/models/flight_sim/item_condition.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/condition_evaluator.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/evaluate_item_conditions_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../testing/fixtures/condition_fixtures.dart';

// AC-31: every condition fixture parses, malformed ones warn and stay manual
// AC-32: every fixture gives the expected met, not met and unknown items
// AC-38: conditional sw_continue picks the expected target in every fixture (domain half)

/// The values after step [n] (0-based): a name absent from a step keeps its
/// earlier value, null removes it (`testing/fixtures/conditions/README.md`).
Map<String, double?> _valuesAfter(ConditionFixture f, int n) {
  final values = <String, double?>{};
  for (var i = 0; i <= n; i++) {
    for (final e in f.steps[i].entries) {
      values[e.key] = e.value?.toDouble();
    }
  }
  return values;
}

void main() {
  const parser = AircraftWorkflowParser();

  group('item conditions (AC-32)', () {
    for (final f in ConditionFixtures.all()) {
      test(f.name, () {
        final document = parser.parse(f.text);
        // Check items in file order; an item with no usable condition is in none
        // of the expected lists.
        final conditions = <ItemCondition?>[
          for (final c in document.checklists)
            for (final item in c.items)
              if (item.type == ChecklistItemType.check) item.condition,
        ];
        expect(conditions, hasLength(f.checkItemCount - _dropped(f, document)));
        final states = [for (final _ in conditions) ConditionState()];
        const evaluator = ConditionEvaluator();
        final result = List<Tri?>.filled(conditions.length, null);
        for (var step = 0; step < f.steps.length; step++) {
          final values = MapValues(_valuesAfter(f, step));
          for (var i = 0; i < conditions.length; i++) {
            final c = conditions[i];
            if (c != null) result[i] = evaluator.evaluate(c, values, states[i]);
          }
        }
        List<int> where(Tri t) => [
          for (var i = 0; i < result.length; i++)
            if (result[i] == t) i,
        ];
        expect(where(Tri.met), f.met, reason: 'met');
        expect(where(Tri.notMet), f.notMet, reason: 'not met');
        expect(where(Tri.unknown), f.unknown, reason: 'unknown');
      });
    }
  });

  group('warnings (AC-31)', () {
    for (final f in ConditionFixtures.all()) {
      test(f.name, () {
        final warnings = parser
            .parse(f.text)
            .warnings
            .where((w) => w.contains('condition not supported'))
            .toList();
        expect(
          warnings,
          f.warnings.where((w) => w.contains('condition not supported')),
        );
      });
    }
  });

  group('conditional sw_continue (AC-38)', () {
    for (final f in ConditionFixtures.all().where(
      (f) => f.continueTargets.isNotEmpty,
    )) {
      test(f.name, () {
        final document = parser.parse(f.text);
        final values = MapValues(_valuesAfter(f, f.steps.length - 1));
        for (final entry in f.continueTargets.entries) {
          final Checklist checklist = document.checklists.firstWhere(
            (c) => c.name == entry.key,
          );
          // Every item checked: the checklist is finished.
          final progress = ChecklistProgress({
            checklist.name: {
              for (var i = 0; i < checklist.items.length; i++) i,
            },
          });
          final result = EvaluateItemConditionsUseCase().evaluate(
            checklist: checklist,
            values: values,
            progress: progress,
            checklists: document.checklists,
          );
          expect(result.continueTo, entry.value, reason: entry.key);
        }
      });
    }
  });
}

/// Check items the parser dropped from the checklist (none today).
int _dropped(ConditionFixture f, Object document) => 0;
