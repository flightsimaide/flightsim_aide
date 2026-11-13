import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/ui/checklist_detail/cubit/checklist_detail_cubit.dart';
import 'package:flightsim_aide/ui/checklist_detail/cubit/checklist_detail_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../../testing/fakes/repositories/fake_checklist_repository.dart';
import '../../../testing/fakes/repositories/fake_settings_repository.dart';

// Task 0.24: Skip, and the saved Auto/Manual choice

const _text = '''
sw_checklist:Start
sw_item_heading:Head|left
sw_item:One|A
sw_item:Two|B
sw_item:Three|C
''';

void main() {
  late FakeChecklistRepository checklists;
  late FakeChecklistProgressRepository progress;
  late ChecklistDetailCubit cubit;

  setUp(() {
    checklists = FakeChecklistRepository(
      current: const AircraftWorkflowParser().parse(_text),
    );
    progress = FakeChecklistProgressRepository();
    cubit = ChecklistDetailCubit(
      checklistName: 'Start',
      checklistRepository: checklists,
      progressRepository: progress,
    )..load();
  });

  tearDown(() async {
    await cubit.close();
    await checklists.dispose();
    await progress.dispose();
  });

  ChecklistDetailLoaded loaded() => cubit.state as ChecklistDetailLoaded;
  List<int> skippedRows() => [
    for (final r in loaded().rows)
      if (r.skipped) r.index,
  ];
  int firstCheckRow() => loaded().rows.indexWhere((r) => r.item.label == 'One');

  test('skipNext skips the first open check item, never a note', () async {
    final first = firstCheckRow();
    cubit.skipNext();
    await pumpEventQueue();
    expect(skippedRows(), [first]);
    cubit.skipNext();
    await pumpEventQueue();
    expect(skippedRows(), [first, first + 1]);
    expect(loaded().skipped, 2);
  });

  test('skip passes a checked item; tapping a skipped row checks it', () async {
    final first = firstCheckRow();
    cubit.toggle(first);
    cubit.skipNext();
    await pumpEventQueue();
    expect(skippedRows(), [first + 1]);
    cubit.toggle(first + 1);
    await pumpEventQueue();
    expect(skippedRows(), isEmpty);
    expect(loaded().done, 2);
  });

  test(
    'canSkip goes false and the list completes when all are passed',
    () async {
      expect(loaded().canSkip, isTrue);
      for (var i = 0; i < 3; i++) {
        cubit.skipNext();
      }
      await pumpEventQueue();
      expect(loaded().canSkip, isFalse);
      expect(loaded().isComplete, isTrue);
      expect(loaded().done, 0);
      expect(loaded().skipped, 3);
    },
  );

  test('the pointer moves past skipped items', () async {
    cubit.skipNext();
    await pumpEventQueue();
    expect(loaded().pointer, firstCheckRow() + 1);
    cubit.checkNext();
    await pumpEventQueue();
    expect(loaded().done, 1);
    expect(skippedRows(), [firstCheckRow()]);
  });

  test(
    'after a tick lower in the list, Skip takes the item below it',
    () async {
      final first = firstCheckRow();
      cubit.toggle(first + 1);
      cubit.skipNext();
      await pumpEventQueue();
      expect(skippedRows(), [
        first + 2,
      ], reason: 'not the open item at the top');
      expect(loaded().pointer, isNull, reason: 'the pointer is below the list');
    },
  );

  test('reset clears skipped items', () async {
    cubit.skipNext();
    cubit.reset();
    await pumpEventQueue();
    expect(loaded().skipped, 0);
  });

  group('Auto/Manual is the user choice, kept in the settings', () {
    late FakeSettingsRepository settings;
    late ChecklistDetailCubit withSettings;

    ChecklistDetailCubit open() => ChecklistDetailCubit(
      checklistName: 'Start',
      checklistRepository: checklists,
      progressRepository: progress,
      settings: settings,
    )..load();

    setUp(() => settings = FakeSettingsRepository());
    tearDown(() => withSettings.close());

    test('the button saves the choice and a new screen keeps it', () async {
      withSettings = open();
      await withSettings.toggleAuto();
      expect(settings.options.autoMode, isFalse);
      expect((withSettings.state as ChecklistDetailLoaded).auto, isFalse);
      await withSettings.close();
      withSettings = open();
      expect((withSettings.state as ChecklistDetailLoaded).auto, isFalse);
      await withSettings.toggleAuto();
      expect(settings.options.autoMode, isTrue);
    });

    test('Reset goes manual for the session and saves nothing', () async {
      withSettings = open();
      withSettings.reset();
      expect(settings.options.autoMode, isTrue, reason: 'the choice is kept');
      expect(progress.isManual('Start'), isTrue);
      expect((withSettings.state as ChecklistDetailLoaded).auto, isFalse);
    });

    test('the button after Reset ends the override and goes to auto', () async {
      withSettings = open();
      withSettings.reset();
      await withSettings.toggleAuto();
      expect(progress.isManual('Start'), isFalse);
      expect(settings.options.autoMode, isTrue);
      expect((withSettings.state as ChecklistDetailLoaded).auto, isTrue);
    });

    test('another checklist is not affected by Reset in this one', () async {
      withSettings = open();
      withSettings.reset();
      expect(progress.isManual('Other'), isFalse);
    });
  });
}
