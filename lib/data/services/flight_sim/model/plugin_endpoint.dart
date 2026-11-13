import 'package:equatable/equatable.dart';

/// Where the companion plugin answers: the sim's host and the plugin's port.
class PluginEndpoint extends Equatable {
  /// Creates an endpoint.
  const PluginEndpoint({required this.host, required this.port});

  /// IP address or host name of the machine running the simulator.
  final String host;

  /// The port the plugin bound (18086 to 18093).
  final int port;

  /// The base URI for plain HTTP requests.
  Uri get baseUri => Uri(scheme: 'http', host: host, port: port);

  @override
  List<Object?> get props => [host, port];
}
