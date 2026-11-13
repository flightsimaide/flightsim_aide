import 'package:equatable/equatable.dart';

import 'discovered_sim.dart';

/// A different computer's simulator answered where the app was connected to
/// another one: the question "switch?" the user must answer (task 0.16).
/// The app never moves to another computer without it.
class SwitchOffer extends Equatable {
  /// Creates an offer to move from [from] to [to].
  const SwitchOffer({required this.from, required this.to});

  /// The computer the app was connected to; null when it is not known.
  final DiscoveredSim? from;

  /// The computer that answered.
  final DiscoveredSim to;

  @override
  List<Object?> get props => [from, to];
}
