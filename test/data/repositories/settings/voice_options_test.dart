import 'package:flightsim_aide/data/repositories/settings/settings_repository_impl.dart';
import 'package:flightsim_aide/domain/models/settings/user_options.dart';
import 'package:flightsim_aide/domain/models/voice/voice_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../testing/fakes/services/in_memory_preferences_service.dart';

// The two voice options (D-84): off by default, kept, read back.
// AC-61

void main() {
  late InMemoryPreferencesService prefs;
  late SettingsRepositoryImpl repo;

  setUp(() {
    prefs = InMemoryPreferencesService();
    repo = SettingsRepositoryImpl(preferences: prefs);
  });

  test('both are off by default', () {
    expect(UserOptions.defaults.voice, const VoiceSettings());
    expect(repo.options.voice.flows, isFalse);
    expect(repo.options.voice.challenges, isFalse);
  });

  test('each is kept on its own key and read back', () async {
    await repo.update((o) => o.set(UserOptions.voiceFlowsOption, true));
    expect(prefs.values['voice_flows'], 'true');
    expect(repo.options.voice, const VoiceSettings(flows: true));
    await repo.update((o) => o.set(UserOptions.voiceChallengesOption, true));
    expect(prefs.values['voice_challenges'], 'true');

    final again = SettingsRepositoryImpl(preferences: prefs);
    await again.loadOptions();
    expect(
      again.options.voice,
      const VoiceSettings(flows: true, challenges: true),
    );
  });

  test('a corrupt stored value gives off', () async {
    prefs.values['voice_flows'] = 'maybe';
    await repo.loadOptions();
    expect(repo.options.voice.flows, isFalse);
  });

  test('turning one off again equals the defaults', () async {
    await repo.update((o) => o.set(UserOptions.voiceFlowsOption, true));
    await repo.update((o) => o.set(UserOptions.voiceFlowsOption, false));
    expect(repo.options, UserOptions.defaults);
  });

  test('speaksFor picks the setting of the row kind', () {
    const flows = VoiceSettings(flows: true);
    expect(flows.speaksFor(challenge: false), isTrue);
    expect(flows.speaksFor(challenge: true), isFalse);
  });
}
