import 'dart:convert';

/// A clock the engine reads, so tests can use fake time.
typedef Now = DateTime Function();

/// The reserved signal that follows the aircraft generation.
const generationSignal = 'flightsim_aide/aircraft_generation';

/// One connected stream client as the engine sees it.
class FakeStreamClient {
  FakeStreamClient._(this._send, DateTime now) : _lastFrameAt = now;

  final void Function(String frame) _send;
  final List<_Sub> _subs = [];
  final List<_Pending> _pending = [];
  DateTime _lastFrameAt;
}

class _Sub {
  _Sub(this.id, this.name, this.hz, this.nextDue);
  final int id;
  final String name;
  final int hz;
  DateTime nextDue;
  Duration get period => Duration(microseconds: 1000000 ~/ hz);
}

class _Pending {
  _Pending(this.id, this.name, this.hz, this.readyAt);
  final int id;
  final String name;
  final int hz;
  final DateTime readyAt;
}

/// The stream half of the protocol (`plugin/PROTOCOL.md` section 7) with no
/// sockets: frames in, frames out, driven by [tick] and an injectable clock.
///
/// The plugin core's stream module and the real plugin must behave the same
/// way for the shared cases in `testing/fixtures/protocol/stream_cases.json`.
class FakePluginStreamEngine {
  FakePluginStreamEngine({
    Now? now,
    Map<String, num>? signals,
    Map<String, List<num>>? arrays,
    Set<String>? unsupported,
  }) : _now = now ?? DateTime.now,
       signals = {...?signals},
       arrays = {...?arrays},
       unsupported = {...?unsupported};

  /// Subscriptions per connection (`plugin/PROTOCOL.md` section 9).
  static const maxSubscriptions = 128;
  static const maxFrameBytes = 4096;
  static const heartbeatAfter = Duration(seconds: 1);

  final Now _now;

  /// Values by signal name. A name not in here is `unknown_name`.
  final Map<String, num> signals;

  /// Array datarefs by base name. `base[n]` reads element n; an index past the
  /// end is accepted and reads `null`; the bare base name is `unsupported`.
  /// `base[a..b]` reads the list of those elements that exist.
  final Map<String, List<num>> arrays;

  /// Names the plugin knows but cannot read as one number.
  final Set<String> unsupported;

  /// Extra time a subscribe waits before it is acknowledged (fault hook).
  Duration ackDelay = Duration.zero;

  /// Whether `base[a..b]` is understood. False imitates a plugin older than
  /// 0.3.0, which answers a range `bad_request`.
  bool supportRanges = true;

  /// When true no frame is sent at all (fault hook for the stale rule).
  bool silenced = false;

  final List<FakeStreamClient> _clients = [];

  /// How many clients are connected.
  int get clientCount => _clients.length;

  /// How many subscriptions are active or waiting for their acknowledgement,
  /// over all clients.
  int get subscriptionCount =>
      _clients.fold(0, (n, c) => n + c._subs.length + c._pending.length);

  /// Adds a client; [send] receives every server frame as JSON text.
  FakeStreamClient addClient(void Function(String frame) send) {
    final c = FakeStreamClient._(send, _now());
    _clients.add(c);
    return c;
  }

  void removeClient(FakeStreamClient client) => _clients.remove(client);

  /// Sets a signal. A change of [generationSignal] is sent at once to every
  /// subscriber, in addition to its periodic frames.
  void setSignal(String name, num value) {
    final changed = signals[name] != value;
    signals[name] = value;
    if (changed && name == generationSignal) {
      for (final c in _clients) {
        final v = <String, Object?>{
          for (final s in c._subs.where((s) => s.name == name))
            '${s.id}': _number(value),
        };
        if (v.isNotEmpty) _values(c, v);
      }
    }
  }

  /// Handles one client frame.
  void receive(FakeStreamClient client, String frame) {
    if (utf8.encode(frame).length > maxFrameBytes) {
      _error(client, null, 'bad_request', 'Frame is larger than 4 KB.');
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(frame);
    } on FormatException {
      _error(client, null, 'bad_request', 'Frame is not JSON.');
      return;
    }
    if (decoded is! Map<String, Object?> || decoded['op'] is! String) {
      _error(client, null, 'bad_request', 'Frame needs an op.');
      return;
    }
    final rawId = decoded['id'];
    final int? id = rawId is int && rawId >= 0 ? rawId : null;
    switch (decoded['op']! as String) {
      case 'subscribe':
        _subscribe(client, id, decoded);
      case 'unsubscribe':
        if (id == null) {
          _error(client, null, 'bad_request', 'unsubscribe needs an id.');
          break;
        }
        client._subs.removeWhere((s) => s.id == id);
        client._pending.removeWhere((p) => p.id == id);
      case 'ping':
        _send(client, {'op': 'pong'});
      case 'set':
        _error(client, id, 'unsupported', 'Writes are not supported.');
      default:
        _error(client, id, 'bad_request', 'Unknown op.');
    }
  }

