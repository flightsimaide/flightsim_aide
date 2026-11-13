import 'package:equatable/equatable.dart';

/// What the handshake has shown about the companion plugin so far.
sealed class PluginState extends Equatable {
  const PluginState();

  @override
  List<Object?> get props => const [];
}

/// Not yet known: the sim is unknown or the handshake window is still open.
class PluginStateUnknown extends PluginState {
  /// Creates the state.
  const PluginStateUnknown();
}

/// No valid hello arrived within the window. Probing continues.
class PluginStateNotDetected extends PluginState {
  /// Creates the state. [noRoute] is set when every probe failed with errno 65
  /// (`No route to host`), the sign of a denied iOS Local Network permission.
  const PluginStateNotDetected({this.noRoute = false});

  /// Whether every probe of the last round failed with errno 65.
  final bool noRoute;

  @override
  List<Object?> get props => [noRoute];
}

/// The plugin speaks another protocol version.
class PluginStateVersionMismatch extends PluginState {
  /// Creates the state.
  const PluginStateVersionMismatch({
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

/// A valid hello arrived from [port].
class PluginStateReady extends PluginState {
  /// Creates the state.
  const PluginStateReady(this.port);

  /// The plugin's port.
  final int port;

  @override
  List<Object?> get props => [port];
}
