import 'package:equatable/equatable.dart';

import 'raw_aircraft_info.dart';

/// What the app knows about the plugin right now: where it answers and which
/// aircraft it reported. Raw data only.
class PluginSession extends Equatable {
  /// Creates a session.
  const PluginSession({
    required this.host,
    required this.port,
    required this.aircraft,
  });

  /// The sim machine's address.
  final String host;

  /// The plugin's port.
  final int port;

  /// The `/v1/aircraft` answer.
  final RawAircraftInfo aircraft;

  /// The aircraft generation at the time of the fetch.
  int get generation => aircraft.generation;

  @override
  List<Object?> get props => [host, port, aircraft];
}
