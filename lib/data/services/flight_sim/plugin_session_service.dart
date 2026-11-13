import 'dart:async';

import '../../../utils/app_exception.dart';
import '../../../utils/result.dart';
import 'companion_plugin_service.dart';
import 'flight_sim_service.dart';
import 'model/plugin_session.dart';
import 'model/signal_spec.dart';
import 'plugin_session_source.dart';
import 'plugin_state.dart';

/// [PluginSessionSource] built from the stream's generation signal and the
/// plugin's `/v1/aircraft`. It is the only caller of `getAircraft`.
///
/// It fetches when a generation arrives that differs from the session it
/// holds (which includes the first one after the plugin becomes ready) and on
/// [reload]. It never polls: an unchanged generation costs nothing.
class PluginSessionService implements PluginSessionSource {
  /// Creates the service. Call [start] to begin listening.
  PluginSessionService({required this.flightSim, required this.companion});

  /// The live link, for plugin state, generation values and the endpoint.
  final FlightSimService flightSim;

  /// The HTTP side.
  final CompanionPluginService companion;

  final _changes = StreamController<PluginSession?>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  PluginSession? _current;
  int? _latestGeneration;
  bool _fetching = false;
  bool _disposed = false;

  @override
  PluginSession? get current => _current;

  @override
  Stream<PluginSession?> get changes => _changes.stream;

  /// Starts listening to the link. Calling it twice is harmless.
  void start() {
    if (_subscriptions.isNotEmpty || _disposed) return;
    _subscriptions
      ..add(flightSim.pluginStates.listen(_onPluginState))
      ..add(
        flightSim.signals
            .where((m) => m.name == aircraftGenerationSignal)
            .listen((m) {
              final value = m.value;
              if (value == null) return;
              _latestGeneration = value.toInt();
              unawaited(_catchUp());
            }),
      );
  }

  /// Stops listening and closes [changes].
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    await _changes.close();
  }

  void _onPluginState(PluginState state) {
    if (state is PluginStateReady) return;
    _latestGeneration = null;
    if (_current != null) {
      _current = null;
      _changes.add(null);
    }
  }

  /// Fetches until the session matches the newest generation seen. A failure
  /// ends the loop; the next generation message tries again.
  Future<void> _catchUp() async {
    if (_fetching || _disposed) return;
    _fetching = true;
    try {
      while (!_disposed &&
          _latestGeneration != null &&
          _current?.generation != _latestGeneration) {
        final result = await _fetch();
        if (_disposed) return;
        switch (result) {
          case Ok(:final value):
            _latestGeneration = value.generation;
            _publish(value);
          case Error(:final error):
            _changes.addError(error);
            return;
        }
      }
    } finally {
      _fetching = false;
    }
  }

  Future<Result<PluginSession>> _fetch() async {
    final endpoint = flightSim.pluginEndpoint;
    if (endpoint == null) return Error(PluginUnreachable());
    final result = await companion.getAircraft(endpoint);
    return switch (result) {
      Error(:final error) => Error(error),
      Ok(:final value) => Ok(
        PluginSession(
          host: endpoint.host,
          port: endpoint.port,
          aircraft: value,
        ),
      ),
    };
  }

  void _publish(PluginSession session) {
    if (session == _current) return;
    _current = session;
    _changes.add(session);
  }

  @override
  Future<Result<PluginSession>> reload() async {
    final result = await _fetch();
    if (_disposed) return result;
    switch (result) {
      case Ok(:final value):
        _publish(value);
      case Error(:final error):
        _changes.addError(error);
    }
    return result;
  }
}
