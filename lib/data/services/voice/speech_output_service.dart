/// Speaks text aloud. The abstract seam over the text-to-speech package, so
/// `domain/` and the cubits never name it (D-84).
abstract class SpeechOutputService {
  /// Speaks [text]. Completes when the speech has ended or been stopped.
  Future<void> speak(String text);

  /// Stops speaking now; a pending [speak] completes.
  Future<void> stop();
}
