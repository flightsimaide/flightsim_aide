import 'package:equatable/equatable.dart';

/// How far the app has got in reaching the simulator and its companion plugin.
sealed class ConnectionStatus extends Equatable {
  const ConnectionStatus();

  @override
  List<Object?> get props => const [];
}

/// Looking for a simulator on the network.
class ConnectionSearching extends ConnectionStatus {
  /// Creates the state.
  const ConnectionSearching();
}

/// A simulator was found; the plugin handshake and stream are being set up.
class ConnectionConnecting extends ConnectionStatus {
  /// Creates the state.
  const ConnectionConnecting();
}

/// The plugin answered and the stream is live.
class ConnectionConnected extends ConnectionStatus {
  /// Creates the state.
  const ConnectionConnected();
}

/// The device has no usable local network.
class ConnectionNoNetwork extends ConnectionStatus {
  /// Creates the state.
  const ConnectionNoNetwork();
}

/// The simulator stopped answering. [lastSeen] is when it last did, if ever.
/// [manualAddress] is the typed address being tried, or null when the sim was
/// found by its beacon.
class ConnectionSimUnreachable extends ConnectionStatus {
  /// Creates the state.
  const ConnectionSimUnreachable({this.lastSeen, this.manualAddress});

  /// When the simulator last answered, or null if it never has.
  final DateTime? lastSeen;

  /// The typed address that does not answer, or null.
  final String? manualAddress;

  @override
  List<Object?> get props => [lastSeen, manualAddress];
}

/// Every connection to the simulator's address was refused with `No route to
/// host`, which is how iOS behaves while Local Network access is denied.
class ConnectionLocalNetworkDenied extends ConnectionStatus {
  /// Creates the state.
  const ConnectionLocalNetworkDenied();
}

/// The plugin speaks a different protocol version than this app.
class ConnectionPluginVersionMismatch extends ConnectionStatus {
  /// Creates the state.
  const ConnectionPluginVersionMismatch({
    required this.found,
    required this.required,
  });

  /// The version the plugin reported.
  final int found;

  /// The version this app needs.
  final int required;

  @override
  List<Object?> get props => [found, required];
}
