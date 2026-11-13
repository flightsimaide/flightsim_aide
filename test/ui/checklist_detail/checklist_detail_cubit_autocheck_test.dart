import 'dart:async';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/ui/checklist_detail/cubit/checklist_detail_cubit.dart';
import 'package:flightsim_aide/ui/checklist_detail/cubit/checklist_detail_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../../testing/fakes/repositories/fake_checklist_repository.dart';
import '../../../testing/fakes/repositories/fake_flight_sim_repository.dart';
import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/services/manual_clock.dart';

// AC-33: opening a checklist watches exactly the names its conditions need, closing releases them
// AC-34: a met condition checks the item, a change condition uses the baseline from the first frame
// AC-35: a manual uncheck is not undone (cubit half)
// AC-36: nothing is applied while the link is down; evaluation resumes from the current values
// AC-38: the continue result, auto-continue once per completion

const _text = '''
sw_checklist:Start
sw_item:Gear|DOWN:a/gear:1
sw_item:Flaps|SET:a/flaps:>0.5
sw_item:Rpm|UP:a/rpm:+>100
sw_item:Manual|DONE
sw_continue:Taxi:a/ready:1
sw_continue:Alt
sw_checklist:Taxi
sw_item:Light|ON:a/light:1&&a/gear:1
sw_checklist:Alt
sw_item:Other|OK
''';

