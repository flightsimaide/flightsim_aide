import 'dart:async';
import 'dart:io';

import '../../../domain/models/flight_sim/dataref.dart';
import '../../../utils/app_exception.dart';
import '../../../utils/clock.dart';
import '../../../utils/result.dart';
import 'companion_plugin_service.dart';
import 'flight_sim_service.dart';
import 'model/plugin_endpoint.dart';
import 'model/raw_frame.dart';
import 'model/raw_hello.dart';
import 'model/raw_signal_message.dart';
import 'model/signal_spec.dart';
import 'model/sim_endpoint.dart';
import 'plugin_state.dart';
import 'plugin_state_tracker.dart';
import 'stream_codec.dart';

/// The plugin's preferred port and the seven after it.
const defaultPluginPorts = [
  18086,
  18087,
  18088,
  18089,
  18090,
  18091,
  18092,
  18093,
];

/// Opens a WebSocket; injected so tests can count and fail attempts.
typedef WebSocketConnector = Future<WebSocket> Function(Uri uri);

/// Wait before the 1st, 2nd and later reconnect attempts.
const _backoff = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 5),
];

/// [FlightSimService] over the companion plugin: probes `/v1/hello` on the
/// port range, opens `/v1/stream`, subscribes the configured signals and
/// reconnects with back-off when the connection closes or goes silent.
class FlightSimConnectionService implements FlightSimService {
  /// Creates the service.
  ///
  /// [ports] is read at every probe, so a caller may change it. A hello that
  /// takes longer than [probeTimeout] counts as no answer.
  FlightSimConnectionService({
    required this.companion,
    this.clock = const SystemClock(),
    this.ports = defaultPluginPorts,
    this.signalSpecs = defaultSignals,
    this.probeTimeout = const Duration(seconds: 1),
    WebSocketConnector? connectWebSocket,
  }) : _connectWebSocket =
           connectWebSocket ?? ((uri) => WebSocket.connect(uri.toString())),
       _tracker = PluginStateTracker(clock: clock);

  /// The HTTP side, used for the hello probe.
  final CompanionPluginService companion;

  /// The time source.
  final Clock clock;

  /// The ports to probe.
  final List<int> ports;

  /// The signals to subscribe; the list index is the subscription id.
  final List<SignalSpec> signalSpecs;

  /// How long one hello probe may take.
  final Duration probeTimeout;

  final WebSocketConnector _connectWebSocket;
  final PluginStateTracker _tracker;

  final _signals = StreamController<RawSignalMessage>.broadcast();
  final _states = StreamController<PluginState>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  final _unavailable = StreamController<String>.broadcast();
  final _unavailableNames = <String>{};

  /// The names to receive besides [signalSpecs], with their rates.
  final Map<String, int> _watched = {};

  /// On the open socket: the subscription id of each watched name, and back.
  final Map<String, int> _watchedIds = {};
  final Map<int, String> _idNames = {};

  /// For a wire name that is a range `base[a..b]`: the watched element names
  /// it stands for, in order. A single name has no entry.
  final Map<String, List<String>> _rangeMembers = {};

  /// Set when the plugin refused a range (a plugin older than 0.3.0): the
  /// elements then go one by one for the rest of this connection.
  bool _noRanges = false;
  int _nextId = 0;

  SimEndpoint? _sim;
  PluginEndpoint? _pluginEndpoint;
  String? _runId;
  String? _simKind;
  PluginState _state = const PluginStateUnknown();
  bool _streamUp = false;
  bool _paused = false;
  bool _disposed = false;
  int _session = 0;
  int _failures = 0;
  WebSocket? _socket;
  StreamSubscription<Object?>? _socketSubscription;
  Timer? _staleTimer;
  Timer? _retryTimer;
  Timer? _notDetectedTimer;

  @override
  Stream<RawSignalMessage> get signals => _signals.stream;

  /// The plugin's limit per connection (`PROTOCOL.md` section 9). A range
  /// subscription counts once.
  static const pluginSubscriptionLimit = 128;

  @override
  int get maxWatched => pluginSubscriptionLimit - signalSpecs.length;

