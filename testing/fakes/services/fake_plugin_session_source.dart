import 'dart:async';

import 'package:flightsim_aide/data/services/flight_sim/model/plugin_session.dart';
import 'package:flightsim_aide/data/services/flight_sim/plugin_session_source.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flightsim_aide/utils/result.dart';

/// A [PluginSessionSource] a test drives by hand.
class FakePluginSessionSource implements PluginSessionSource {
  /// Creates the fake with an optional first [current] session.
  FakePluginSessionSource([this.current]);

  @override
  PluginSession? current;

  final _controller = StreamController<PluginSession?>.broadcast(sync: true);

  /// What [reload] does. By default it returns [current], or
  /// [PluginNotDetected] when there is none.
  Future<Result<PluginSession>> Function()? onReload;

  /// How many times [reload] was called.
  int reloads = 0;

  @override
  Stream<PluginSession?> get changes => _controller.stream;

  /// Makes [session] the current one and announces it.
  void emit(PluginSession? session) {
    current = session;
    _controller.add(session);
  }

  /// Reports a failed fetch on the error channel; [current] stays.
  void emitError(Object error) => _controller.addError(error);

  @override
  Future<Result<PluginSession>> reload() async {
    reloads++;
    final handler = onReload;
    if (handler != null) {
      final result = await handler();
      if (result case Ok(:final value)) current = value;
      return result;
    }
    final session = current;
    return session == null ? Error(PluginNotDetected()) : Ok(session);
  }

  /// Closes the stream.
  Future<void> dispose() => _controller.close();
}
