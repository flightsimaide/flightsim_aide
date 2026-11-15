import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/ui/checklist_detail/cubit/checklist_detail_cubit.dart';
import 'package:flightsim_aide/ui/checklist_detail/cubit/checklist_detail_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../../testing/fakes/repositories/fake_checklist_repository.dart';
import '../../../testing/fakes/repositories/fake_flight_sim_repository.dart';
import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/services/manual_clock.dart';

// Switch blocks (D-82). Rows: 0 Before, 1 Use GPU (switch), 2 GPU,
// 3 GPU power, 4 After.
const _text = '''
sw_checklist:Start
sw_item:Before|ON:a/before:1
sw_enable_start:Use GPU
sw_item:GPU|ON:a/gpu:1
sw_item:GPU power|ON:a/power:1
sw_enable_end
sw_item:After|ON:a/after:1
''';

void main() {
  late FakeChecklistRepository checklists;
  late FakeChecklistProgressRepository progress;
  late FakeFlightSimRepository sim;
  late FakeSettingsRepository settings;
  late ManualClock clock;
  late ChecklistDetailCubit cubit;

  ChecklistDetailCubit open() => ChecklistDetailCubit(
    checklistName: 'Start',
    checklistRepository: checklists,
    progressRepository: progress,
    flightSim: sim,
    settings: settings,
  )..load();

  setUp(() {
    clock = ManualClock();
    settings = FakeSettingsRepository();
    sim = FakeFlightSimRepository(clock: clock, settings: settings)
      ..setStatus(const ConnectionConnected());
    checklists = FakeChecklistRepository(
      current: const AircraftWorkflowParser().parse(_text),
    );
    progress = FakeChecklistProgressRepository();
    cubit = open();
  });

  tearDown(() async {
    await cubit.close();
    await sim.dispose();
    await checklists.dispose();
    await progress.dispose();
  });

  ChecklistDetailLoaded loaded() => cubit.state as ChecklistDetailLoaded;
  bool checked(int row) => loaded().rows[row].checked;

  Future<void> tick([int ms = 500]) async {
    clock.advance(Duration(milliseconds: ms));
    await pumpEventQueue();
  }

  void setValues(Map<String, double?> values) {
    for (final e in values.entries) {
      sim.signals.setValue(e.key, e.value);
    }
  }

  Future<void> tap(int row) async {
    cubit.toggle(row);
    await pumpEventQueue();
  }

  Future<void> flip(int row) async {
    cubit.toggleOption(row);
    await pumpEventQueue();
  }

  test('a new checklist has the block off: rows are disabled, total is 3', () {
    final rows = loaded().rows;
    expect(rows.map((r) => r.enabled), [true, true, false, false, true]);
    expect(rows[1].optionOn, isFalse);
    expect(loaded().total, 3);
  });

  test('turning the switch on enables the rows and raises the total', () async {
    await flip(1);
    expect(loaded().rows[1].optionOn, isTrue);
    expect(loaded().rows.map((r) => r.enabled), everyElement(isTrue));
    expect(loaded().total, 5);
    await flip(1);
    expect(loaded().total, 3);
  });

  test('a disabled item cannot be ticked', () async {
    await tap(2);
    expect(checked(2), isFalse);
    expect(progress.toggleCalls, isEmpty);
  });

  test('toggleOption ignores a row that is not a switch', () async {
    await flip(0);
    await flip(2);
    await flip(99);
    expect(loaded().rows[1].optionOn, isFalse);
    expect(loaded().total, 3);
  });

  test('turning the switch off clears the ticks of its items', () async {
    await flip(1);
    await tap(2);
    await tap(3);
    expect([checked(2), checked(3)], [true, true]);
    await flip(1);
    expect([checked(2), checked(3)], [false, false]);
    expect(loaded().done, 0);
  });

  test(
    'the checklist is complete without the block when the switch is off',
    () async {
      await tap(0);
      await tap(1);
      await tap(4);
      expect(loaded().isComplete, isTrue);
      await flip(1);
      expect(loaded().isComplete, isFalse);
    },
  );

  test('Check and Skip pass over the disabled items', () async {
    await tap(0);
    expect(loaded().pointer, 1, reason: 'the switch row is an item');
    await tap(1);
    expect(loaded().pointer, 4, reason: 'the GPU items are off');
    cubit.skipNext();
    await pumpEventQueue();
    expect(loaded().rows[4].skipped, isTrue);
    expect(loaded().rows[2].skipped, isFalse);
  });

  test('auto stops at the switch row and never ticks it', () async {
    setValues({'a/before': 1, 'a/gpu': 1, 'a/power': 1, 'a/after': 1});
    await tick();
    expect(
      [checked(0), checked(1), checked(2), checked(3), checked(4)],
      [true, false, false, false, false],
    );
    expect(loaded().pointer, 1);
    await flip(1);
    await tick();
    expect(checked(1), isFalse, reason: 'turning it on is not ticking it');
    expect(checked(2), isFalse);
  });

  test(
    'auto ticks around a block that is off once the switch is ticked',
    () async {
      setValues({'a/before': 1, 'a/gpu': 1, 'a/power': 1, 'a/after': 1});
      await tick();
      await tap(1);
      await tick();
      expect(
        [checked(0), checked(1), checked(2), checked(3), checked(4)],
        [true, true, false, false, true],
      );
    },
  );

  test('skipping the switch row passes it and leaves the block off', () async {
    await tap(0);
    cubit.skipNext();
    await pumpEventQueue();
    expect(loaded().rows[1].skipped, isTrue);
    expect(loaded().rows[1].optionOn, isFalse);
    expect(loaded().pointer, 4);
  });

  test('turning the switch on lets auto tick the block at once', () async {
    setValues({'a/before': 1, 'a/gpu': 1, 'a/power': 1, 'a/after': 1});
    await tick();
    await tap(1);
    await flip(1);
    await tick();
    expect([checked(2), checked(3)], [true, true]);
    expect(loaded().done, 5);
  });

  test('Reset clears the ticks and keeps the switch on', () async {
    await flip(1);
    await tap(2);
    cubit.reset();
    await pumpEventQueue();
    expect(loaded().rows[1].optionOn, isTrue);
    expect(checked(2), isFalse);
    expect(loaded().total, 5);
  });
}