void main() {
  late FakeChecklistRepository checklists;
  late FakeChecklistProgressRepository progress;
  late FakeFlightSimRepository sim;
  late FakeSettingsRepository settings;
  late ManualClock clock;
  late ChecklistDetailCubit cubit;

  ChecklistDetailCubit open(String name) => ChecklistDetailCubit(
    checklistName: name,
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

  Future<void> tick([int ms = 500]) async {
    clock.advance(Duration(milliseconds: ms));
    await pumpEventQueue();
  }

  void setValues(Map<String, double?> values) {
    for (final e in values.entries) {
      sim.signals.setValue(e.key, e.value);
    }
  }

  group('open, watch, release (AC-33)', () {
    test('opening watches the names of the checklist, each once', () async {
      cubit = open('Start');
      expect(sim.signals.watchCalls.last.keys, [
        'a/gear',
        'a/flaps',
        'a/rpm',
        'a/ready',
      ]);
    });

    test('a checklist with no conditions subscribes nothing', () async {
      cubit = open('Alt');
      expect(sim.signals.watchCalls, isEmpty);
    });

    test('closing releases the names after the delay', () async {
      cubit = open('Start');
      await cubit.close();
      clock.advance(const Duration(seconds: 3));
      expect(sim.signals.watchCalls.last, isEmpty);
      cubit = open('Alt'); // so tearDown has something to close
    });

    test('a second checklist sharing a name does not resubscribe it', () async {
      cubit = open('Start');
      final calls = sim.signals.watchCalls.length;
      final other = open('Taxi');
      // Taxi needs a/light (new) and a/gear (shared): one more call, and the
      // shared name is in it once.
      expect(sim.signals.watchCalls.length, calls + 1);
      expect(sim.signals.watchCalls.last.keys.toSet(), {
        'a/gear',
        'a/flaps',
        'a/rpm',
        'a/ready',
        'a/light',
      });
      unawaited(other.close());
    });

    test('without a flight sim nothing is watched or checked', () async {
      cubit = ChecklistDetailCubit(
        checklistName: 'Start',
        checklistRepository: checklists,
        progressRepository: progress,
      )..load();
      expect(loaded().rows.any((r) => r.checked), isFalse);
    });
  });

  group('apply results (AC-34)', () {
    test('a met value checks the item and marks it automatic', () async {
      cubit = open('Start');
      setValues({'a/gear': 1});
      await tick();
      final row = loaded().rows[0];
      expect(row.checked, isTrue);
      expect(row.autoChecked, isTrue);
      expect(loaded().done, 1);
      expect(loaded().rows[1].checked, isFalse);
    });

    test('a not-met value checks nothing', () async {
      cubit = open('Start');
      setValues({'a/gear': 0, 'a/flaps': 0.2});
      await tick();
      expect(loaded().done, 0);
    });

    test('a change condition takes its baseline when its item is the pointer', () async {
      cubit = open('Start');
      // Gear and flaps are true, so rpm is the pointer item on the first frame.
      setValues({'a/gear': 1, 'a/flaps': 1, 'a/rpm': 1000});
      await tick();
      expect(loaded().rows[2].checked, isFalse); // baseline only
      setValues({'a/rpm': 1050});
      await tick();
      expect(loaded().rows[2].checked, isFalse);
      setValues({'a/rpm': 1150});
      await tick();
      expect(loaded().rows[2].checked, isTrue);
    });

    test('a manual uncheck sticks (AC-35)', () async {
      cubit = open('Start');
      setValues({'a/gear': 1});
      await tick();
      cubit.toggle(0);
      await pumpEventQueue();
      expect(loaded().rows[0].checked, isFalse);
      await tick();
      await tick();
      expect(loaded().rows[0].checked, isFalse);
    });

    test('a manual item with no condition is left alone', () async {
      cubit = open('Start');
      setValues({'a/gear': 1, 'a/flaps': 1, 'a/rpm': 5});
      await tick();
      expect(loaded().rows[3].checked, isFalse);
    });

    test('auto is on when a checklist opens', () async {
      cubit = open('Start');
      expect(loaded().auto, isTrue);
      expect(loaded().resets, 0);
    });

    test('reset clears the ticks and switches to manual', () async {
      cubit = open('Start');
      setValues({'a/gear': 1});
      await tick();
      expect(loaded().done, 1);
      cubit.reset();
      await pumpEventQueue();
      expect(loaded().done, 0);
      expect(loaded().auto, isFalse);
      expect(loaded().resets, 1);
    });

    test('after a reset the met values are not ticked again', () async {
      cubit = open('Start');
      setValues({'a/gear': 1});
      await tick();
      cubit.reset();
      await tick();
      setValues({'a/gear': 1, 'a/flaps': 1});
      await tick();
      expect(loaded().done, 0);
    });

    test('manual ticks still work in manual mode', () async {
      cubit = open('Start');
      cubit.reset();
      cubit.toggle(0);
      await pumpEventQueue();
      expect(loaded().rows[0].checked, isTrue);
    });

    test('switching back to auto checks what is met', () async {
      cubit = open('Start');
      setValues({'a/gear': 1});
      await tick();
      cubit.reset();
      await tick();
      expect(loaded().done, 0);
      await cubit.toggleAuto();
      await tick();
      expect(loaded().auto, isTrue);
      expect(loaded().rows[0].checked, isTrue);
    });

    test('toggleAuto flips the mode both ways', () async {
      cubit = open('Start');
      await cubit.toggleAuto();
      expect(loaded().auto, isFalse);
      await cubit.toggleAuto();
      expect(loaded().auto, isTrue);
    });

    test('leaving the page ends the manual mode set by Reset', () async {
      cubit = open('Start');
      setValues({'a/gear': 1});
      await tick();
      cubit.reset();
      await tick();
      expect(loaded().auto, isFalse);
      await cubit.close();

      cubit = open('Start');
      expect(loaded().auto, isTrue);
    });

    test('the mode belongs to one checklist', () async {
      cubit = open('Start');
      cubit.reset();
      await cubit.close();
      cubit = open('Taxi');
      expect(loaded().auto, isTrue);
    });

    test(
      'loading another aircraft puts every checklist back to auto',
      () async {
        cubit = open('Start');
        cubit.reset();
        await cubit.close();
        await progress.attach(
          checklists.current!,
          aircraft: const AircraftIdentity(
            aircraftPath: 'other.acf',
            icao: 'C172',
            description: 'Cessna',
          ),
        );
        cubit = open('Start');
        expect(loaded().auto, isTrue);
      },
    );
  });

  group('stale and lost (AC-36)', () {
    test('nothing is applied while not connected; marks stay', () async {
      cubit = open('Start');
      setValues({'a/gear': 1});
      await tick();
      expect(loaded().done, 1);
      sim.setStatus(const ConnectionSimUnreachable());
      setValues({'a/flaps': 1});
      await tick();
      await tick();
      expect(loaded().rows[1].checked, isFalse);
      expect(loaded().rows[0].checked, isTrue);
    });

    test('on recovery evaluation resumes from the current values', () async {
      cubit = open('Start');
      sim.setStatus(const ConnectionSimUnreachable());
      setValues({'a/gear': 1, 'a/flaps': 1});
      await tick();
      expect(loaded().done, 0);
      sim.setStatus(const ConnectionConnected());
      await tick();
      expect(loaded().rows[0].checked, isTrue);
      expect(loaded().rows[1].checked, isTrue);
    });

    test(
      'a lost stream makes the values unknown, so nothing is checked',
      () async {
        cubit = open('Start');
        setValues({'a/gear': 1});
        sim.signals.setConnected(false);
        await tick();
        expect(loaded().done, 0);
      },
    );
  });

  group('continue (AC-38)', () {
    Future<void> completeAll() async {
      setValues({'a/gear': 1, 'a/flaps': 1, 'a/rpm': 0, 'a/ready': 0});
      await tick();
      setValues({'a/rpm': 500});
      await tick();
      cubit.toggle(3);
      await pumpEventQueue();
    }

    test('no continue result before the checklist is complete', () async {
      cubit = open('Start');
      setValues({'a/ready': 1});
      await tick();
      expect(loaded().continueTo, isNull);
    });

    test('the first matching link wins when complete', () async {
      cubit = open('Start');
      await completeAll();
      setValues({'a/ready': 1});
      await tick();
      expect(loaded().isComplete, isTrue);
      expect(loaded().continueTo?.name, 'Taxi');
    });

    test(
      'with the first condition not met the bare link is followed',
      () async {
        cubit = open('Start');
        await completeAll();
        await tick();
        expect(loaded().continueTo?.name, 'Alt');
      },
    );

    test('unchecking an item drops the continue result', () async {
      cubit = open('Start');
      await completeAll();
      await tick();
      expect(loaded().continueTo, isNotNull);
      cubit.toggle(3);
      await pumpEventQueue();
      expect(loaded().continueTo, isNull);
    });

    test('opened already complete: the continue result is there', () async {
      for (var i = 0; i < 4; i++) {
        progress.toggle('Start', i);
      }
      cubit = open('Start');
      await tick();
      await pumpEventQueue();
      expect(loaded().continueTo?.name, 'Alt');
    });
  });

  group('items that stay manual (7.9)', () {
    test('a rejected name counts the items that need it', () async {
      sim.signals.reject('a/gear');
      cubit = open('Start');
      await tick();
      expect(loaded().stayManual, 1);
    });

    test('nothing rejected, nothing counted', () async {
      cubit = open('Start');
      await tick();
      expect(loaded().stayManual, 0);
    });
  });
}
