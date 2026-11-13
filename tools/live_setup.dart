// Sets the sim state that `protocol_contract.dart --live` reads, through
// X-Plane 12's web API (port 8086), so no value is set by hand, and puts the
// old values back afterwards.
//
//   dart run tools/live_setup.dart [--api http://127.0.0.1:8086] [--keep]
//
// Use it with an aircraft loaded and parked. It remembers each dataref's old
// value, writes the new one, reads it back and exits non-zero when a value did
// not hold (a read-only dataref, or the sim overwrote it). Without `--keep` it
// then restores the old values. The written values are in [liveState];
// `protocol_contract.dart` calls [applySimState] itself and restores in a
// `finally`, so the two cannot drift apart.
//
// The contract does not assume how long an array is or what an aircraft keeps
// in it: it reads the array back through the same API ([readArray]) and
// derives what the plugin must answer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One dataref element to write. [index] is null for a scalar.
class SimValue {
  const SimValue(this.name, this.value, {this.index});

  final String name;
  final num value;
  final int? index;

  String get label => index == null ? name : '$name[$index]';
}

/// The state the live stream cases read. Floats are stored by the sim as
/// 32-bit values, so a read-back is compared with a small tolerance.
const liveState = <SimValue>[
  // The float and double cases read a writable float that nothing else moves.
  SimValue('sim/cockpit/misc/barometer_setting', 29.92),
  // The int array element case.
  SimValue('sim/cockpit2/engine/actuators/ignition_key', 3, index: 0),
  // The array element and range cases. The array is longer than the fixtures
  // assume and its length differs between aircraft, so only the first four
  // are written and the rest is read back (see [readArray]).
  SimValue('sim/cockpit2/engine/actuators/throttle_ratio', 0.25, index: 0),
  SimValue('sim/cockpit2/engine/actuators/throttle_ratio', 0.5, index: 1),
  SimValue('sim/cockpit2/engine/actuators/throttle_ratio', 0.75, index: 2),
  SimValue('sim/cockpit2/engine/actuators/throttle_ratio', 1, index: 3),
];

/// The result of [applySimState]: one `OK`/`FAIL` line per value, and a way to
/// put the old values back.
class SimSetup {
  SimSetup._(this.lines, this._undo, this._api);

  final List<String> lines;
  final List<(SimValue, num)> _undo;
  final Uri _api;

  bool get ok => !lines.any((l) => l.startsWith('FAIL'));

  /// Writes the old values back, last write first. Returns one line per value.
  Future<List<String>> restore() async {
    final client = HttpClient();
    final ids = <String, int?>{};
    try {
      final out = <String>[];
      for (final (v, old) in _undo.reversed) {
        final line = await _write(
          client,
          _api,
          SimValue(v.name, old, index: v.index),
          ids,
        );
        out.add(line.replaceFirst('OK  ', 'RESTORED'));
      }
      return out;
    } finally {
      client.close(force: true);
    }
  }
}

/// Remembers the old values, writes [values] and reads each back.
Future<SimSetup> applySimState(
  Uri api, {
  List<SimValue> values = liveState,
}) async {
  final client = HttpClient();
  final ids = <String, int?>{};
  final lines = <String>[];
  final undo = <(SimValue, num)>[];
  try {
    for (final v in values) {
      final old = await _read(client, api, v, ids);
      if (old != null) undo.add((v, old));
      lines.add(await _write(client, api, v, ids));
    }
  } finally {
    client.close(force: true);
  }
  return SimSetup._(lines, undo, api);
}

/// Reads a whole array dataref (for example `.../throttle_ratio`) through the
/// web API; null when it is not found or not an array.
Future<List<num>?> readArray(Uri api, String name) async {
  final client = HttpClient();
  try {
    final id = await _idOf(client, api, name);
    if (id == null) return null;
    final res = await _send(client, 'GET', _valueUrl(api, id, null), null);
    final data = (jsonDecode(res.body) as Map<String, Object?>)['data'];
    return data is List ? data.cast<num>() : null;
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Reads a scalar number dataref (for example the latitude) through the web
/// API; null when it is not found or not a number.
Future<num?> readNumber(Uri api, String name) async {
  final client = HttpClient();
  try {
    return await _read(client, api, SimValue(name, 0), {});
  } finally {
    client.close(force: true);
  }
}

Future<num?> _read(
  HttpClient client,
  Uri api,
  SimValue v,
  Map<String, int?> ids,
) async {
  try {
    final id = ids[v.name] ??= await _idOf(client, api, v.name);
    if (id == null) return null;
    final res = await _send(client, 'GET', _valueUrl(api, id, v.index), null);
    return _number((jsonDecode(res.body) as Map<String, Object?>)['data']);
  } on Object {
    return null;
  }
}

num? _number(Object? data) {
  // An indexed read comes back as a one-element list.
  final got = data is List && data.length == 1 ? data.first : data;
  return got is num ? got : null;
}

Future<String> _write(
  HttpClient client,
  Uri api,
  SimValue v,
  Map<String, int?> ids,
) async {
  try {
    final id = ids[v.name] ??= await _idOf(client, api, v.name);
    if (id == null) return 'FAIL ${v.label}: not found in the sim';
    final url = _valueUrl(api, id, v.index);
    final put = await _send(client, 'PATCH', url, {'data': v.value});
    if (put.status != 200) {
      return 'FAIL ${v.label}: write gave http ${put.status} ${put.body}';
    }
    final back = await _send(client, 'GET', url, null);
    final got = _number(
      (jsonDecode(back.body) as Map<String, Object?>)['data'],
    );
    if (got == null || (got - v.value).abs() > 1e-4) {
      return 'FAIL ${v.label}: wrote ${v.value}, read back $got';
    }
    return 'OK   ${v.label} = ${v.value}';
  } on Object catch (e) {
    return 'FAIL ${v.label}: $e';
  }
}

Uri _valueUrl(Uri api, int id, int? index) => api.replace(
  path: '/api/v2/datarefs/$id/value',
  queryParameters: index == null ? null : {'index': '$index'},
);

Future<int?> _idOf(HttpClient client, Uri api, String name) async {
  final url = api.replace(
    path: '/api/v2/datarefs',
    queryParameters: {'filter[name]': name},
  );
  final res = await _send(client, 'GET', url, null);
  final data = (jsonDecode(res.body) as Map<String, Object?>)['data'];
  if (data is List && data.isNotEmpty) {
    return (data.first as Map<String, Object?>)['id'] as int?;
  }
  return null;
}

class _Reply {
  const _Reply(this.status, this.body);

  final int status;
  final String body;
}

Future<_Reply> _send(
  HttpClient client,
  String method,
  Uri url,
  Object? json,
) async {
  final req = await client.openUrl(method, url);
  if (json != null) {
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(json));
  }
  final res = await req.close().timeout(const Duration(seconds: 5));
  return _Reply(res.statusCode, await utf8.decodeStream(res));
}

Future<void> main(List<String> args) async {
  var api = Uri.parse('http://127.0.0.1:8086');
  var keep = false;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--api' && i + 1 < args.length) api = Uri.parse(args[++i]);
    if (args[i] == '--keep') keep = true;
  }
  final setup = await applySimState(api);
  setup.lines.forEach(stdout.writeln);
  if (!keep) (await setup.restore()).forEach(stdout.writeln);
  exit(setup.ok ? 0 : 1);
}
