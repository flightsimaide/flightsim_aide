import '../../../domain/models/voice/voice_prompt.dart';
import '../../../utils/result.dart';

/// Speaks prompts and listens for the pilot (D-84). Never throws.
abstract class VoiceRepository {
  /// The phrases the pilot said, one per utterance.
  Stream<String> get phrases;

  /// Whether a prompt is being spoken.
  bool get isSpeaking;

  /// Whether listening is on.
  bool get isListening;

  /// Speaks [prompt], cutting off any speech in progress. Completes when the
  /// speech is finished or was cut off. The microphone is off while speaking,
  /// so the voice does not hear itself.
  Future<void> say(VoicePrompt prompt);

  /// Stops speaking now.
  Future<void> stopSpeaking();

  /// Starts listening. An [Error] when speech recognition is not available;
  /// the voice then still speaks.
  Future<Result<void>> startListening();

  /// Stops listening.
  Future<void> stopListening();
}
