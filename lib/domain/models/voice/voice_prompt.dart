import 'package:equatable/equatable.dart';

/// One thing to say, and how long to wait after it.
class VoiceUtterance extends Equatable {
  /// Creates an utterance.
  const VoiceUtterance(this.text, {this.pauseAfter = Duration.zero});

  /// The words to speak.
  final String text;

  /// The silence after the words, before the next utterance.
  final Duration pauseAfter;

  @override
  List<Object?> get props => [text, pauseAfter];
}

/// What the voice says after a step, and what it then waits for.
class VoicePrompt extends Equatable {
  /// Creates a prompt.
  const VoicePrompt({
    this.utterances = const [],
    this.waitingFor,
    this.waitingForChallenge = false,
    this.complete = false,
  });

  /// Nothing to say and nothing to wait for.
  static const silent = VoicePrompt();

  /// What to say, in order.
  final List<VoiceUtterance> utterances;

  /// The item index the voice waits on (a dataref change, a tick or a spoken
  /// answer), or null when it waits for nothing: the checklist is complete,
  /// or the voice is off for that kind of row.
  final int? waitingFor;

  /// Whether [waitingFor] is a challenge row (the pilot answers it) rather
  /// than a flow row (the pilot does it).
  final bool waitingForChallenge;

  /// Whether the checklist is complete.
  final bool complete;

  /// The words, joined, for tests and logs.
  String get text => utterances.map((u) => u.text).join(' ');

  @override
  List<Object?> get props => [
    utterances,
    waitingFor,
    waitingForChallenge,
    complete,
  ];
}
