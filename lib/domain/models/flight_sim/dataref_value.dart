import 'package:equatable/equatable.dart';

/// The latest value of one [Dataref]: a number (every kind the stream carries
/// is a number, `PROTOCOL.md` section 6) and when it was sampled, or the
/// [DatarefValue.unknown] shape when the app has no value for it.
class DatarefValue extends Equatable {
  /// A known [number] sampled at [sampledAt].
  const DatarefValue(double this.number, this.sampledAt);

  /// No value: the name is unknown to the sim, the index is past the end, the
  /// stream is stale or nothing has arrived yet. Never "zero".
  const DatarefValue.unknown([this.sampledAt]) : number = null;

  /// The number, or null when [isKnown] is false.
  final double? number;

  /// When the value was sampled (the frame's `t`), if known.
  final DateTime? sampledAt;

  /// Whether there is a number.
  bool get isKnown => number != null;

  @override
  List<Object?> get props => [number, sampledAt];
}
