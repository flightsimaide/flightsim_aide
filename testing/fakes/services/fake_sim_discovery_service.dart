import 'dart:async';

import 'package:flightsim_aide/data/services/flight_sim/model/sim_endpoint.dart';
import 'package:flightsim_aide/data/services/flight_sim/sim_discovery_service.dart';

/// A [SimDiscoveryService] a test drives by hand.
class FakeSimDiscoveryService implements SimDiscoveryService {
  /// Creates the fake. [manualHost] is what the repository asked for.
  FakeSimDiscoveryService({this.manualHost});

  /// The manual address this discovery was created for, or null.
  final String? manualHost;

  final _controller = StreamController<SimEndpoint>.broadcast(sync: true);

  /// Counters for the lifecycle calls.
  int starts = 0;
  int stops = 0;
  int refreshes = 0;
  bool disposed = false;

  @override
  Stream<SimEndpoint> get endpoints => _controller.stream;

  /// Announces a sim, as a beacon would.
  void see(SimEndpoint sim) => _controller.add(sim);

  @override
  Future<void> start() async {
    starts++;
    final manual = manualHost;
    if (manual != null) _controller.add(SimEndpoint(host: manual));
  }

  @override
  Future<void> refresh() async => refreshes++;

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
  }
}
