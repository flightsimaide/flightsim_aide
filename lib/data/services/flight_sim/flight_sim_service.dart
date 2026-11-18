import 'model/plugin_endpoint.dart';
import 'model/raw_hello.dart';
import 'model/raw_signal_message.dart';
import 'model/sim_endpoint.dart';
import 'plugin_state.dart';
import 'signal_source.dart';

/// The live link to a simulator's companion plugin: handshake, signal stream
/// and recovery. The name stays whatever the transport is; today it is the
/// plugin's WebSocket (D-36). Raw types only, no domain models.
abstract class FlightSimService implements SignalSource {
  /// Every sampled value, as the plugin sent it.
  @override
  Stream<RawSignalMessage> get signals;

  /// Changes of the plugin's state (not detected, version mismatch, ready).
  Stream<PluginState> get pluginStates;

  /// The latest plugin state.
  PluginState get pluginState;

  /// Whether the stream is open and fresh. Emitted on change.
  @override
  Stream<bool> get streamConnected;

  /// Whether the stream is open and fresh right now.
  @override
  bool get isStreamConnected;

  /// Names of subscribed signals the plugin cannot serve (`unknown_name` or
  /// `unsupported`). Emitted once per name; not an error.
  @override
  Stream<String> get unavailableSignals;

  /// Where the plugin was found, once it has been.
  PluginEndpoint? get pluginEndpoint;

  /// The run id from the hello of the plugin the stream is connected to, or
  /// null before the first connection. It stays after the stream drops.
  String? get runId;

  /// The `sim.kind` from the same hello (for example `xplane` or `msfs`), or
  /// null before the first connection or when the plugin did not say. It stays
  /// after the stream drops, like [runId].
  String? get simKind;

  /// Finds the plugin on [sim], opens the stream and keeps it open, retrying
  /// with back-off. Completes after the first attempt.
  Future<void> connect(SimEndpoint sim);

  /// Asks [sim] for its plugin's hello without connecting or touching the
  /// link's state. Null when no address answers. Never throws.
  Future<RawHello?> peekHello(SimEndpoint sim);

  /// Closes everything and forgets the sim.
  Future<void> disconnect();

  /// Closes the sockets and stops all timers (the app went to the background).
  Future<void> pause();

  /// Reconnects to the sim [connect] was last given.
  Future<void> resume();

  /// Releases everything; the service cannot be used afterwards.
  Future<void> dispose();
}
