import 'package:equatable/equatable.dart';

import 'simulator.dart';

/// A simulator found on the network, or typed in by hand.
class DiscoveredSim extends Equatable {
  /// Creates a sim entry.
  const DiscoveredSim({required this.host, this.name, this.simulator, this.os});

  /// IP address.
  final String host;

  /// The computer name the sim announced, when it did.
  final String? name;

  /// Which simulator it is, when known (a beacon on X-Plane's group is
  /// X-Plane).
  final Simulator? simulator;

  /// The computer's operating system, once its plugin has said.
  final HostOs? os;

  /// This entry with [os] set.
  DiscoveredSim withOs(HostOs? os) =>
      DiscoveredSim(host: host, name: name, simulator: simulator, os: os);

  @override
  List<Object?> get props => [host, name, simulator, os];
}
