/// Listens for spoken phrases. The abstract seam over the speech recognition
/// package (D-84).
abstract class SpeechInputService {
  /// The final phrases the recogniser heard, one per utterance.
  Stream<String> get phrases;

  /// Whether the service is meant to be listening.
  bool get isListening;

  /// Starts listening and keeps listening until [stop]. Returns false when
  /// speech recognition is not available (no microphone, access denied).
  Future<bool> start();

  /// Stops listening.
  Future<void> stop();
}
