import 'package:flutter_tts/flutter_tts.dart';

import 'speech_output_service.dart';

/// [SpeechOutputService] over `flutter_tts` (D-84). Windows is best effort.
class FlutterTtsSpeechOutputService implements SpeechOutputService {
  /// Creates the service; [tts] is for tests.
  FlutterTtsSpeechOutputService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  Future<void>? _ready;

  Future<void> _prepare() => _ready ??= () async {
    await _tts.awaitSpeakCompletion(true);
  }();

  @override
  Future<void> speak(String text) async {
    try {
      await _prepare();
      await _tts.speak(text);
    } on Object {
      // A voice that cannot speak must not break the checklist.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object {
      // Nothing to stop.
    }
  }
}
