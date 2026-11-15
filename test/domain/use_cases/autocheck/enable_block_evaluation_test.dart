import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/condition_evaluator.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/evaluate_item_conditions_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

// Switches (D-82). 0 Before, 1 Use GPU (switch, default OFF), 2 GPU and
// 3 GPU power (ON branch), 4 Unplug (OFF branch), 5 After.
Checklist _list() => const AircraftWorkflowParser()
    .parse('''
sw_checklist:A
sw_item:Before|ON:a/before:1
sw_switch:Use GPU|gpu|OFF
sw_item:GPU|ON:a/gpu:1
sw_item:GPU power|ON:a/power:1
sw_else
sw_item:Unplug|ON:a/unplug:1
sw_end
sw_item:After|ON:a/after:1
''')
    .checklists
    .single;

void main() {
  final list = _list();
  final gpu = list.items[1].switchDef!;
  late EvaluateItemConditionsUseCase useCase;
  const values = MapValues({
    'a/before': 1,
    'a/gpu': 1,
    'a/power': 1,
    'a/unplug': 1,
    'a/after': 1,
  });

  setUp(() => useCase = EvaluateItemConditionsUseCase());

  AutoCheckResult run(ChecklistProgress progress) =>
      useCase.evaluate(checklist: list, values: values, progress: progress);

  ChecklistProgress ticked([bool on = false]) {
    final progress = ChecklistProgress().toggled('A', 0).toggled('A', 1);
    return on ? progress.switchSet([list], gpu, on: true) : progress;
  }

  test('auto stops at the switch row until the pilot ticks it', () {
    final result = run(ChecklistProgress());
    expect(result.toCheck, {0});
    expect(result.cursor, 1);
    final on = run(ChecklistProgress().switchSet([list], gpu, on: true));
    expect(on.toCheck, {0}, reason: 'on or off, it waits for the tick');
  });

  test('with the switch off auto evaluates the OFF branch only', () {
    final result = run(ticked());
    expect(result.toCheck, {4, 5});
    expect(result.itemResults.keys, isNot(contains(2)));
  });

  test('with the switch on auto evaluates the ON branch only, in order', () {
    final result = run(ticked(true));
    expect(result.toCheck, {2, 3, 5});
    expect(result.itemResults.keys, isNot(contains(4)));
  });

  test('auto waits on a shown item that is not met', () {
    const off = MapValues({
      'a/before': 1,
      'a/gpu': 0,
      'a/power': 1,
      'a/after': 1,
    });
    final result = useCase.evaluate(
      checklist: list,
      values: off,
      progress: ticked(true),
    );
    expect(result.toCheck, isEmpty);
    expect(result.itemResults[2], Tri.notMet);
  });

  test('the checklist is complete when the shown items are done', () {
    final progress = ticked().toggled('A', 4).toggled('A', 5);
    final result = useCase.evaluate(
      checklist: list,
      values: values,
      progress: progress,
    );
    expect(result.cursor, list.items.length);
  });

  test('resetItems forgets the memory of the given items only', () {
    const text = '''
sw_checklist:A
sw_item:One|X:a/one:+>1
sw_item:Two|X:a/two:+>1
''';
    final change = const AircraftWorkflowParser().parse(text).checklists.single;
    const first = MapValues({'a/one': 0, 'a/two': 0});
    const later = MapValues({'a/one': 5, 'a/two': 5});
    final progress = ChecklistProgress();
    useCase.evaluate(checklist: change, values: first, progress: progress);
    useCase.resetItems('A', [1]);
    // Item 0 kept its baseline (0), so 5 is a rise; item 1 starts again.
    final result = useCase.evaluate(
      checklist: change,
      values: later,
      progress: progress,
    );
    expect(result.toCheck, {0});
  });
}
