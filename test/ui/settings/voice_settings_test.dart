import 'package:bloc_test/bloc_test.dart';
import 'package:flightsim_aide/data/repositories/settings/settings_repository.dart';
import 'package:flightsim_aide/domain/models/settings/user_options.dart';
import 'package:flightsim_aide/domain/models/voice/voice_settings.dart';
import 'package:flightsim_aide/ui/settings/cubit/voice_settings_cubit.dart';
import 'package:flightsim_aide/ui/settings/widgets/voice_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_settings_repository.dart';

// The Voice page and its cubit (D-84).
// AC-61

void main() {
  late FakeSettingsRepository settings;

  setUp(() => settings = FakeSettingsRepository());

  group('VoiceSettingsCubit', () {
    test('starts from the saved options', () async {
      expect(
        VoiceSettingsCubit(settings: settings).state,
        const VoiceSettings(),
      );
    });

    blocTest<VoiceSettingsCubit, VoiceSettings>(
      'turning each on is kept and emitted',
      build: () => VoiceSettingsCubit(settings: settings),
      act: (c) async {
        await c.setFlows(true);
        await c.setChallenges(true);
      },
      expect: () => [
        const VoiceSettings(flows: true),
        const VoiceSettings(flows: true, challenges: true),
      ],
      verify: (_) => expect(
        settings.options.voice,
        const VoiceSettings(flows: true, challenges: true),
      ),
    );

    blocTest<VoiceSettingsCubit, VoiceSettings>(
      'follows a change made elsewhere',
      build: () => VoiceSettingsCubit(settings: settings),
      act: (_) =>
          settings.update((o) => o.set(UserOptions.voiceFlowsOption, true)),
      expect: () => [const VoiceSettings(flows: true)],
    );
  });

  group('the Voice page', () {
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: RepositoryProvider<SettingsRepository>.value(
          value: settings,
          child: const VoiceSettingsScreen(),
        ),
      ),
    );

    testWidgets('shows both switches off', (tester) async {
      await pump(tester);
      final flows = tester.widget<SwitchListTile>(
        find.byKey(const Key('voice-flows')),
      );
      final challenges = tester.widget<SwitchListTile>(
        find.byKey(const Key('voice-challenges')),
      );
      expect(flows.value, isFalse);
      expect(challenges.value, isFalse);
    });

    testWidgets('a tap turns one on and keeps it', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('voice-challenges')));
      await tester.pump();
      expect(settings.options.voice, const VoiceSettings(challenges: true));
      final challenges = tester.widget<SwitchListTile>(
        find.byKey(const Key('voice-challenges')),
      );
      expect(challenges.value, isTrue);
      final flows = tester.widget<SwitchListTile>(
        find.byKey(const Key('voice-flows')),
      );
      expect(flows.value, isFalse);
    });
  });
}
