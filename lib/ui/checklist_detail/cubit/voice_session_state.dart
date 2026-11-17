import 'package:equatable/equatable.dart';

/// The state of the voice for one open checklist (D-84).
class VoiceSessionState extends Equatable {
  /// Creates the state.
  const VoiceSessionState({
    this.active = false,
    this.paused = false,
    this.listening = false,
    this.micUnavailable = false,
  });

  /// Whether the voice is on (at least one of the two switches).
  final bool active;

  /// Whether the pilot paused it; the screen flashes PAUSED.
  final bool paused;

  /// Whether the microphone is on.
  final bool listening;

  /// Whether speech recognition could not be started: the voice speaks but
  /// does not listen.
  final bool micUnavailable;

  /// A copy with the given fields changed.
  VoiceSessionState copyWith({
    bool? active,
    bool? paused,
    bool? listening,
    bool? micUnavailable,
  }) => VoiceSessionState(
    active: active ?? this.active,
    paused: paused ?? this.paused,
    listening: listening ?? this.listening,
    micUnavailable: micUnavailable ?? this.micUnavailable,
  );

  @override
  List<Object?> get props => [active, paused, listening, micUnavailable];
}