  @override
  List<String> fit(List<String> names) {
    final fixed = {for (final s in signalSpecs) s.name};
    bool fits(int count) {
      final plan = _planFor({
        for (final n in names.take(count))
          if (!fixed.contains(n)) n: 1,
      });
      return plan.length <= maxWatched;
    }

    if (fits(names.length)) return List.of(names);
    var low = 0; // fits
    var high = names.length; // does not fit
    while (high - low > 1) {
      final mid = (low + high) ~/ 2;
      if (fits(mid)) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return names.take(low).toList();
  }

  @override
  void watchSignals(Map<String, int> namesAtHz) {
    final fixed = {for (final s in signalSpecs) s.name};
    final kept = fit(namesAtHz.keys.toList()).toSet();
    final wanted = <String, int>{
      for (final e in namesAtHz.entries)
        if (kept.contains(e.key) && !fixed.contains(e.key)) e.key: e.value,
    };
    _watched
      ..clear()
      ..addAll(wanted);
    final socket = _socket;
    if (socket == null) return;
    _applyWatches(socket);
  }

  /// Brings the subscriptions on [socket] in line with [_watched]: elements
  /// of one array that are consecutive and have the same rate share one range
  /// subscription `base[a..b]` (the plugin sends them as one list), any other
  /// name its own.
  void _applyWatches(WebSocket socket) {
    final plan = _plan();
    for (final name in _watchedIds.keys.toList()) {
      if (plan.containsKey(name)) continue;
      final id = _watchedIds.remove(name)!;
      _idNames.remove(id);
      _rangeMembers.remove(name);
      socket.add(encodeUnsubscribe(id));
    }
    for (final e in plan.entries) {
      _sendWatch(socket, e.key, e.value.hz, e.value.members);
    }
  }

  /// The wire subscriptions for [_watched], by wire name.
  Map<String, ({int hz, List<String> members})> _plan() => _planFor(_watched);

  Map<String, ({int hz, List<String> members})> _planFor(
    Map<String, int> watched,
  ) {
    final plan = <String, ({int hz, List<String> members})>{};
    final elements = <(String, int), Map<int, String>>{};
    for (final e in watched.entries) {
      final dataref = _noRanges ? null : Dataref.tryParse(e.key);
      final index = dataref?.index;
      if (dataref == null || index == null) {
        plan[e.key] = (hz: e.value, members: [e.key]);
        continue;
      }
      (elements[(dataref.name, e.value)] ??= {})[index] = e.key;
    }
    for (final group in elements.entries) {
      final (base, hz) = group.key;
      final indexes = group.value.keys.toList()..sort();
      var i = 0;
      while (i < indexes.length) {
        var j = i;
        while (j + 1 < indexes.length &&
            indexes[j + 1] == indexes[j] + 1 &&
            j + 1 - i < kMaxRangeElements) {
          j++;
        }
        final members = [for (var k = i; k <= j; k++) group.value[indexes[k]]!];
        final wire = j == i
            ? members.single
            : '$base[${indexes[i]}..${indexes[j]}]';
        plan[wire] = (hz: hz, members: members);
        i = j + 1;
      }
    }
    return plan;
  }

  /// The most elements one range may cover (`PROTOCOL.md` section 9).
  static const kMaxRangeElements = 128;

  /// Subscribes [name] (or re-subscribes it at a new rate under its id).
  /// [members] are the element names behind a range.
  void _sendWatch(WebSocket socket, String name, int hz, List<String> members) {
    final known = _watchedIds[name];
    final id = known ?? _nextId++;
    try {
      socket.add(encodeSubscribe(id, name, hz));
    } on ArgumentError {
      if (known == null) _nextId--;
      for (final member in members) {
        if (_unavailableNames.add(member)) _unavailable.add(member);
      }
      return;
    }
    _watchedIds[name] = id;
    _idNames[id] = name;
    if (members.length > 1) {
      _rangeMembers[name] = members;
    } else {
      _rangeMembers.remove(name);
    }
    _watchedRates[name] = hz;
  }

  final Map<String, int> _watchedRates = {};

  @override
  Stream<PluginState> get pluginStates => _states.stream;

  @override
  PluginState get pluginState => _state;

  @override
  Stream<bool> get streamConnected => _connected.stream;

  @override
  bool get isStreamConnected => _streamUp;

  @override
  Stream<String> get unavailableSignals => _unavailable.stream;

  @override
  PluginEndpoint? get pluginEndpoint => _pluginEndpoint;

  @override
  String? get runId => _runId;

  @override
  String? get simKind => _simKind;

  @override
  Future<void> connect(SimEndpoint sim) async {
    if (_disposed) return;
    await _stop();
    _sim = sim;
    _paused = false;
    await _begin();
  }

  @override
  Future<RawHello?> peekHello(SimEndpoint sim) async {
    for (final host in sim.hosts) {
      final found = await _probe(host, track: false);
      if (_disposed) return null;
      if (found != null) return found.$2;
    }
    return null;
  }

  @override
  Future<void> disconnect() async {
    await _stop();
    _sim = null;
    _pluginEndpoint = null;
    _runId = null;
    _simKind = null;
    _tracker.reset();
    _publishState();
  }

  @override
  Future<void> pause() async {
    if (_paused) return;
    _paused = true;
    await _stop();
  }

  @override
  Future<void> resume() async {
    if (_disposed || !_paused || _sim == null) return;
    _paused = false;
    await _begin();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await disconnect();
    _disposed = true;
    await _signals.close();
    await _states.close();
    await _connected.close();
    await _unavailable.close();
  }

  /// Starts from scratch against [_sim]: new window, new attempt count.
  Future<void> _begin() {
    _failures = 0;
    _tracker
      ..reset()
      ..simKnown();
    _publishState();
    _armNotDetected();
    return _attempt();
  }

  bool _alive(int token) => token == _session && !_paused && !_disposed;

  Future<void> _attempt() async {
    final sim = _sim;
    if (sim == null || _paused || _disposed) return;
    final token = ++_session;
    await _closeSocket();
    String? host;
    (int, RawHello)? found;
    for (final candidate in sim.hosts) {
      found = await _probe(candidate);
      if (!_alive(token)) return;
      if (found != null) {
        host = candidate;
        break;
      }
    }
    if (found == null || host == null) {
      if (_state is PluginStateReady) {
        _tracker.lostPlugin();
        _armNotDetected();
      }
      _publishState();
      _scheduleRetry();
      return;
    }
    final (port, hello) = found;
    _notDetectedTimer?.cancel();
    _publishState();
    if (_state is PluginStateVersionMismatch) return;
    final WebSocket socket;
    try {
      socket = await _connectWebSocket(
        Uri(scheme: 'ws', host: host, port: port, path: hello.streamPath),
      );
    } on Object {
      if (_alive(token)) _scheduleRetry();
      return;
    }
    if (!_alive(token)) {
      unawaited(socket.close().then((_) {}, onError: (Object _) {}));
      return;
    }
    _pluginEndpoint = PluginEndpoint(host: host, port: port);
    _runId = hello.runId;
    _simKind = hello.simKind;
    _socket = socket;
    _tracker.onFrame();
    _unavailableNames.clear();
    _watchedIds.clear();
    _idNames.clear();
    _rangeMembers.clear();
    _noRanges = false;
    _watchedRates.clear();
    _nextId = signalSpecs.length;
    for (var id = 0; id < signalSpecs.length; id++) {
      final spec = signalSpecs[id];
      socket.add(encodeSubscribe(id, spec.name, spec.hz));
    }
    _applyWatches(socket);
    _socketSubscription = socket.listen(
      (data) => _onData(token, data),
      onDone: () => _onClosed(token),
      onError: (Object _) => _onClosed(token),
    );
    _staleTimer = clock.periodic(const Duration(seconds: 1), (_) {
      if (_tracker.isStale) _onClosed(token);
    });
  }

  /// Probes every port in parallel. Returns the first valid answer with its
  /// port, or null when none answered (also when all timed out).
  Future<(int, RawHello)?> _probe(String host, {bool track = true}) {
    final probed = List.of(ports);
    if (probed.isEmpty) return Future.value();
    final done = Completer<(int, RawHello)?>();
    var pending = probed.length;
    var noRoute = 0;
    for (final port in probed) {
      companion
          .getHello(host, port)
          .timeout(probeTimeout, onTimeout: () => Error(PluginUnreachable()))
          .then((result) {
            if (result case Ok(:final value) when !done.isCompleted) {
              if (track) _tracker.onHello(port, value);
              done.complete((port, value));
            }
            if (result
                case Error(error: PluginUnreachable(:final noRouteToHost))
                when noRouteToHost) {
              noRoute++;
            }
            if (--pending == 0 && !done.isCompleted) {
              if (track) {
                _tracker.probeRound(noRoute: noRoute == probed.length);
              }
              done.complete(null);
            }
          });
    }
    return done.future;
  }

  void _onData(int token, Object? data) {
    if (!_alive(token) || data is! String) return;
    final frame = decodeFrame(data);
    if (frame == null) return;
    _tracker.onFrame();
    if (!_streamUp) {
      _failures = 0;
      _setStreamUp(true);
    }
    switch (frame) {
      case Values(:final time, :final values, :final lists):
        for (final MapEntry(:key, :value) in values.entries) {
          final name = _nameOf(key);
          if (name == null) continue;
          _signals.add(
            RawSignalMessage(
              subscriptionId: key,
              name: name,
              value: value,
              sampleTime: time,
            ),
          );
        }
        for (final MapEntry(:key, value: list) in lists.entries) {
          final members = _rangeMembers[_nameOf(key)];
          if (members == null) continue;
          // An element past the end of the array is missing from the list.
          for (var k = 0; k < members.length; k++) {
            _signals.add(
              RawSignalMessage(
                subscriptionId: key,
                name: members[k],
                value: k < list.length ? list[k] : null,
                sampleTime: time,
              ),
            );
          }
        }
      case StreamError(:final code, :final id):
        final name = id == null ? null : _nameOf(id);
        if (name == null) break;
        final members = _rangeMembers[name];
        if (members != null && code == 'bad_request' && !_noRanges) {
          // A plugin older than 0.3.0 does not know ranges: go element by
          // element.
          _noRanges = true;
          final socket = _socket;
          if (socket != null) {
            _idNames.remove(_watchedIds.remove(name));
            _rangeMembers.remove(name);
            _applyWatches(socket);
          }
        } else if (code == 'unknown_name' ||
            code == 'unsupported' ||
            code == 'limit') {
          for (final member in members ?? [name]) {
            if (_unavailableNames.add(member)) _unavailable.add(member);
          }
        }
      case Subscribed() || Heartbeat() || Pong():
        break;
    }
  }

  /// The signal behind subscription [id]: a fixed one or a watched name.
  String? _nameOf(int id) {
    if (id < 0) return null;
    if (id < signalSpecs.length) return signalSpecs[id].name;
    return _idNames[id];
  }

  void _onClosed(int token) {
    if (!_alive(token)) return;
    _session++;
    unawaited(_closeSocket());
    _setStreamUp(false);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay =
        _backoff[_failures < _backoff.length ? _failures : _backoff.length - 1];
    _failures++;
    _retryTimer = clock.timer(delay, () {
      _retryTimer = null;
      unawaited(_attempt());
    });
  }

  void _armNotDetected() {
    _notDetectedTimer?.cancel();
    _notDetectedTimer = clock.timer(_tracker.notDetectedAfter, _publishState);
  }

  void _publishState() {
    if (_disposed) return;
    final next = _tracker.state;
    if (next == _state) return;
    _state = next;
    _states.add(next);
  }

  void _setStreamUp(bool up) {
    if (_streamUp == up || _disposed) return;
    _streamUp = up;
    _connected.add(up);
  }

  /// Cancels every timer, invalidates running attempts and closes the socket.
  Future<void> _stop() async {
    _session++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _notDetectedTimer?.cancel();
    _notDetectedTimer = null;
    await _closeSocket();
    _setStreamUp(false);
  }

  Future<void> _closeSocket() async {
    _staleTimer?.cancel();
    _staleTimer = null;
    _tracker.streamClosed();
    final subscription = _socketSubscription;
    _socketSubscription = null;
    final socket = _socket;
    _socket = null;
    await subscription?.cancel();
    if (socket != null) {
      unawaited(socket.close().then((_) {}, onError: (Object _) {}));
    }
  }
}
