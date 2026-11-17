import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/data/repositories/settings/settings_repository.dart';
import 'package:flightsim_aide/data/repositories/voice/voice_repository.dart';
import 'package:flightsim_aide/domain/models/settings/user_options.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_detail_screen.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/voice_controls.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../../testing/fakes/repositories/fake_checklist_repository.dart';
import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/repositories/fake_voice_repository.dart';

// The Pause button, the flashing PAUSED chip and the spoken answer on the
// screen (D-84).
// AC-64

void main() {
  late FakeChecklistProgressRepository progress;
  late FakeSettingsRepository settings;
  late FakeVoiceRepository voice;

  Future<void> pump(
    WidgetTester tester, {
    bool voiceOn = true,
    bool withVoice = true,
    bool micAvailable = true,
    bool disableAnimations = false,
  }) async {
    final document = const AircraftWorkflowParser().parse(
      'sw_checklist:A\nsw_item:Parking brake|SET\nsw_item:Flaps|SET',
    );
    progress = FakeChecklistProgressRepository();
    settings = FakeSettingsRepository();
    await settings.update((o) => o.set(UserOptions.voiceFlowsOption, voiceOn));
    voice = FakeVoiceRepository()..micAvailable = micAvailable;
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ChecklistRepository>.value(
            value: FakeChecklistRepository(current: document),
          ),
          RepositoryProvider<ChecklistProgressRepository>.value(
            value: progress,
          ),
          RepositoryProvider<SettingsRepository>.value(value: settings),
          if (withVoice)
            RepositoryProvider<VoiceRepository>.value(value: voice),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: const ChecklistDetailScreen(checklistName: 'A'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('with no voice in the app there are no voice controls', (
    tester,
  ) async {
    await pump(tester, withVoice: false);
    expect(find.byKey(voicePauseButtonKey), findsNothing);
  });

  testWidgets('with both switches off there are no voice controls', (
    tester,
  ) async {
    await pump(tester, voiceOn: false);
    expect(find.byKey(voicePauseButtonKey), findsNothing);
    expect(voice.said, isEmpty);
  });

  testWidgets('with the voice on the screen reads the first item', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(voicePauseButtonKey), findsOneWidget);
    expect(find.byKey(voicePausedChipKey), findsNothing);
    expect(voice.texts, ['Parking brake, SET']);
  });

  testWidgets('Pause flashes PAUSED with an icon and Resume clears it', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(voicePauseButtonKey));
    await tester.pump();
    expect(find.byKey(voicePausedChipKey), findsOneWidget);
    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle), findsOneWidget);
    // The chip flashes: its opacity changes with time.
    FadeTransition fade() => tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byKey(voicePausedChipKey),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    final first = fade().opacity.value;
    await tester.pump(const Duration(milliseconds: 350));
    expect(fade().opacity.value, isNot(first));

    await tester.tap(find.byKey(voicePauseButtonKey));
    await tester.pump();
    expect(find.byKey(voicePausedChipKey), findsNothing);
    expect(voice.texts.last, 'Parking brake, SET');
  });

  testWidgets('the flash stops when animations are off, the word stays', (
    tester,
  ) async {
    await pump(tester, disableAnimations: true);
    await tester.tap(find.byKey(voicePauseButtonKey));
    await tester.pump();
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byKey(voicePausedChipKey),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, 1);
    await tester.pump(const Duration(milliseconds: 350));
    expect(fade.opacity.value, 1);
    expect(find.text('PAUSED'), findsOneWidget);
  });

  testWidgets('a spoken answer ticks the item, like a tap', (tester) async {
    await pump(tester);
    voice.hear('set');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(progress.current.isChecked('A', 0), isTrue);
    expect(voice.texts.last, 'Flaps, SET');
  });

  testWidgets('a spoken skip skips the item', (tester) async {
    await pump(tester);
    voice.hear('skip');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(progress.current.isSkipped('A', 0), isTrue);
  });

  testWidgets('no microphone shows an icon and the voice still speaks', (
    tester,
  ) async {
    await pump(tester, micAvailable: false);
    expect(find.byKey(voiceMicOffKey), findsOneWidget);
    expect(voice.texts, ['Parking brake, SET']);
  });
}
