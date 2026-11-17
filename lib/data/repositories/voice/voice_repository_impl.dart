import '../../../domain/models/voice/voice_prompt.dart';
import '../../../utils/app_exception.dart';
import '../../../utils/result.dart';
import '../../services/voice/speech_input_service.dart';
import '../../services/voice/speech_output_service.dart';
import 'voice_repository.dart';

/// [VoiceRepository] over a [SpeechOutputService] and a [SpeechInputService].
class VoiceRepositoryImpl implements VoiceRepository {
  /// Creates the repository. [wait] is how a pause is waited out, for tests.
  VoiceRepositoryImpl({
    required this._output,
    required this._input,
    Future<void> Function(Duration)? wait,
  }) : _wait = wait ?? Future<void>.delayed;

  final SpeechOutputService _output;
  final SpeechInputService _input;
  final Future<void> Function(Duration) _wait;

  /// Counts the calls to [say] and [stopSpeaking]; a speech in progress ends
  /// as soon as it is no longer the latest.
  int _turn = 0;
  bool _speaking = false;
  bool _wantListening = false;

  @override
  Stream<String> get phrases => _input.phrases;

  @override
  bool get isSpeaking => _speaking;

  @override
  bool get isListening => _wantListening;

  @override
  Future<void> say(VoicePrompt prompt) async {
    final turn = ++_turn;
    await _output.stop();
    if (prompt.utterances.isEmpty) {
      _speaking = false;
      await _resumeListening(turn);
      return;
    }
    _speaking = true;
    if (_input.isListening) await _input.stop();
    for (final utterance in prompt.utterances) {
      if (turn != _turn) return;
      await _output.speak(utterance.text);
      if (turn != _turn) return;
      if (utterance.pauseAfter > Duration.zero) {
        await _wait(utterance.pauseAfter);
      }
    }
    if (turn != _turn) return;
    _speaking = false;
    await _resumeListening(turn);
  }

  @override
  Future<void> stopSpeaking() async {
    final turn = ++_turn;
    _speaking = false;
    await _output.stop();
    await _resumeListening(turn);
  }

  @override
  Future<Result<void>> startListening() async {
    _wantListening = true;
    if (_speaking) return const Ok(null);
    final worked = await _input.start();
    if (!worked) {
      _wantListening = false;
      return Error(SpeechUnavailable());
    }
    return const Ok(null);
  }

  @override
  Future<void> stopListening() async {
    _wantListening = false;
    await _input.stop();
  }

  Future<void> _resumeListening(int turn) async {
    if (turn != _turn || !_wantListening || _input.isListening) return;
    if (!await _input.start()) _wantListening = false;
  }
}
