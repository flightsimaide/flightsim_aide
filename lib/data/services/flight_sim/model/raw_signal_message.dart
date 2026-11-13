import 'package:equatable/equatable.dart';

/// One sampled value from the stream.
class RawSignalMessage extends Equatable {
  /// Creates a message.
  const RawSignalMessage({
    required this.subscriptionId,
    required this.name,
    required this.value,
    required this.sampleTime,
  });

  /// The id the client chose when subscribing.
  final int subscriptionId;

  /// The signal's name.
  final String name;

  /// The value; null when the source reported a non-finite number.
  final num? value;

  /// When the value was sampled, epoch milliseconds.
  final int sampleTime;

  @override
  List<Object?> get props => [subscriptionId, name, value, sampleTime];
}
