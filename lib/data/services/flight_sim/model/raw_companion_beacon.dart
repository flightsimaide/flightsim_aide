import 'package:equatable/equatable.dart';

/// A decoded companion beacon (`plugin/PROTOCOL.md` section 11).
class RawCompanionBeacon extends Equatable {
  /// Creates a beacon.
  const RawCompanionBeacon({
    required this.ip,
    required this.name,
    required this.port,
    required this.simKind,
  });

  /// The address the datagram came from.
  final String ip;

  /// The computer name.
  final String name;

  /// The TCP port the companion says it listens on. Informational: the app
  /// probes the whole range and trusts the hello.
  final int port;

  /// The companion's `sim.kind`, for example `msfs`.
  final String simKind;

  @override
  List<Object?> get props => [ip, name, port, simKind];
}
