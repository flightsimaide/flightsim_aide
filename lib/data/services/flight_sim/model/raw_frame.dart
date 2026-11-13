import 'package:equatable/equatable.dart';

/// A server-to-client stream frame, decoded.
sealed class RawFrame extends Equatable {
  const RawFrame();

  @override
  List<Object?> get props => const [];
}

/// A subscription was accepted.
class Subscribed extends RawFrame {
  /// Creates the frame.
  const Subscribed(this.id);

  /// The subscription id.
  final int id;

  @override
  List<Object?> get props => [id];
}

/// The plugin refused something. [id] is set when the frame named one.
class StreamError extends RawFrame {
  /// Creates the frame.
  const StreamError(this.code, {this.id});

  /// For example `unknown_name`, `unsupported`, `bad_request`, `limit`.
  final String code;

  /// The subscription the error is about, if known.
  final int? id;

  @override
  List<Object?> get props => [code, id];
}

/// Sampled values: [time] in epoch milliseconds, [values] by subscription id.
class Values extends RawFrame {
  /// Creates the frame.
  const Values(this.time, this.values, {this.lists = const {}});

  /// Sample time, epoch milliseconds.
  final int time;

  /// Value per subscription id; null for a non-finite number.
  final Map<int, num?> values;

  /// The list per range subscription id (`name[a..b]`): one entry per element
  /// that exists, so shorter than asked when the array ends inside the range.
  final Map<int, List<num?>> lists;

  @override
  List<Object?> get props => [time, values, lists];
}

/// The idle keep-alive.
class Heartbeat extends RawFrame {
  /// Creates the frame.
  const Heartbeat();
}

/// The answer to a ping.
class Pong extends RawFrame {
  /// Creates the frame.
  const Pong();
}
