import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/settings/user_options.dart';
import 'package:flightsim_aide/ui/checklist_detail/cubit/voice_session_cubit.dart';
import 'package:flightsim_aide/ui/checklist_detail/cubit/voice_session_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../../testing/fakes/repositories/fake_checklist_repository.dart';
import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/repositories/fake_voice_repository.dart';

// The voice session of an open checklist (D-84).
// AC-63

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeChecklistProgressRepository progress;
  late FakeSettingsRepository settings;
  late FakeVoiceRepository voice;
  late int checks;
  late int skips;
  late VoiceSessionCubit cubit;

  const flowFile =
      'sw_checklist:A\nsw_item:Parking brake|SET\nsw_item:Flaps|SET\n'
      'sw_item:Lights|ON';
  const challengeFile =
      'sw_checklist:A\nsw_challenge: ON\nsw_item:Beacon|ON\n'
      'sw_item:Strobes|ON\nsw_item:Nav|ON\nsw_item:Taxi|ON\nsw_item:Flaps|SET\n'
      'sw_challenge: OFF';

  Future<void> open(
    String file, {
    bool flows = true,
    bool challenges = true,
  }) async {
    final document = const AircraftWorkflowParser().parse(file);
    progress = FakeChecklistProgressRepository();
    settings = FakeSettingsRepository();
    await settings.update(
      (o) => o
          .set(UserOptions.voiceFlowsOption, flows)
          .set(UserOptions.voiceChallengesOption, challenges),
    );
    voice = FakeVoiceRepository();
    checks = 0;
    skips = 0;
    cubit = VoiceSessionCubit(
      checklistName: 'A',
      checklistRepository: FakeChecklistRepository(current: document),
      progressRepository: progress,
      settings: settings,
      voice: voice,
      checkNext: () => checks++,
      skipNext: () => skips++,
    )..load();
    await settle();
  }

  tearDown(() => cubit.close());

  group('opening', () {
    test('with both switches off it is silent and does not listen', () async {
      await open(flowFile, flows: false, challenges: false);
      expect(cubit.state, const VoiceSessionState());
      expect(voice.said, isEmpty);
      expect(voice.isListening, isFalse);
    });

    test('with a switch on it listens and reads the first item', () async {
      await open(flowFile);
      expect(cubit.state.active, isTrue);
      expect(cubit.state.listening, isTrue);
      expect(voice.texts, ['Parking brake']);
    });

    test('with no microphone it still speaks', () async {
      voice = FakeVoiceRepository()..micAvailable = false;
      final document = const AircraftWorkflowParser().parse(flowFile);
      progress = FakeChecklistProgressRepository();
      settings = FakeSettingsRepository();
      await settings.update((o) => o.set(UserOptions.voiceFlowsOption, true));
      cubit = VoiceSessionCubit(
        checklistName: 'A',
        checklistRepository: FakeChecklistRepository(current: document),
        progressRepository: progress,
        settings: settings,
        voice: voice,
        checkNext: () {},
        skipNext: () {},
      )..load();
      await settle();
      expect(cubit.state.micUnavailable, isTrue);
      expect(cubit.state.listening, isFalse);
      expect(voice.texts, ['Parking brake']);
    });
  });

  group('the ready question', () {
    test(
      'a challenge checklist in auto mode asks and reads nothing else',
      () async {
        await open(challengeFile);
        expect(voice.texts, ['Ready for a checklist?']);
        voice.hear('on');
        voice.hear('skip');
        await settle();
        expect(checks + skips, 0);
        expect(voice.texts, ['Ready for a checklist?']);
      },
    );

    test('yes, ready and okay start it', () async {
      for (final word in ['yes', 'ready', 'okay']) {
        await open(challengeFile);
        voice.hear(word);
        await settle();
        expect(voice.texts.last, 'Beacon', reason: word);
        await cubit.close();
      }
    });

    test(
      'auto-check ticking items does not start it, a tick by hand does',
      () async {
        await open(challengeFile);
        progress.autoCheck('A', {0}, cursor: 1);
        await settle();
        expect(voice.texts, ['Ready for a checklist?']);
        progress.toggle('A', 1);
        await settle();
        expect(voice.texts.last, 'Nav');
      },
    );

    test('a flow checklist does not ask', () async {
      await open(flowFile);
      expect(voice.texts, ['Parking brake']);
    });

    test('manual mode does not ask', () async {
      final document = const AircraftWorkflowParser().parse(challengeFile);
      progress = FakeChecklistProgressRepository()
        ..setManual('A', manual: true);
      settings = FakeSettingsRepository();
      await settings.update(
        (o) => o.set(UserOptions.voiceChallengesOption, true),
      );
      voice = FakeVoiceRepository();
      cubit = VoiceSessionCubit(
        checklistName: 'A',
        checklistRepository: FakeChecklistRepository(current: document),
        progressRepository: progress,
        settings: settings,
        voice: voice,
        checkNext: () {},
        skipNext: () {},
      )..load();
      await settle();
      expect(voice.texts, ['Beacon']);
    });

    test('with the challenge voice off it does not ask', () async {
      await open(challengeFile, challenges: false);
      expect(voice.texts.every((t) => t.isEmpty), isTrue);
    });

    test('pause and resume while waiting asks again', () async {
      await open(challengeFile);
      voice.hear('pause checklist');
      await settle();
      voice.hear('resume checklist');
      await settle();
      expect(voice.texts, ['Ready for a checklist?', 'Ready for a checklist?']);
      voice.hear('yes');
      await settle();
      expect(voice.texts.last, 'Beacon');
    });
  });

  group('after a step', () {
    test('a tick by hand reads the next item', () async {
      await open(flowFile);
      progress.toggle('A', 0);
      await settle();
      expect(voice.texts.last, 'SET Flaps');
    });

    test('three challenge rows ticked by auto are counted', () async {
      await open(challengeFile);
      voice.hear('yes');
      await settle();
      expect(voice.texts, ['Ready for a checklist?', 'Beacon']);
      progress.autoCheck('A', {0, 1, 2}, cursor: 3);
      await settle();
      expect(voice.texts.last, '3 verified Taxi');
    });

    test('a tick against the sim says double check first', () async {
      await open(flowFile);
      progress.toggle('A', 0, disagrees: true);
      await settle();
      expect(voice.texts.last, 'Double check Parking brake Flaps');
    });

    test('the last tick says the checklist is complete', () async {
      await open(flowFile);
      for (var i = 0; i < 3; i++) {
        progress.toggle('A', i);
        await settle();
      }
      expect(voice.texts.last, 'ON Checklist complete');
    });

    test('a change to another checklist is not spoken', () async {
      await open(flowFile);
      final before = voice.said.length;
      progress.toggle('Other', 0);
      await settle();
      expect(voice.said.length, before);
    });
  });

  group('spoken answers', () {
    test('an answer ticks the item the voice waits on', () async {
      await open(flowFile);
      voice.hear('set');
      await settle();
      expect(checks, 1);
    });

    test('the result of the item is an answer', () async {
      await open('sw_checklist:A\nsw_item:Doors|LOCKED');
      voice.hear('locked');
      await settle();
      expect(checks, 1);
    });

    test('skip skips', () async {
      await open(flowFile);
      voice.hear('skip');
      await settle();
      expect(skips, 1);
      expect(checks, 0);
    });

    test('nothing is ticked for a row the voice is off for', () async {
      await open(flowFile, flows: false);
      voice.hear('set');
      await settle();
      expect(checks, 0);
    });

    test('noise is ignored', () async {
      await open(flowFile);
      final before = voice.said.length;
      voice.hear('banana split');
      await settle();
      expect(checks + skips, 0);
      expect(voice.said.length, before);
    });

    test('a close match asks, and yes does it', () async {
      await open(flowFile);
      voice.hear('chek');
      await settle();
      expect(voice.texts.last, 'Did you mean check?');
      expect(checks, 0);
      voice.hear('yes');
      await settle();
      expect(checks, 1);
    });

    test('no after a close match reads the item again', () async {
      await open(flowFile);
      voice.hear('chek');
      await settle();
      voice.hear('no');
      await settle();
      expect(checks, 0);
      expect(voice.texts.last, 'Parking brake');
    });

    test('a yes with nothing asked does nothing', () async {
      await open(flowFile);
      voice.hear('yes');
      await settle();
      expect(checks, 0);
    });
  });

  group('pause', () {
    test('the words pause it: it stops speaking and ignores answers', () async {
      await open(flowFile);
      voice.hear('pause checklist');
      await settle();
      expect(cubit.state.paused, isTrue);
      expect(voice.stops, 1);
      voice.hear('set');
      await settle();
      expect(checks, 0);
    });

    test('progress while paused is silent', () async {
      await open(flowFile);
      cubit.pause();
      final before = voice.said.length;
      progress.toggle('A', 0);
      await settle();
      expect(voice.said.length, before);
    });

    test('resume checklist carries on with the item to do now', () async {
      await open(flowFile);
      cubit.pause();
      progress.toggle('A', 0);
      await settle();
      voice.hear('resume checklist');
      await settle();
      expect(cubit.state.paused, isFalse);
      expect(voice.texts.last, 'Flaps');
    });

    test('the button pauses and resumes', () async {
      await open(flowFile);
      cubit.pause();
      expect(cubit.state.paused, isTrue);
      cubit.resume();
      expect(cubit.state.paused, isFalse);
      expect(voice.texts.last, 'Parking brake');
    });

    test('a near miss of resume asks, and yes resumes', () async {
      await open(flowFile);
      cubit.pause();
      voice.hear('continue checkist');
      await settle();
      expect(voice.texts.last, 'Did you mean continue checklist?');
      voice.hear('yes');
      await settle();
      expect(cubit.state.paused, isFalse);
    });

    test('pause is ignored while the voice is off', () async {
      await open(flowFile, flows: false, challenges: false);
      cubit.pause();
      expect(cubit.state.paused, isFalse);
    });
  });

  group('the settings change while it is open', () {
    test('turning the voice on starts it', () async {
      await open(flowFile, flows: false, challenges: false);
      await settings.update((o) => o.set(UserOptions.voiceFlowsOption, true));
      await settle();
      expect(cubit.state.active, isTrue);
      expect(voice.texts, ['Parking brake']);
    });

    test('turning both off stops it', () async {
      await open(flowFile);
      await settings.update(
        (o) => o
            .set(UserOptions.voiceFlowsOption, false)
            .set(UserOptions.voiceChallengesOption, false),
      );
      await settle();
      expect(cubit.state, const VoiceSessionState());
      expect(voice.isListening, isFalse);
      expect(voice.stops, 1);
    });

    test(
      'turning one kind off reads the item again for what is left',
      () async {
        await open(flowFile);
        await settings.update(
          (o) => o.set(UserOptions.voiceFlowsOption, false),
        );
        await settle();
        expect(voice.texts.last, '');
        voice.hear('set');
        await settle();
        expect(checks, 0);
      },
    );
  });
}
