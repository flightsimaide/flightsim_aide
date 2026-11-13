import 'package:equatable/equatable.dart';

/// A machine that may run a simulator, found by beacon or typed by hand.
class SimEndpoint extends Equatable {
  /// Creates an endpoint.
  const SimEndpoint({
    required this.host,
    this.name,
    this.alternateHosts = const [],
  });

  /// IP address or host name.
  final String host;

  /// The computer name, when the beacon carried one.
  final String? name;

  /// Other addresses the same computer announced from (one per network
  /// adapter), tried in order when [host] does not answer.
  final List<String> alternateHosts;

  /// [host] first, then [alternateHosts].
  List<String> get hosts => [host, ...alternateHosts];

  @override
  List<Object?> get props => [host, name, alternateHosts];
}
