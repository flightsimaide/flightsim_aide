import 'dart:async';

import 'package:flightsim_aide/data/services/flight_sim/flight_sim_service.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/plugin_endpoint.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/raw_hello.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/raw_signal_message.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/sim_endpoint.dart';
import 'package:flightsim_aide/data/services/flight_sim/plugin_state.dart';

/// A [FlightSimService] a test drives by hand. It opens no socket.
class FakeFlightSimService implements FlightSimService {
  final _signals = StreamController<RawSignalMessage>.broadcast(sync: true);
  final _states = StreamController<PluginState>.broadcast(sync: true);
  final _connected = StreamController<bool>.broadcast(sync: true);
  final _unavailable = StreamController<String>.broadcast(sync: true);

  PluginState _state = const PluginStateUnknown();
  bool _up = false;

  @override
  PluginEndpoint? pluginEndpoint;

  @override
  String? runId;

  /// Every sim passed to [connect], in order.
  final List<SimEndpoint> connects = [];

  /// What [peekHello] answers, by the sim's first address; absent means no
  /// answer.
  final Map<String, RawHello> hellos = {};

  /// Every sim passed to [peekHello], in order.
  final List<SimEndpoint> peeks = [];

  @override
  Future<RawHello?> peekHello(SimEndpoint sim) async {
    peeks.add(sim);
    return hellos[sim.host];
  }

  /// The size limit [watchSignals] reports; tests change it.
  @override
  int maxWatched = 126;

  @override
  List<String> fit(List<String> names) => names.take(maxWatched).toList();

  /// Every set passed to [watchSignals], in order.
  final List<Map<String, int>> watchCalls = [];

  @override
  void watchSignals(Map<String, int> namesAtHz) =>
      watchCalls.add(Map.of(namesAtHz));

  /// How many times each lifecycle call happened.
  int disconnects = 0;
  int pauses = 0;
  int resumes = 0;

  @override
  Stream<RawSignalMessage> get signals => _signals.stream;

  @override
  Stream<PluginState> get pluginStates => _states.stream;

  @override
  PluginState get pluginState => _state;

  @override
  Stream<bool> get streamConnected => _connected.stream;

  @override
  bool get isStreamConnected => _up;

  @override
  Stream<String> get unavailableSignals => _unavailable.stream;

  /// Sets and announces the plugin state.
  void setPluginState(PluginState state) {
    if (state == _state) return;
    _state = state;
    _states.add(state);
  }

  /// Sets and announces whether the stream is up.
  void setStreamConnected(bool up) {
    if (up == _up) return;
    _up = up;
    _connected.add(up);
  }

  /// Delivers a sampled value.
  void emit(String name, num? value, {int id = 0, int time = 0}) =>
      _signals.add(
        RawSignalMessage(
          subscriptionId: id,
          name: name,
          value: value,
          sampleTime: time,
        ),
      );

  /// Reports that [name] cannot be served.
  void emitUnavailable(String name) => _unavailable.add(name);

  @override
  Future<void> connect(SimEndpoint sim) async => connects.add(sim);

  @override
  Future<void> disconnect() async {
    disconnects++;
    setStreamConnected(false);
  }

  @override
  Future<void> pause() async => pauses++;

  @override
  Future<void> resume() async => resumes++;

  @override
  Future<void> dispose() async {
    await _signals.close();
    await _states.close();
    await _connected.close();
    await _unavailable.close();
  }
}