  void _subscribe(FakeStreamClient c, int? id, Map<String, Object?> frame) {
    final name = frame['name'];
    final hz = frame['hz'];
    final nameOk =
        name is String &&
        name.isNotEmpty &&
        name.length <= 200 &&
        !name.codeUnits.any((u) => u < 0x20 || u == 0x7f);
    if (id == null ||
        !nameOk ||
        hz is! int ||
        hz < 1 ||
        hz > 60 ||
        !_parseName(name).ok ||
        (!supportRanges && _parseName(name).last != null)) {
      _error(c, id, 'bad_request', 'Invalid subscribe.');
      return;
    }
    final replacing =
        c._subs.any((s) => s.id == id) || c._pending.any((p) => p.id == id);
    if (!replacing && c._subs.length + c._pending.length >= maxSubscriptions) {
      _error(c, id, 'limit', 'At most $maxSubscriptions subscriptions.');
      return;
    }
    c._subs.removeWhere((s) => s.id == id);
    c._pending.removeWhere((p) => p.id == id);
    c._pending.add(_Pending(id, name, hz, _now().add(ackDelay)));
  }

  /// One flight-loop tick: resolves pending subscribes, then sends what is
  /// due and a heartbeat after a second of silence.
  void tick() {
    final now = _now();
    for (final c in List.of(_clients)) {
      for (final p
          in c._pending.where((p) => !p.readyAt.isAfter(now)).toList()) {
        c._pending.remove(p);
        final parsed = _parseName(p.name);
        final known = parsed.index == null
            ? signals.containsKey(p.name)
            : arrays.containsKey(parsed.base);
        if (parsed.index == null &&
            (unsupported.contains(p.name) || arrays.containsKey(p.name))) {
          _error(c, p.id, 'unsupported', 'Not a single number.');
        } else if (!known) {
          _error(c, p.id, 'unknown_name', 'No such signal.');
        } else {
          c._subs.add(_Sub(p.id, p.name, p.hz, now));
          _send(c, {'op': 'subscribed', 'id': p.id});
        }
      }
      final v = <String, Object?>{};
      for (final s in c._subs) {
        if (s.nextDue.isAfter(now)) continue;
        v['${s.id}'] = _read(s.name);
        var next = s.nextDue.add(s.period);
        if (!next.isAfter(now)) next = now.add(s.period);
        s.nextDue = next;
      }
      if (v.isNotEmpty) {
        _values(c, v);
      } else if (now.difference(c._lastFrameAt) >= heartbeatAfter) {
        c._lastFrameAt = now;
        _send(c, {'op': 'hb'});
      }
    }
  }

  /// `base`, `base[n]` and the range `base[a..b]` (decimal digits, at most 6
  /// each, `a <= b`, at most 128 elements); anything else with a bracket in
  /// it is not [ok].
  static ({bool ok, String base, int? index, int? last}) _parseName(
    String name,
  ) {
    final m = RegExp(r'^(.*)\[(\d{1,6})(?:\.\.(\d{1,6}))?\]$').firstMatch(name);
    final base = m == null ? name : m.group(1)!;
    if (base.contains('[') || base.contains(']')) {
      return (ok: false, base: name, index: null, last: null);
    }
    final first = m == null ? null : int.parse(m.group(2)!);
    final last = m?.group(3) == null ? null : int.parse(m!.group(3)!);
    if (last != null &&
        (last < first! || last - first + 1 > maxSubscriptions)) {
      return (ok: false, base: name, index: null, last: null);
    }
    return (ok: true, base: base, index: first, last: last);
  }

  Object? _read(String name) {
    final p = _parseName(name);
    if (p.index == null) return _number(signals[name]!);
    final list = arrays[p.base]!;
    if (p.last != null) {
      // A range: the elements that exist, cut short where the array ends.
      return [
        for (var i = p.index!; i <= p.last! && i < list.length; i++)
          _number(list[i]),
      ];
    }
    return p.index! < list.length ? _number(list[p.index!]) : null;
  }

  void _values(FakeStreamClient c, Map<String, Object?> v) {
    c._lastFrameAt = _now();
    _send(c, {
      'op': 'values',
      't': c._lastFrameAt.millisecondsSinceEpoch,
      'v': v,
    });
  }

  void _error(FakeStreamClient c, int? id, String code, String message) {
    _send(c, {'op': 'error', 'id': ?id, 'code': code, 'message': message});
  }

  void _send(FakeStreamClient c, Map<String, Object?> frame) {
    if (silenced) return;
    c._send(jsonEncode(frame));
  }

  /// Integers stay integers, non-finite numbers become null.
  static Object? _number(num v) => v is double && !v.isFinite ? null : v;
}
