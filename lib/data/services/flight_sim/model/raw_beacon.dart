import 'package:equatable/equatable.dart';

/// A decoded X-Plane multicast beacon.
class RawBeacon extends Equatable {
  /// Creates a beacon.
  const RawBeacon({
    required this.ip,
    required this.port,
    required this.name,
    required this.version,
  });

  /// The address the datagram came from.
  final String ip;

  /// X-Plane's own UDP port, not the plugin's.
  final int port;

  /// The computer name.
  final String name;

  /// The simulator version number.
  final int version;

  @override
  List<Object?> get props => [ip, port, name, version];
}
