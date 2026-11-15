import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/condition_evaluator.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/evaluate_item_conditions_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

// Switch blocks (D-82). 0 Before, 1 Use GPU, 2 GPU, 3 GPU power, 4 After
Checklist _list() => const AircraftWorkflowParser()
    .parse('''
sw_checklist:A
sw_item:Before|ON:a/before:1
sw_enable_start:Use GPU
sw_item:GPU|ON:a/gpu:1
sw_item:GPU power|ON:a/power:1
sw_enable_end
sw_item:After|ON:a/after:1
''')
    .checklists
    .single;

void main() {
  final list = _list();
  late EvaluateItemConditionsUseCase useCase;
  const values = MapValues({
    'a/before': 1,
    'a/gpu': 1,
    'a/power': 1,
    'a/after': 1,
  });

  setUp(() => useCase = EvaluateItemConditionsUseCase());

  AutoCheckResult run(ChecklistProgress progress) =>
      useCase.evaluate(checklist: list, values: values, progress: progress);

  test('items of a switch that is off are passed over', () {
    final result = run(ChecklistProgress());
    expect(result.toCheck, {0, 4});
    expect(result.itemResults.keys, isNot(contains(2)));
  });

  test('items of a switch that is on are evaluated in order', () {
    final result = run(ChecklistProgress().optionSet(list, 1, on: true));
    expect(result.toCheck, {0, 2, 3, 4});
  });

  test('auto waits on an enabled item that is not met', () {
    const off = MapValues({
      'a/before': 1,
      'a/gpu': 0,
      'a/power': 1,
      'a/after': 1,
    });
    final result = useCase.evaluate(
      checklist: list,
      values: off,
      progress: ChecklistProgress().optionSet(list, 1, on: true),
    );
    expect(result.toCheck, {0});
  });

  test('the checklist is complete when the enabled items are done', () {
    final progress = ChecklistProgress().toggled('A', 0).toggled('A', 4);
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
