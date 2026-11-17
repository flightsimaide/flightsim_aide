import 'dart:async';

import 'package:flightsim_aide/data/services/voice/speech_input_service.dart';

/// A recogniser the test speaks into with [hear].
class FakeSpeechInputService implements SpeechInputService {
  final _phrases = StreamController<String>.broadcast();

  /// Whether [start] works; false stands for no microphone.
  bool available = true;

  /// How many times [start] and [stop] were called.
  int starts = 0;

  /// How many times [stop] was called.
  int stops = 0;
  bool _listening = false;

  @override
  Stream<String> get phrases => _phrases.stream;

  @override
  bool get isListening => _listening;

  /// Says [phrase] to the recogniser.
  void hear(String phrase) => _phrases.add(phrase);

  @override
  Future<bool> start() async {
    starts++;
    _listening = available;
    return available;
  }

  @override
  Future<void> stop() async {
    stops++;
    _listening = false;
  }
}
