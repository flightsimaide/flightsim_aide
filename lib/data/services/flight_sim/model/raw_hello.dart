import 'package:equatable/equatable.dart';

/// The `GET /v1/hello` answer, as sent.
class RawHello extends Equatable {
  /// Creates a handshake answer.
  const RawHello({
    required this.protocolVersion,
    required this.port,
    required this.streamPath,
    required this.runId,
    this.simKind,
    this.simVersion,
    this.os,
    this.pluginVersion,
  });

  /// The protocol version the plugin speaks.
  final int protocolVersion;

  /// The port that answered.
  final int port;

  /// Path of the WebSocket stream.
  final String streamPath;

  /// Picked by the plugin when X-Plane starts: the same for the whole run, so a
  /// different one on reconnect means X-Plane was restarted.
  final String runId;

  /// The simulator kind, for example `xplane`.
  final String? simKind;

  /// The simulator's version, informational.
  final String? simVersion;

  /// The OS of the computer the sim runs on (`windows`, `macos`, `linux`),
  /// absent from older plugins.
  final String? os;

  /// The plugin's own version, informational.
  final String? pluginVersion;

  @override
  List<Object?> get props => [
    protocolVersion,
    port,
    streamPath,
    runId,
    simKind,
    simVersion,
    os,
    pluginVersion,
  ];
}
