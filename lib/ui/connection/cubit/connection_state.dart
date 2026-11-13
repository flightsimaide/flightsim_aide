import 'package:equatable/equatable.dart';

import '../../../domain/models/aircraft/aircraft_identity.dart';
import '../../../domain/models/flight_sim/discovered_sim.dart';

/// What the connection UI shows. Named `...View...` and `Link...` so it does
/// not clash with Flutter's `ConnectionState` or the domain's
/// `ConnectionStatus` classes.
///
/// Every state can carry [inputError], the reason the last manual address was
/// refused; the connection itself is untouched by it.
sealed class ConnectionViewState extends Equatable {
  const ConnectionViewState({
    this.inputError,
    this.computer,
    this.others = const [],
  });

  /// Why the last typed address was refused, or null.
  final String? inputError;

  /// For the connected states: the computer connected to, when known.
  final DiscoveredSim? computer;

  /// For the connected states: the other computers on the list (task 0.16).
  final List<DiscoveredSim> others;

  /// The same state with [error] as [inputError].
  ConnectionViewState withInputError(String? error);

  @override
  List<Object?> get props => [inputError, computer, others];
}

/// Looking for a simulator. [sims] lists those already seen.
final class LinkSearching extends ConnectionViewState {
  /// Creates the state.
  const LinkSearching({this.sims = const [], super.inputError});

  /// Simulators seen so far.
  final List<DiscoveredSim> sims;

  @override
  LinkSearching withInputError(String? error) =>
      LinkSearching(sims: sims, inputError: error);

  @override
  List<Object?> get props => [...super.props, sims];
}

/// A simulator was found and nothing more is known until the plugin answers
/// with an aircraft, which can take seconds or minutes. [hint] is true once
/// the wait has lasted [waitingHintDelay].
final class LinkConnecting extends ConnectionViewState {
  /// Creates the state.
  const LinkConnecting({this.hint = false, super.inputError});

  /// Whether the wait is long enough to suggest checking the plugin list.
  final bool hint;

  @override
  LinkConnecting withInputError(String? error) =>
      LinkConnecting(hint: hint, inputError: error);

  @override
  List<Object?> get props => [...super.props, hint];
}

/// Connected; [aircraft] is what the simulator has loaded and it has a
/// checklist.
final class LinkConnected extends ConnectionViewState {
  /// Creates the state.
  const LinkConnected(
    this.aircraft, {
    super.inputError,
    super.computer,
    super.others,
  });

  /// The aircraft in the simulator.
  final AircraftIdentity aircraft;

  @override
  LinkConnected withInputError(String? error) => LinkConnected(
    aircraft,
    inputError: error,
    computer: computer,
    others: others,
  );

  @override
  List<Object?> get props => [...super.props, aircraft];
}

/// Connected, but the simulator's aircraft has no checklist file.
final class LinkNoChecklist extends ConnectionViewState {
  /// Creates the state.
  const LinkNoChecklist(
    this.aircraft, {
    super.inputError,
    super.computer,
    super.others,
  });

  /// The aircraft in the simulator.
  final AircraftIdentity aircraft;

  @override
  LinkNoChecklist withInputError(String? error) => LinkNoChecklist(
    aircraft,
    inputError: error,
    computer: computer,
    others: others,
  );

  @override
  List<Object?> get props => [...super.props, aircraft];
}

/// The simulator now has a different aircraft than the one whose checklist is
/// shown (D-32). Nothing is swapped until the user says so.
final class LinkAircraftChanged extends ConnectionViewState {
  /// Creates the state.
  const LinkAircraftChanged({
    required this.loaded,
    required this.live,
    super.inputError,
    super.computer,
    super.others,
  });

  /// The aircraft of the checklist on screen.
  final AircraftIdentity loaded;

  /// The aircraft the simulator has now.
  final AircraftIdentity live;

  /// Whether [live] has no checklist file.
  bool get liveHasChecklist => live.checklistPath != null;

  @override
  LinkAircraftChanged withInputError(String? error) => LinkAircraftChanged(
    loaded: loaded,
    live: live,
    inputError: error,
    computer: computer,
    others: others,
  );

  @override
  List<Object?> get props => [...super.props, loaded, live];
}

/// The device has no usable network.
final class LinkNoNetwork extends ConnectionViewState {
  /// Creates the state.
  const LinkNoNetwork({super.inputError});

  @override
  LinkNoNetwork withInputError(String? error) =>
      LinkNoNetwork(inputError: error);
}

/// The simulator stopped answering; [lastSeen] is when it last did and
/// [manualAddress] the typed address being tried, if one is in use.
final class LinkSimUnreachable extends ConnectionViewState {
  /// Creates the state.
  const LinkSimUnreachable({
    this.lastSeen,
    this.manualAddress,
    super.inputError,
    super.computer,
    super.others,
  });

  /// When the simulator last answered, or null if it never has.
  final DateTime? lastSeen;

  /// The typed address that does not answer, or null.
  final String? manualAddress;

  @override
  LinkSimUnreachable withInputError(String? error) => LinkSimUnreachable(
    lastSeen: lastSeen,
    manualAddress: manualAddress,
    inputError: error,
    computer: computer,
    others: others,
  );

  @override
  List<Object?> get props => [...super.props, lastSeen, manualAddress];
}

/// Connections to the simulator fail with `No route to host`; on iOS this
/// means Local Network access is off for the app.
final class LinkLocalNetworkDenied extends ConnectionViewState {
  /// Creates the state.
  const LinkLocalNetworkDenied({super.inputError});

  @override
  LinkLocalNetworkDenied withInputError(String? error) =>
      LinkLocalNetworkDenied(inputError: error);
}

/// The plugin speaks a different protocol version.
final class LinkVersionMismatch extends ConnectionViewState {
  /// Creates the state.
  const LinkVersionMismatch({
    required this.found,
    required this.required,
    super.inputError,
  });

  /// The version the plugin reported.
  final int found;

  /// The version this app needs.
  final int required;

  @override
  LinkVersionMismatch withInputError(String? error) =>
      LinkVersionMismatch(found: found, required: required, inputError: error);

  @override
  List<Object?> get props => [...super.props, found, required];
}

/// How long the wait for the aircraft runs before the hint appears.
const waitingHintDelay = Duration(seconds: 10);
