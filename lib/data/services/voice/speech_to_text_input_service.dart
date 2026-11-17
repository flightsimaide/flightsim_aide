import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

import 'speech_input_service.dart';

/// [SpeechInputService] over `speech_to_text` (D-84). The package stops after
/// a silence, so this restarts it while listening is wanted. Windows is best
/// effort.
class SpeechToTextInputService implements SpeechInputService {
  /// Creates the service; [speech] is for tests.
  SpeechToTextInputService({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  final _phrases = StreamController<String>.broadcast();
  bool _initialised = false;
  bool _wanted = false;
  int _errors = 0;

  /// After this many errors in a row listening is given up.
  static const maxErrorsInARow = 5;

  @override
  Stream<String> get phrases => _phrases.stream;

  @override
  bool get isListening => _wanted;

  @override
  Future<bool> start() async {
    if (!_initialised) {
      try {
        _initialised = await _speech.initialize(
          onStatus: _onStatus,
          onError: (_) => _errors++,
        );
      } on Object {
        _initialised = false;
      }
    }
    if (!_initialised) return false;
    _wanted = true;
    _errors = 0;
    await _listen();
    return true;
  }

  @override
  Future<void> stop() async {
    _wanted = false;
    try {
      await _speech.stop();
    } on Object {
      // Already stopped.
    }
  }

  Future<void> _listen() async {
    if (!_wanted || _speech.isListening) return;
    try {
      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (result.finalResult && words.isNotEmpty) {
            _errors = 0;
            _phrases.add(words);
          }
        },
        listenOptions: SpeechListenOptions(
          partialResults: false,
          cancelOnError: false,
          listenMode: ListenMode.confirmation,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
        ),
      );
    } on Object {
      _errors++;
    }
  }

  void _onStatus(String status) {
    if (!_wanted) return;
    if (status != SpeechToText.doneStatus &&
        status != SpeechToText.notListeningStatus) {
      return;
    }
    if (_errors >= maxErrorsInARow) {
      _wanted = false;
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 200), _listen);
  }
}
