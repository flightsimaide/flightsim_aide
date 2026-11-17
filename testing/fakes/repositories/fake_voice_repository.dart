import 'dart:async';

import 'package:flightsim_aide/data/repositories/voice/voice_repository.dart';
import 'package:flightsim_aide/domain/models/voice/voice_prompt.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flightsim_aide/utils/result.dart';

/// A voice for cubit tests: records what is said and lets the test speak.
class FakeVoiceRepository implements VoiceRepository {
  final _phrases = StreamController<String>.broadcast();

  /// Every prompt passed to [say], in order.
  final List<VoicePrompt> said = [];

  /// How many times speaking was stopped.
  int stops = 0;

  /// Whether [startListening] works.
  bool micAvailable = true;
  bool _listening = false;

  @override
  Stream<String> get phrases => _phrases.stream;

  @override
  bool get isSpeaking => false;

  @override
  bool get isListening => _listening;

  /// The words of every prompt said.
  List<String> get texts => [for (final p in said) p.text];

  /// The pilot says [phrase].
  void hear(String phrase) => _phrases.add(phrase);

  @override
  Future<void> say(VoicePrompt prompt) async => said.add(prompt);

  @override
  Future<void> stopSpeaking() async => stops++;

  @override
  Future<Result<void>> startListening() async {
    _listening = micAvailable;
    return micAvailable ? const Ok(null) : Error(SpeechUnavailable());
  }

  @override
  Future<void> stopListening() async => _listening = false;
}
