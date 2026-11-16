import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/calculated_value.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/ui/checklist_detail/cubit/checklist_detail_cubit.dart';
import 'package:flightsim_aide/ui/checklist_detail/cubit/checklist_detail_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../../testing/fakes/repositories/fake_checklist_repository.dart';
import '../../../testing/fakes/repositories/fake_flight_sim_repository.dart';
import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/services/manual_clock.dart';

// AC-56: the live value of a sw_calculate line reaches the row, and its input
// datarefs are watched while the checklist is open.

const _text = '''
sw_checklist:Cruise
sw_item:Power|SET
sw_calculate:t|y|Torque|psi|0.1
sw_item:Other|OK
sw_table:t|x=a/x|y
sw_row:0|0
sw_row:10|100
sw_table_end
''';

void main() {
  late FakeChecklistRepository checklists;
  late FakeChecklistProgressRepository progress;
  late FakeFlightSimRepository sim;
  late FakeSettingsRepository settings;
  late ManualClock clock;
  late ChecklistDetailCubit cubit;

  setUp(() {
    clock = ManualClock();
    settings = FakeSettingsRepository();
    sim = FakeFlightSimRepository(clock: clock, settings: settings)
      ..setStatus(const ConnectionConnected());
    checklists = FakeChecklistRepository(
      current: const AircraftWorkflowParser().parse(_text),
    );
    progress = FakeChecklistProgressRepository();
    cubit = ChecklistDetailCubit(
      checklistName: 'Cruise',
      checklistRepository: checklists,
      progressRepository: progress,
      flightSim: sim,
      settings: settings,
    )..load();
  });

  tearDown(() async {
    await cubit.close();
    await sim.dispose();
    await checklists.dispose();
    await progress.dispose();
  });

  List<CalculatedValue> power() =>
      (cubit.state as ChecklistDetailLoaded).rows[0].calculated;

  Future<void> tick() async {
    clock.advance(const Duration(milliseconds: 500));
    await pumpEventQueue();
  }

  test('watches the inputs of the table', () {
    expect(sim.signals.watchCalls.last.keys, ['a/x']);
  });

  test('a row with no calculation has no values', () {
    expect((cubit.state as ChecklistDetailLoaded).rows[1].calculated, isEmpty);
  });

  test('has no value until the sim gives the input', () async {
    expect(power(), [const CalculatedValue.unavailable()]);
  });

  test('shows the value and follows the input', () async {
    sim.signals.setValue('a/x', 5);
    await tick();
    expect(power(), [const CalculatedValue(50)]);
    sim.signals.setValue('a/x', 7.04);
    await tick();
    expect(power(), [const CalculatedValue(70.4)]);
  });

  test('says when the input is beyond the table', () async {
    sim.signals.setValue('a/x', 20);
    await tick();
    expect(power(), [
      const CalculatedValue(
        100,
        limits: [LimitExceeded(name: 'x', actual: 20, limit: 10, above: true)],
      ),
    ]);
  });

  test('a change smaller than the step emits nothing new', () async {
    sim.signals.setValue('a/x', 5);
    await tick();
    final states = <Object>[];
    final sub = cubit.stream.listen(states.add);
    sim.signals.setValue('a/x', 5.01); // 50.1 rounds to 50.1, so it changes
    await tick();
    sim.signals.setValue('a/x', 5.011); // 50.11 rounds to 50.1 again
    await tick();
    await sub.cancel();
    expect(states, hasLength(1));
  });

  test(
    'has no value while the link is down, and again when it returns',
    () async {
      sim.signals.setValue('a/x', 5);
      await tick();
      expect(power(), [const CalculatedValue(50)]);
      sim.setStatus(const ConnectionSimUnreachable());
      await tick();
      expect(power(), [const CalculatedValue.unavailable()]);
      sim.setStatus(const ConnectionConnected());
      await tick();
      expect(power(), [const CalculatedValue(50)]);
    },
  );
}
