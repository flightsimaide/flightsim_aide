import 'dart:async';

import '../../../utils/clock.dart';
import 'model/raw_signal_message.dart';
import 'signal_source.dart';

/// A [SignalSource] with no sockets: values are set from code, scripted on a
/// timeline or drifted slowly, so the app can be run and tested without a
/// sim (task 5.5). It backs `FlightSimRepositoryLocal`.
class SimulatedSignalSource implements SignalSource {
  /// Creates the source. It re-sends every watched value each [period], the
  /// way the plugin does; the watch hub keeps only what changed.
  SimulatedSignalSource({
    this.clock = const SystemClock(),
    this.period = const Duration(milliseconds: 100),
    this.maxWatched = 126,
    this.initiallyConnected = true,
  }) : _connected = initiallyConnected;

  /// Time and timers.
  final Clock clock;

  /// How often the watched values are re-sent.
  final Duration period;

  /// Whether the link starts up.
  final bool initiallyConnected;

  @override
  final int maxWatched;

  @override
  List<String> fit(List<String> names) => names.take(maxWatched).toList();

  final _signals = StreamController<RawSignalMessage>.broadcast(sync: true);
  final _unavailable = StreamController<String>.broadcast(sync: true);
  final _connectedChanges = StreamController<bool>.broadcast(sync: true);
  final _values = <String, double?>{};
  final _rejected = <String>{};
  final _ids = <String, int>{};
  final _timers = <Timer>[];
  Map<String, int> _watched = {};
  Timer? _tick;
  bool _connected;
  int _nextId = 0;

  /// Every set passed to [watchSignals], in order.
  final List<Map<String, int>> watchCalls = [];

  /// Sets the value of [name] now; null is a value the sim could not give.
  void setValue(String name, double? value) => _values[name] = value;

  /// Makes the source answer `unknown_name` for [name].
  void reject(String name) {
    _rejected.add(name);
    if (_watched.containsKey(name)) _unavailable.add(name);
  }

  /// Sets [name] to [value] after [after] (a script: call it several times).
  void schedule(Duration after, String name, double? value) {
    _timers.add(clock.timer(after, () => setValue(name, value)));
  }

  /// Moves [name] from [from] to [to] in steps of [step] every [every]: a slow
  /// change, such as a gauge settling.
  void drift(
    String name, {
    required double from,
    required double to,
    required double step,
    Duration every = const Duration(seconds: 1),
  }) {
    var value = from;
    _values[name] = value;
    _timers.add(
      clock.periodic(every, (timer) {
        if (value == to) {
          timer.cancel();
          return;
        }
        value = to > value
            ? (value + step > to ? to : value + step)
            : (value - step < to ? to : value - step);
        _values[name] = value;
      }),
    );
  }

  /// Opens or closes the simulated link.
  void setConnected(bool up) {
    if (up == _connected) return;
    _connected = up;
    if (up) _rejected.clear();
    _connectedChanges.add(up);
  }

  @override
  Stream<RawSignalMessage> get signals => _signals.stream;

  @override
  Stream<String> get unavailableSignals => _unavailable.stream;

  @override
  Stream<bool> get streamConnected => _connectedChanges.stream;

  @override
  bool get isStreamConnected => _connected;

  @override
  void watchSignals(Map<String, int> namesAtHz) {
    watchCalls.add(Map.of(namesAtHz));
    final fresh = [
      for (final n in namesAtHz.keys)
        if (!_watched.containsKey(n)) n,
    ];
    _watched = Map.of(namesAtHz);
    _tick ??= clock.periodic(period, (_) => _send());
    for (final n in fresh) {
      if (_rejected.contains(n)) _unavailable.add(n);
    }
  }

  void _send() {
    if (!_connected) return;
    final at = clock.now().millisecondsSinceEpoch;
    for (final name in _watched.keys) {
      if (_rejected.contains(name)) continue;
      _signals.add(
        RawSignalMessage(
          subscriptionId: _ids.putIfAbsent(name, () => _nextId++),
          name: name,
          value: _values[name],
          sampleTime: at,
        ),
      );
    }
  }

  /// Releases the timers and streams.
  Future<void> dispose() async {
    _tick?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    await _signals.close();
    await _unavailable.close();
    await _connectedChanges.close();
  }
}
