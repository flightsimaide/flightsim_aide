import 'dart:async';

import 'package:flightsim_aide/data/services/voice/speech_output_service.dart';

/// Records what was spoken. A [speak] completes at once unless [hold] is set,
/// then it waits for [finishCurrent] or [stop].
class FakeSpeechOutputService implements SpeechOutputService {
  /// Everything spoken, in order.
  final List<String> spoken = [];

  /// How many times [stop] was called.
  int stops = 0;

  /// Whether [speak] waits for [finishCurrent] instead of completing at once.
  bool hold = false;

  Completer<void>? _current;

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    if (!hold) return Future.value();
    _current = Completer<void>();
    return _current!.future;
  }

  /// Ends the speech in progress.
  void finishCurrent() {
    final current = _current;
    _current = null;
    if (current != null && !current.isCompleted) current.complete();
  }

  @override
  Future<void> stop() async {
    stops++;
    finishCurrent();
  }
}
