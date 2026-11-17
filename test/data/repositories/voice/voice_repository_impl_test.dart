import 'package:flightsim_aide/data/repositories/voice/voice_repository_impl.dart';
import 'package:flightsim_aide/domain/models/voice/voice_prompt.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../testing/fakes/services/fake_speech_input_service.dart';
import '../../../../testing/fakes/services/fake_speech_output_service.dart';

// The voice repository over the speech services (D-84).
// AC-62

VoicePrompt say(List<String> texts, {Duration pause = Duration.zero}) =>
    VoicePrompt(
      utterances: [for (final t in texts) VoiceUtterance(t, pauseAfter: pause)],
    );

void main() {
  late FakeSpeechOutputService output;
  late FakeSpeechInputService input;
  late List<Duration> waits;
  late VoiceRepositoryImpl repo;

  setUp(() {
    output = FakeSpeechOutputService();
    input = FakeSpeechInputService();
    waits = [];
    repo = VoiceRepositoryImpl(
      output: output,
      input: input,
      wait: (d) async => waits.add(d),
    );
  });

  test('speaks the utterances in order and waits out each pause', () async {
    await repo.say(say(['Beacon', 'ON'], pause: const Duration(seconds: 1)));
    expect(output.spoken, ['Beacon', 'ON']);
    expect(waits, [const Duration(seconds: 1), const Duration(seconds: 1)]);
    expect(repo.isSpeaking, isFalse);
  });

  test('a silent prompt says nothing', () async {
    await repo.say(VoicePrompt.silent);
    expect(output.spoken, isEmpty);
  });

  test('a new prompt cuts off the one in progress', () async {
    output.hold = true;
    final first = repo.say(say(['one', 'two']));
    await Future<void>.delayed(Duration.zero);
    expect(output.spoken, ['one']);
    expect(repo.isSpeaking, isTrue);

    final second = repo.say(say(['three']));
    await Future<void>.delayed(Duration.zero);
    output.finishCurrent();
    await Future.wait([first, second]);
    expect(output.spoken, ['one', 'three']);
  });

  test('stopSpeaking stops the speech', () async {
    output.hold = true;
    final speaking = repo.say(say(['one', 'two']));
    await Future<void>.delayed(Duration.zero);
    await repo.stopSpeaking();
    await speaking;
    expect(output.spoken, ['one']);
    expect(repo.isSpeaking, isFalse);
  });

  group('the microphone', () {
    test('phrases pass through', () async {
      final heard = <String>[];
      final sub = repo.phrases.listen(heard.add);
      await repo.startListening();
      input.hear('check');
      await Future<void>.delayed(Duration.zero);
      expect(heard, ['check']);
      await sub.cancel();
    });

    test('is off while speaking and back on after', () async {
      await repo.startListening();
      expect(input.isListening, isTrue);
      output.hold = true;
      final speaking = repo.say(say(['one']));
      await Future<void>.delayed(Duration.zero);
      expect(input.isListening, isFalse);
      output.finishCurrent();
      await speaking;
      expect(input.isListening, isTrue);
      expect(repo.isListening, isTrue);
    });

    test('is not started while speaking, only after', () async {
      output.hold = true;
      final speaking = repo.say(say(['one']));
      await Future<void>.delayed(Duration.zero);
      expect((await repo.startListening()).isOk, isTrue);
      expect(input.isListening, isFalse);
      output.finishCurrent();
      await speaking;
      expect(input.isListening, isTrue);
    });

    test('stays off after speech when listening was never wanted', () async {
      await repo.say(say(['one']));
      expect(input.isListening, isFalse);
    });

    test('stopListening keeps it off after speech', () async {
      await repo.startListening();
      await repo.stopListening();
      await repo.say(say(['one']));
      expect(input.isListening, isFalse);
      expect(repo.isListening, isFalse);
    });

    test(
      'no microphone gives a SpeechUnavailable error, and speech works',
      () async {
        input.available = false;
        final result = await repo.startListening();
        expect(result.errorOrNull, isA<SpeechUnavailable>());
        expect(repo.isListening, isFalse);
        await repo.say(say(['one']));
        expect(output.spoken, ['one']);
      },
    );
  });
}
