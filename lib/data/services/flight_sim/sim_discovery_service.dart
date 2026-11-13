import 'model/sim_endpoint.dart';

/// Finds machines that may run a simulator. Each simulator family has its own
/// implementation (D-42); the plugin handshake that follows is common.
abstract class SimDiscoveryService {
  /// Every simulator found, once per distinct machine.
  Stream<SimEndpoint> get endpoints;

  /// Starts looking. Calling it twice is harmless.
  Future<void> start();

  /// Asks the implementation to re-check the network (for example after the
  /// device changed Wi-Fi).
  Future<void> refresh();

  /// Stops looking and releases sockets. [start] may be called again.
  Future<void> stop();

  /// Stops for good and closes [endpoints].
  Future<void> dispose();
}
