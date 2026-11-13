import 'dart:async';

import '../../../domain/models/flight_sim/dataref.dart';
import '../../../domain/models/flight_sim/dataref_value.dart';
import '../../../utils/clock.dart';
import '../../services/flight_sim/model/raw_signal_message.dart';
import '../../services/flight_sim/signal_source.dart';
import '../settings/settings_repository.dart';
import 'dataref_watch.dart';

/// Turns a [SignalSource] into [DatarefWatch]es: one subscription per name
/// (reference counted), values throttled to the stream rate option and
/// coalesced, unavailable names remembered, everything unknown while the
/// stream is down (tasks 5.4 to 5.10).
class DatarefWatchHub {
  /// Creates the hub and starts listening to [source] and the options.
  DatarefWatchHub({
    required this.source,
    required this.settings,
    this.clock = const SystemClock(),
    this.releaseDelay = const Duration(seconds: 2),
  }) : _rateHz = settings.options.streamRateHz {
    _subs
      ..add(source.signals.listen(_onSignal))
      ..add(source.unavailableSignals.listen(_onUnavailable))
      ..add(source.streamConnected.listen(_onConnected))
      ..add(settings.optionsChanges.listen(_onOptions));
    _startTimer();
  }

  /// The live link.
  final SignalSource source;

  /// Where the stream rate option lives.
  final SettingsRepository settings;

  /// How long a name nobody watches stays subscribed, so a quick return to a
  /// screen does not unsubscribe and subscribe again.
  final Duration releaseDelay;

  /// Time and timers.
  final Clock clock;

  final _subs = <StreamSubscription<Object?>>[];
  final _watches = <_Watch>[];
  final _refs = <String, int>{}; // insertion order = first watched first
  final _releaseTimers = <String, Timer>{};
  final _latest = <String, DatarefValue>{};
  final _dirty = <String>{};
  final _rejected = <String>{}; // reported by the plugin on this connection
  Set<String> _capped = {}; // watched but past the limit
  Timer? _tick;
  int _rateHz;
  bool _disposed = false;

  /// The rate in use, values per second.
  int get rateHz => _rateHz;

  /// Names currently subscribed (or about to be), in subscription order.
  List<String> get subscribedNames => [
    for (final e in _refs.entries)
      if (e.value > 0) e.key,
  ];

  /// Opens a watch over [datarefs].
  DatarefWatch watch(Iterable<Dataref> datarefs) {
    final watch = _Watch(this, datarefs.toSet());
    _watches.add(watch);
    var changed = false;
    for (final d in watch.datarefs) {
      final name = d.wireName;
      _releaseTimers.remove(name)?.cancel();
      changed |= !_refs.containsKey(name);
      _refs[name] = (_refs[name] ?? 0) + 1;
    }
    if (changed) _resubscribe();
    watch.unavailable = _unavailableOf(watch);
    return watch;
  }

  void _unwatch(_Watch watch) {
    if (!_watches.remove(watch)) return;
    for (final d in watch.datarefs) {
      final name = d.wireName;
      final left = (_refs[name] ?? 1) - 1;
      _refs[name] = left;
      if (left == 0) {
        _releaseTimers[name]?.cancel();
        _releaseTimers[name] = clock.timer(releaseDelay, () {
          _releaseTimers.remove(name);
          if (_refs[name] != 0) return;
          _refs.remove(name);
          _latest.remove(name);
          _dirty.remove(name);
          _rejected.remove(name);
          _resubscribe();
        });
      }
    }
  }

  void _resubscribe() {
    if (_disposed) return;
    final names = subscribedNames;
    final fit = source.fit(names.toList());
    _capped = names.skip(fit.length).toSet();
    source.watchSignals({for (final n in fit) n: _rateHz});
    _refreshUnavailable();
  }

