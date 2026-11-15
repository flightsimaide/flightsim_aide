import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flutter_test/flutter_test.dart';

// Switch blocks (D-82). Indexes below:
// 0 Before, 1 Use GPU (switch), 2 GPU, 3 GPU power, 4 After
Checklist _list() => const AircraftWorkflowParser()
    .parse('''
sw_checklist:A
sw_item:Before|ON
sw_enable_start:Use GPU
sw_item:GPU|CONNECT
sw_item:GPU power|ON
sw_enable_end
sw_item:After|ON
''')
    .checklists
    .single;

void main() {
  final list = _list();

  test('a switch is off by default and its items are not counted', () {
    final progress = ChecklistProgress();
    expect(progress.isOptionOn('A', 1), isFalse);
    expect(progress.isEnabled(list, 0), isTrue);
    expect(progress.isEnabled(list, 2), isFalse);
    expect(progress.countsFor(list), (done: 0, total: 3, skipped: 0));
  });

  test('turning a switch on adds its items to the total', () {
    final progress = ChecklistProgress().optionSet(list, 1, on: true);
    expect(progress.isOptionOn('A', 1), isTrue);
    expect(progress.isEnabled(list, 3), isTrue);
    expect(progress.countsFor(list), (done: 0, total: 5, skipped: 0));
  });

  test('the switch row itself is always counted and never gated', () {
    final progress = ChecklistProgress();
    expect(progress.isEnabled(list, 1), isTrue, reason: 'it has no gate');
    expect(progress.countsFor(list).total, 3);
    final ticked = progress.toggled('A', 1);
    expect(ticked.countsFor(list), (done: 1, total: 3, skipped: 0));
    final skipped = progress.skipping('A', 1);
    expect(skipped.countsFor(list), (done: 0, total: 3, skipped: 1));
  });

  test('the tick of the switch row is independent of the switch', () {
    var progress = ChecklistProgress().toggled('A', 1);
    expect(progress.isOptionOn('A', 1), isFalse, reason: 'ticking is not on');
    progress = progress
        .optionSet(list, 1, on: true)
        .optionSet(list, 1, on: false);
    expect(progress.isChecked('A', 1), isTrue, reason: 'off keeps the tick');
    progress = progress.toggled('A', 1);
    expect(progress.isChecked('A', 1), isFalse);
    expect(progress.isOptionOn('A', 1), isFalse);
  });

  test('completion follows the enabled items only', () {
    var progress = ChecklistProgress()
        .toggled('A', 0)
        .toggled('A', 1)
        .toggled('A', 4);
    expect(progress.isComplete(list), isTrue, reason: 'GPU items are off');
    expect(
      progress.toggled('A', 1).isComplete(list),
      isFalse,
      reason: 'the switch row is an item',
    );
    progress = progress.optionSet(list, 1, on: true);
    expect(progress.isComplete(list), isFalse);
    progress = progress.toggled('A', 2).toggled('A', 3);
    expect(progress.isComplete(list), isTrue);
  });

  test('turning a switch off clears every mark of its items', () {
    var progress = ChecklistProgress().optionSet(list, 1, on: true);
    progress = progress
        .toggled('A', 2, disagrees: true)
        .autoChecking('A', [3])
        .toggled('A', 0);
    progress = progress.optionSet(list, 1, on: false);
    expect(progress.isChecked('A', 2), isFalse);
    expect(progress.isChecked('A', 3), isFalse);
    expect(progress.isDisagreed('A', 2), isFalse);
    expect(progress.isAutoChecked('A', 3), isFalse);
    expect(progress.isChecked('A', 0), isTrue, reason: 'outside the block');
  });

  test('turning a switch off clears skips of its items', () {
    var progress = ChecklistProgress()
        .optionSet(list, 1, on: true)
        .skipping('A', 2);
    expect(progress.isSkipped('A', 2), isTrue);
    progress = progress.optionSet(list, 1, on: false);
    expect(progress.isSkipped('A', 2), isFalse);
  });

  test('turning it on leaves the items open', () {
    final progress = ChecklistProgress().optionSet(list, 1, on: true);
    expect(progress.isChecked('A', 2), isFalse);
    expect(progress.isChecked('A', 3), isFalse);
  });

  test('the cursor goes back to the switch row when it was past it', () {
    var progress = ChecklistProgress().toggled('A', 4); // cursor 4
    expect(progress.cursorOf('A'), 4);
    progress = progress.optionSet(list, 1, on: true);
    expect(progress.cursorOf('A'), 1);
    progress = progress.toggled('A', 3);
    expect(progress.cursorOf('A'), 3);
    progress = progress.optionSet(list, 1, on: false);
    expect(progress.cursorOf('A'), 1);
  });

  test('the cursor stays when it is above the switch row', () {
    final progress = ChecklistProgress()
        .toggled('A', 0)
        .optionSet(list, 1, on: true);
    expect(progress.cursorOf('A'), 0);
  });

  test('a position that does not change, and a non-switch row, do nothing', () {
    final progress = ChecklistProgress();
    expect(identical(progress.optionSet(list, 1, on: false), progress), isTrue);
    expect(identical(progress.optionSet(list, 0, on: true), progress), isTrue);
    expect(identical(progress.optionSet(list, 99, on: true), progress), isTrue);
  });

  test('Reset keeps the switch positions and clears the ticks', () {
    var progress = ChecklistProgress()
        .optionSet(list, 1, on: true)
        .toggled('A', 2);
    progress = progress.reset('A');
    expect(progress.isOptionOn('A', 1), isTrue);
    expect(progress.isChecked('A', 2), isFalse);
  });

  test('resetting all clears the switches too', () {
    final progress = ChecklistProgress()
        .optionSet(list, 1, on: true)
        .resetAll();
    expect(progress.isOptionOn('A', 1), isFalse);
  });

  test('later changes keep the switches', () {
    final progress = ChecklistProgress()
        .optionSet(list, 1, on: true)
        .toggled('A', 0)
        .skipping('A', 2)
        .autoChecking('A', [3]);
    expect(progress.isOptionOn('A', 1), isTrue);
  });

  test('two progresses differing only in a switch are not equal', () {
    expect(
      ChecklistProgress().optionSet(list, 1, on: true),
      isNot(ChecklistProgress()),
    );
  });

  test('a red mark of a disabled item is not counted', () {
    final progress = ChecklistProgress()
        .optionSet(list, 1, on: true)
        .toggled('A', 2, disagrees: true);
    expect(progress.disagreedCount(list), 1);
    expect(progress.optionSet(list, 1, on: false).disagreedCount(list), 0);
  });
}
