import 'dart:async';

import 'package:flightsim_aide/data/services/flight_sim/network_status_service.dart';

/// A [NetworkStatusService] a test drives by hand.
class FakeNetworkStatusService implements NetworkStatusService {
  /// Creates the fake; [initiallyAvailable] is the starting value.
  FakeNetworkStatusService({bool initiallyAvailable = true})
    : _available = initiallyAvailable;

  final _controller = StreamController<bool>.broadcast(sync: true);
  bool _available;

  /// How many times [reportSendFailure] was called.
  int sendFailures = 0;

  @override
  bool get isAvailable => _available;

  @override
  Stream<bool> get availability => _controller.stream;

  /// Changes availability and announces it when it changed.
  void setAvailable(bool value) {
    if (value == _available) return;
    _available = value;
    _controller.add(value);
  }

  @override
  void reportSendFailure() {
    sendFailures++;
    setAvailable(false);
  }

  @override
  void start() {}

  @override
  void dispose() => unawaited(_controller.close());
}
