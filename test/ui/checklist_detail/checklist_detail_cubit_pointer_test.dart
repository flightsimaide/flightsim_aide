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

// AC-33: auto ticks the item it is waiting on, in order (cubit half)
// AC-34: a manual tick against the dataref is warned about and marked red
// AC-35: the pointer follows the pilot's ticks, forward and back; an untick sticks

const _text = '''
sw_checklist:Start
sw_item:Gear|DOWN:a/gear:1
sw_item:Flaps|SET:a/flaps:1
sw_item:Rpm|UP:a/rpm:+>100
sw_item:Manual|DONE
sw_item:Light|ON:a/light:1
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

  group('auto ticks one step ahead of the pilot (AC-33)', () {
    test(
      'items already true tick in sequence on open, a false one stops',
      () async {
        cubit = open();
        setValues({'a/gear': 1, 'a/flaps': 1, 'a/rpm': 1000, 'a/light': 1});
        await tick();
        expect([checked(0), checked(1), checked(2)], [true, true, false]);
        expect(checked(4), isFalse, reason: 'light is true but rpm stops auto');
      },
    );

    test('a false first item ticks nothing', () async {
      cubit = open();
      setValues({'a/gear': 0, 'a/flaps': 1});
      await tick();
      expect(loaded().done, 0);
    });

    test('a flip ticks only the item auto is waiting on', () async {
      cubit = open();
      setValues({'a/gear': 1, 'a/flaps': 0});
      await tick();
      expect([checked(0), checked(1)], [true, false]);
      setValues({'a/flaps': 1});
      await tick();
      expect(checked(1), isTrue);
    });

    test(
      'an item that was true early ticks once the ones above are done',
      () async {
        cubit = open();
        setValues({'a/gear': 0, 'a/flaps': 1});
        await tick();
        expect(loaded().done, 0);
        setValues({'a/gear': 1});
        await tick();
        expect([checked(0), checked(1)], [true, true]);
      },
    );

    test('auto stops at a manual item until the pilot ticks it', () async {
      cubit = open();
      setValues({'a/gear': 1, 'a/flaps': 1, 'a/rpm': 1000, 'a/light': 1});
      await tick();
      setValues({'a/rpm': 1200});
      await tick();
      expect(checked(2), isTrue);
      expect(checked(3), isFalse, reason: 'manual');
      expect(checked(4), isFalse, reason: 'auto waits at the manual item');
      await tap(3);
      await tick();
      expect(checked(4), isTrue);
    });

    test(
      'a change condition takes its baseline when its item becomes the pointer',
      () async {
        cubit = open();
        setValues({'a/gear': 0, 'a/flaps': 0, 'a/rpm': 1000});
        await tick();
        setValues({
          'a/rpm': 5000,
        }); // moves a lot, but rpm is not the pointer yet
        await tick();
        setValues({
          'a/gear': 1,
          'a/flaps': 1,
        }); // rpm becomes the pointer at 5000
        await tick();
        expect(checked(2), isFalse, reason: '5000 is the baseline');
        setValues({'a/rpm': 5150});
        await tick();
        expect(checked(2), isTrue);
      },
    );
  });

  group('following the pilot (AC-35)', () {
    test('after a jump ahead the skipped item above is not ticked', () async {
      cubit = open();
      await tick();
      await tap(1); // the pilot ticks flaps; gear is skipped
      setValues({'a/gear': 1, 'a/flaps': 1});
      await tick();
      expect(checked(0), isFalse);
      expect(progress.current.cursorOf('Start'), greaterThanOrEqualTo(1));
    });

    test('backing up moves the pointer back to follow the pilot', () async {
      cubit = open();
      setValues({'a/gear': 1, 'a/flaps': 1, 'a/light': 0});
      await tick(); // gear and flaps tick, auto waits at rpm
      cubit.reset();
      await cubit.toggleAuto(); // reset switches to manual: turn auto back on
      await pumpEventQueue();
      await tick();
      await tap(3); // the pilot jumps to the manual item: gear and flaps behind
      await tick();
      expect(progress.current.cursorOf('Start'), 4, reason: 'waiting at light');
      await tap(0); // untick gear (auto switches to manual), then tick it again
      await tap(0);
      await tick();
      expect(checked(0), isTrue);
      expect(
        loaded().pointer,
        2,
        reason: 'the pointer followed the pilot back and is at rpm',
      );
    });

    test('ticking a skipped item makes auto resume just after it', () async {
      cubit = open();
      setValues({'a/gear': 0, 'a/flaps': 1, 'a/rpm': 1000, 'a/light': 0});
      await tick(); // gear is false: auto waits at the top
      await tap(3); // the pilot jumps ahead to the manual item
      expect(
        checked(1),
        isFalse,
        reason: 'flaps is true but behind the pointer',
      );
      await tap(0); // and goes back to gear: auto resumes after it, at flaps
      cubit.acknowledgeTick(); // the warning for gear is answered first
      await tick();
      expect(
        checked(1),
        isTrue,
        reason: 'flaps is true and now the pointer item',
      );
    });

    test(
      'an untick in auto switches to manual and backs the pointer up',
      () async {
        cubit = open();
        var notices = 0;
        final sub = cubit.manualNotices.listen((_) => notices++);
        addTearDown(sub.cancel);
        setValues({'a/gear': 1, 'a/flaps': 1, 'a/rpm': 1000});
        await tick();
        expect(loaded().auto, isTrue);
        await tap(1); // untick flaps while the sim still says it is set
        expect(checked(1), isFalse);
        await tick();
        await tick();
        expect(checked(1), isFalse, reason: 'manual: nothing ticks it again');
        expect(loaded().auto, isFalse);
        expect(progress.current.cursorOf('Start'), 1);
        expect(loaded().pointer, 1);
        expect(notices, 1);
        await tap(2); // an untick in manual mode gives no notice
        await tap(2);
        expect(notices, 1);
      },
    );

    test('Auto after an untick starts at the backed-up pointer', () async {
      cubit = open();
      setValues({'a/gear': 1, 'a/flaps': 1, 'a/rpm': 1000});
      await tick();
      await tap(1); // untick flaps: manual, pointer at flaps
      await cubit.toggleAuto(); // Auto again
      await pumpEventQueue();
      await tick();
      expect(checked(1), isTrue, reason: 'auto resumes at the pointer');
    });

    test('reset puts the pointer at the top again', () async {
      cubit = open();
      setValues({'a/gear': 1, 'a/flaps': 1, 'a/rpm': 1000});
      await tick();
      expect(progress.current.cursorOf('Start'), 2);
      setValues({'a/gear': 0});
      await tick();
      cubit.reset();
      await pumpEventQueue();
      expect(progress.current.cursorOf('Start'), 0);
      expect(loaded().done, 0);
      await cubit.toggleAuto(); // reset switched to manual
      setValues({'a/gear': 1});
      await tick();
      expect([checked(0), checked(1)], [true, true]);
    });
  });

  group('a manual tick against the dataref (AC-34)', () {
    late List<TickWarning> warnings;
    setUp(() => warnings = []);

    Future<void> openAndListen() async {
      cubit = open();
      cubit.tickWarnings.listen(warnings.add);
    }

    test(
      'a false condition warns once, keeps the tick and marks it red',
      () async {
        await openAndListen();
        setValues({'a/gear': 0});
        await tick();
        await tap(0);
        await pumpEventQueue();
        expect(warnings, hasLength(1));
        expect(warnings.single.index, 0);
        expect(warnings.single.label, 'Gear');
        expect(checked(0), isTrue);
        expect(loaded().rows[0].disagreed, isTrue);
        expect(progress.current.isDisagreed('Start', 0), isTrue);
      },
    );

    test('a true condition does not warn', () async {
      await openAndListen();
      setValues({'a/gear': 0, 'a/flaps': 1});
      await tick();
      await tap(1);
      expect(warnings, isEmpty);
      expect(loaded().rows[1].disagreed, isFalse);
    });

    test('an unknown value does not warn', () async {
      await openAndListen();
      await tick();
      await tap(0);
      expect(warnings, isEmpty);
    });

    test('an item with no condition does not warn', () async {
      await openAndListen();
      setValues({'a/gear': 1});
      await tick();
      await tap(3);
      expect(warnings, isEmpty);
    });

    test('unticking does not warn and removes the red mark', () async {
      await openAndListen();
      setValues({'a/gear': 0});
      await tick();
      await tap(0);
      expect(warnings, hasLength(1));
      await tap(0);
      expect(warnings, hasLength(1));
      expect(loaded().rows[0].disagreed, isFalse);
    });

    test('with the link down nothing is known, so no warning', () async {
      await openAndListen();
      setValues({'a/gear': 0});
      await tick();
      sim.setStatus(const ConnectionSimUnreachable());
      await tick();
      await tap(0);
      expect(warnings, isEmpty);
    });

    test('a change condition with no baseline yet does not warn', () async {
      await openAndListen();
      setValues({'a/gear': 0, 'a/rpm': 1000});
      await tick();
      await tap(2);
      expect(warnings, isEmpty);
    });

    test('the warning stream closes with the cubit', () async {
      await openAndListen();
      var done = false;
      cubit.tickWarnings.listen((_) {}, onDone: () => done = true);
      await cubit.close();
      await pumpEventQueue();
      expect(done, isTrue);
      cubit = open(); // so tearDown has something to close
    });
  });

  group('the Check button ticks the pointer item', () {
    test(
      'the pointer is the first unchecked item at or after the cursor',
      () async {
        cubit = open();
        expect(loaded().pointer, 0);
        await tap(2);
        expect(
          loaded().pointer,
          3,
          reason: 'item 0 and 1 stay behind the cursor',
        );
        await tap(3);
        await tap(4);
        expect(loaded().pointer, isNull);
      },
    );

    test('checkNext ticks the pointer item and moves on', () async {
      cubit = open();
      cubit.checkNext();
      await pumpEventQueue();
      expect([checked(0), checked(1)], [true, false]);
      expect(loaded().pointer, 1);
      cubit.checkNext();
      await pumpEventQueue();
      expect([checked(0), checked(1), checked(2)], [true, true, false]);
    });

    test('it works in manual mode, from the top after a reset', () async {
      cubit = open();
      setValues({'a/gear': 1});
      await tick();
      cubit.reset();
      await tick();
      expect(loaded().auto, isFalse);
      expect(loaded().pointer, 0);
      cubit.checkNext();
      await pumpEventQueue();
      expect(checked(0), isTrue);
      expect(loaded().pointer, 1);
    });

    test('it follows a manual tick forward', () async {
      cubit = open();
      await cubit.toggleAuto();
      await tap(2);
      cubit.checkNext();
      await pumpEventQueue();
      expect([checked(2), checked(3), checked(1)], [true, true, false]);
    });

    test('with nothing left it does nothing', () async {
      cubit = open();
      for (var i = 0; i < 5; i++) {
        cubit.checkNext();
      }
      await pumpEventQueue();
      expect(loaded().done, 5);
      expect(loaded().pointer, isNull);
      cubit.checkNext();
      await pumpEventQueue();
      expect(loaded().done, 5);
    });

    test('it warns like a tap when the sim says the item is not set', () async {
      cubit = open();
      final warnings = <TickWarning>[];
      cubit.tickWarnings.listen(warnings.add);
      setValues({'a/gear': 0});
      await tick();
      cubit.checkNext();
      await pumpEventQueue();
      expect(checked(0), isTrue);
      expect(warnings.map((w) => w.index), [0]);
    });
  });

  group('backing out of a warned tick', () {
    Future<TickWarning> tickGear() async {
      final warnings = <TickWarning>[];
      cubit.tickWarnings.listen(warnings.add);
      setValues({'a/gear': 0});
      await tick();
      await tap(0);
      expect(warnings, hasLength(1));
      return warnings.single;
    }

    test('cancelling unticks the item and removes the red mark', () async {
      cubit = open();
      final warning = await tickGear();
      cubit.cancelTick(warning);
      await pumpEventQueue();
      expect(checked(0), isFalse);
      expect(loaded().rows[0].disagreed, isFalse);
      expect(loaded().pointer, 0);
    });

    test('auto still ticks the item once the sim says it is set', () async {
      cubit = open();
      final warning = await tickGear();
      cubit.cancelTick(warning);
      await tick();
      expect(checked(0), isFalse);
      setValues({'a/gear': 1});
      await tick();
      expect(checked(0), isTrue);
      expect(loaded().rows[0].autoChecked, isTrue);
    });

    test(
      'auto waits while the warning is open and ticks nothing below',
      () async {
        cubit = open();
        final warning = await tickGear();
        setValues({'a/flaps': 1, 'a/rpm': 1000});
        await tick();
        expect(
          checked(1),
          isFalse,
          reason: 'flaps is met but the dialog is open',
        );
        expect(checked(2), isFalse);
        cubit.cancelTick(warning);
        await tick();
        expect(checked(0), isFalse);
        expect(checked(1), isFalse, reason: 'auto waits on gear again');
        expect(loaded().pointer, 0);
      },
    );

    test('acknowledging lets auto carry on below the red item', () async {
      cubit = open();
      await tickGear();
      setValues({'a/flaps': 1});
      await tick();
      expect(checked(1), isFalse);
      cubit.acknowledgeTick();
      await tick();
      expect(checked(0), isTrue);
      expect(checked(1), isTrue);
    });
  });
}
