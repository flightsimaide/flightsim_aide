import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flightsim_aide/domain/models/checklist/switch_gate.dart';
import 'package:flutter_test/flutter_test.dart';

// Switches (D-82). Checklist A: 0 Before, 1 Use GPU (switch, default OFF),
// 2 GPU and 3 GPU power (ON branch), 4 Unplug (OFF branch), 5 After.
// Checklist B has a block of the same switch: 0 Early (ON), 1 Late (OFF).
const _text = '''
sw_checklist:A
sw_item:Before|ON
sw_switch:Use GPU|gpu|OFF
sw_item:GPU|CONNECT
sw_item:GPU power|ON
sw_else
sw_item:Unplug|CHECK
sw_end
sw_item:After|ON
sw_checklist:B
sw_if|gpu|ON
sw_item:Early|ON
sw_else
sw_item:Late|ON
sw_end
''';

void main() {
  final document = const AircraftWorkflowParser().parse(_text);
  final lists = document.checklists;
  final list = lists[0];
  final other = lists[1];
  final gpu = list.items[1].switchDef!;

  ChecklistProgress on([ChecklistProgress? p]) =>
      (p ?? ChecklistProgress()).switchSet(lists, gpu, on: true);
  ChecklistProgress off(ChecklistProgress p) =>
      p.switchSet(lists, gpu, on: false);

  test('a switch is at its default, and the other branch is enabled', () {
    final progress = ChecklistProgress();
    expect(progress.isSwitchOn(gpu), isFalse);
    expect(
      [for (var i = 0; i < 6; i++) progress.isEnabled(list, i)],
      [true, true, false, false, true, true],
    );
    expect(progress.countsFor(list), (done: 0, total: 4, skipped: 0));
  });

  test('a switch whose default is ON starts on', () {
    final doc = const AircraftWorkflowParser().parse(
      'sw_checklist:A\nsw_switch:X|a|ON\nsw_item:i\nsw_else\nsw_item:j\nsw_end',
    );
    final a = doc.checklists.single;
    final progress = ChecklistProgress();
    expect(progress.isSwitchOn(a.items[0].switchDef!), isTrue);
    expect(
      [for (var i = 0; i < 3; i++) progress.isEnabled(a, i)],
      [true, true, false],
    );
  });

  test('turning a switch on swaps the branches and the total follows', () {
    final progress = on();
    expect(progress.isSwitchOn(gpu), isTrue);
    expect(
      [for (var i = 0; i < 6; i++) progress.isEnabled(list, i)],
      [true, true, true, true, false, true],
    );
    expect(progress.countsFor(list), (done: 0, total: 5, skipped: 0));
  });

  test('the position is shared by the blocks of every checklist', () {
    expect(ChecklistProgress().isEnabled(other, 0), isFalse);
    expect(ChecklistProgress().isEnabled(other, 1), isTrue);
    expect(on().isEnabled(other, 0), isTrue);
    expect(on().isEnabled(other, 1), isFalse);
    expect(on().countsFor(other).total, 1);
  });

  test('the switch row is always counted and never gated', () {
    final progress = ChecklistProgress();
    expect(progress.isEnabled(list, 1), isTrue, reason: 'it has no gate');
    final ticked = progress.toggled('A', 1);
    expect(ticked.countsFor(list), (done: 1, total: 4, skipped: 0));
    final skipped = progress.skipping('A', 1);
    expect(skipped.countsFor(list), (done: 0, total: 4, skipped: 1));
  });

  test('the tick of the switch row is independent of the switch', () {
    var progress = ChecklistProgress().toggled('A', 1);
    expect(progress.isSwitchOn(gpu), isFalse, reason: 'ticking is not on');
    progress = off(on(progress));
    expect(progress.isChecked('A', 1), isTrue, reason: 'off keeps the tick');
    progress = progress.toggled('A', 1);
    expect(progress.isChecked('A', 1), isFalse);
    expect(progress.isSwitchOn(gpu), isFalse);
  });

  test('completion follows the enabled items only', () {
    var progress = ChecklistProgress()
        .toggled('A', 0)
        .toggled('A', 1)
        .toggled('A', 4)
        .toggled('A', 5);
    expect(progress.isComplete(list), isTrue);
    progress = on(progress);
    expect(progress.isComplete(list), isFalse);
    progress = progress.toggled('A', 2).toggled('A', 3);
    expect(progress.isComplete(list), isTrue);
  });

  test('turning a switch clears the marks of the branch it hides', () {
    var progress = on().toggled('A', 2, disagrees: true).autoChecking('A', [3]);
    progress = progress.toggled('A', 0);
    progress = off(progress);
    expect(progress.isChecked('A', 2), isFalse);
    expect(progress.isChecked('A', 3), isFalse);
    expect(progress.isDisagreed('A', 2), isFalse);
    expect(progress.isAutoChecked('A', 3), isFalse);
    expect(progress.isChecked('A', 0), isTrue, reason: 'outside the block');
    // The same goes for the OFF branch when turning on hides it.
    final unplugged = ChecklistProgress().toggled('A', 4);
    expect(on(unplugged).isChecked('A', 4), isFalse);
  });

  test('marks of a block in another checklist are cleared too', () {
    var progress = on().toggled('B', 0);
    expect(progress.isChecked('B', 0), isTrue);
    progress = off(progress);
    expect(progress.isChecked('B', 0), isFalse);
    expect(progress.isEnabled(other, 1), isTrue);
  });

  test('turning a switch off clears skips of its items', () {
    var progress = on().skipping('A', 2);
    expect(progress.isSkipped('A', 2), isTrue);
    progress = off(progress);
    expect(progress.isSkipped('A', 2), isFalse);
  });

  test('turning it on leaves the items open', () {
    final progress = on();
    expect(progress.isChecked('A', 2), isFalse);
    expect(progress.isChecked('A', 3), isFalse);
  });

  test('the cursor goes back to the switch row when it was past it', () {
    var progress = ChecklistProgress().toggled('A', 5); // cursor 5
    expect(progress.cursorOf('A'), 5);
    progress = on(progress);
    expect(progress.cursorOf('A'), 1);
    progress = progress.toggled('A', 3);
    expect(progress.cursorOf('A'), 3);
    progress = off(progress);
    expect(progress.cursorOf('A'), 1);
  });

  test('the cursor of a checklist with only a block goes to the block', () {
    final progress = on(ChecklistProgress().toggled('B', 1));
    expect(progress.cursorOf('B'), 0);
  });

  test('the cursor stays when it is above the switch row', () {
    final progress = on(ChecklistProgress().toggled('A', 0));
    expect(progress.cursorOf('A'), 0);
  });

  test('a position that does not change does nothing', () {
    final progress = ChecklistProgress();
    expect(
      identical(progress.switchSet(lists, gpu, on: false), progress),
      isTrue,
    );
  });

  test('a position equal to the default is not kept', () {
    expect(off(on()), ChecklistProgress());
    expect(on().switches, {'gpu': true});
    expect(ChecklistProgress().switches, isEmpty);
  });

  test('Reset keeps the switch positions and clears the ticks', () {
    var progress = on().toggled('A', 2);
    progress = progress.reset('A');
    expect(progress.isSwitchOn(gpu), isTrue);
    expect(progress.isChecked('A', 2), isFalse);
  });

  test('resetting all puts the switches back to their default', () {
    expect(on().resetAll().isSwitchOn(gpu), isFalse);
  });

  test('later changes keep the switches', () {
    final progress = on().toggled('A', 0).skipping('A', 2).autoChecking('A', [
      3,
    ]);
    expect(progress.isSwitchOn(gpu), isTrue);
  });

  test('two progresses differing only in a switch are not equal', () {
    expect(on(), isNot(ChecklistProgress()));
  });

  test('a red mark of a hidden item is not counted', () {
    final progress = on().toggled('A', 2, disagrees: true);
    expect(progress.disagreedCount(list), 1);
    expect(off(progress).disagreedCount(list), 0);
  });

  test('a switch that no row names changes only its own position', () {
    const unrelated = SwitchDef('nothing');
    final progress = ChecklistProgress().switchSet(lists, unrelated, on: true);
    expect(progress.isSwitchOn(unrelated), isTrue);
    expect(progress.countsFor(list), ChecklistProgress().countsFor(list));
  });
}
