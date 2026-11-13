import '../../../utils/clock.dart';
import 'companion_plugin_service.dart' show requiredProtocolVersion;
import 'model/raw_hello.dart';
import 'plugin_state.dart';

/// Derives the plugin's state from hello probes, and judges stream staleness
/// from frame arrival. Pure: it holds no timers and reads time only from the
/// injected [clock] when asked.
class PluginStateTracker {
  /// Creates a tracker.
  ///
  /// With no valid hello within [notDetectedAfter] of [simKnown] the state is
  /// "not detected" (D-38). A stream with no frame for [staleAfter] is
  /// stale.
  PluginStateTracker({
    required this.clock,
    this.notDetectedAfter = const Duration(seconds: 2),
    this.staleAfter = const Duration(seconds: 3),
  });

  /// The time source.
  final Clock clock;

  /// How long the handshake window stays open.
  final Duration notDetectedAfter;

  /// How long the stream may stay silent before it counts as stale.
  final Duration staleAfter;

  DateTime? _simKnownAt;
  PluginState? _helloState;
  DateTime? _lastFrame;
  bool _noRoute = false;

  /// The current plugin state.
  PluginState get state {
    final fromHello = _helloState;
    if (fromHello != null) return fromHello;
    final since = _simKnownAt;
    if (since == null) return const PluginStateUnknown();
    return clock.now().difference(since) >= notDetectedAfter
        ? PluginStateNotDetected(noRoute: _noRoute)
        : const PluginStateUnknown();
  }

  /// Records whether every probe of the latest round failed with errno 65.
  void probeRound({required bool noRoute}) => _noRoute = noRoute;

  /// Whether a started stream has been silent for [staleAfter] or more.
  bool get isStale {
    final last = _lastFrame;
    return last != null && clock.now().difference(last) >= staleAfter;
  }

  /// The sim's address is known now; the handshake window opens. Calling it
  /// again while the window is open does not restart it.
  void simKnown() => _simKnownAt ??= clock.now();

  /// A hello arrived from [port]. The latest hello wins.
  void onHello(int port, RawHello hello) {
    _noRoute = false;
    _helloState = hello.protocolVersion == requiredProtocolVersion
        ? PluginStateReady(port)
        : PluginStateVersionMismatch(
            found: hello.protocolVersion,
            required: requiredProtocolVersion,
          );
  }

  /// The plugin stopped answering; the window opens again from now.
  void lostPlugin() {
    _helloState = null;
    _simKnownAt = clock.now();
  }

  /// Any stream frame arrived (values, heartbeat or pong).
  void onFrame() => _lastFrame = clock.now();

  /// The stream closed, so silence is no longer judged.
  void streamClosed() => _lastFrame = null;

  /// Forgets everything (a different sim, or a restart).
  void reset() {
    _simKnownAt = null;
    _helloState = null;
    _lastFrame = null;
    _noRoute = false;
  }
}