  void _onSignal(RawSignalMessage m) {
    if ((_refs[m.name] ?? 0) <= 0) return;
    final n = m.value?.toDouble();
    final at = DateTime.fromMillisecondsSinceEpoch(m.sampleTime, isUtc: true);
    final next = n == null ? DatarefValue.unknown(at) : DatarefValue(n, at);
    final old = _latest[m.name];
    _latest[m.name] = next;
    if (old == null || old.number != next.number) _dirty.add(m.name);
  }

  void _onUnavailable(String name) {
    if ((_refs[name] ?? 0) <= 0 || !_rejected.add(name)) return;
    _setUnknown(name);
    _refreshUnavailable();
  }

  void _onConnected(bool up) {
    if (up) {
      _rejected.clear();
      _refreshUnavailable();
      return;
    }
    for (final name in _refs.keys) {
      _setUnknown(name);
    }
  }

  void _setUnknown(String name) {
    final old = _latest[name];
    if (old != null && !old.isKnown) return;
    _latest[name] = const DatarefValue.unknown();
    _dirty.add(name);
  }

  void _onOptions(Object options) {
    final hz = settings.options.streamRateHz;
    if (hz == _rateHz) return;
    _rateHz = hz;
    _startTimer();
    _resubscribe();
  }

  void _startTimer() {
    _tick?.cancel();
    _tick = clock.periodic(
      Duration(milliseconds: (1000 / _rateHz).round()),
      (_) => _flush(),
    );
  }

  void _flush() {
    if (_dirty.isEmpty) return;
    final dirty = Set<String>.of(_dirty);
    _dirty.clear();
    for (final w in List.of(_watches)) {
      final batch = <Dataref, DatarefValue>{
        for (final d in w.datarefs)
          if (dirty.contains(d.wireName))
            d: _latest[d.wireName] ?? const DatarefValue.unknown(),
      };
      if (batch.isNotEmpty) w.push(batch);
    }
  }

  Set<Dataref> _unavailableOf(_Watch w) => {
    for (final d in w.datarefs)
      if (_rejected.contains(d.wireName) || _capped.contains(d.wireName)) d,
  };

  void _refreshUnavailable() {
    for (final w in _watches) {
      final next = _unavailableOf(w);
      if (next.length == w.unavailable.length &&
          next.containsAll(w.unavailable)) {
        continue;
      }
      w.unavailable = next;
      w.announce();
    }
  }

  DatarefValue _valueOf(Dataref d) =>
      _latest[d.wireName] ?? const DatarefValue.unknown();

  /// Releases everything.
  Future<void> dispose() async {
    _disposed = true;
    _tick?.cancel();
    for (final t in _releaseTimers.values) {
      t.cancel();
    }
    for (final s in _subs) {
      await s.cancel();
    }
    for (final w in List.of(_watches)) {
      w.release();
    }
    _watches.clear();
  }
}

class _Watch implements DatarefWatch {
  _Watch(this._hub, this.datarefs);

  final DatarefWatchHub _hub;
  final Set<Dataref> datarefs;
  final _batches = StreamController<Map<Dataref, DatarefValue>>.broadcast();
  final _unavailableChanges = StreamController<Set<Dataref>>.broadcast();
  bool _released = false;

  @override
  Set<Dataref> unavailable = {};

  @override
  Stream<Map<Dataref, DatarefValue>> get batches => _batches.stream;

  @override
  Stream<Set<Dataref>> get unavailableChanges => _unavailableChanges.stream;

  @override
  Map<Dataref, DatarefValue> get current => {
    for (final d in datarefs) d: _hub._valueOf(d),
  };

  void push(Map<Dataref, DatarefValue> batch) {
    if (!_released) _batches.add(batch);
  }

  void announce() {
    if (!_released) _unavailableChanges.add(Set.of(unavailable));
  }

  @override
  void release() {
    if (_released) return;
    _released = true;
    _hub._unwatch(this);
    unawaited(_batches.close());
    unawaited(_unavailableChanges.close());
  }
}
