// Runs the shared protocol cases (testing/fixtures/protocol) against a server.
//
//   dart run tools/protocol_contract.dart <baseUrl> [--scenario name]
//       [--no-plugin-only] [--http-only | --stream-only] [--fixtures dir]
//       [--live [--sim-api url] [--no-setup]]
//
// --live is for a real sim: the aircraft path, generation and checklist
// modification time are the sim's own, so they are read from the server and
// not compared with the fixtures; icao, description and the checklist text
// still are. Cases tagged needsFixtureAircraft in cases.json need the fixture
// aircraft (C172 With Checklist, see BUILDING.md); with any other aircraft
// they print SKIP and are counted apart, unless --require-fixture-aircraft is
// given, which runs them and so fails them. Before the stream
// cases it sets the datarefs they read through X-Plane's web API
// (tools/live_setup.dart; --sim-api defaults to http://127.0.0.1:8086,
// --no-setup skips it).
//
// The same cases run against the Dart fake and the real plugin, so the two
// cannot drift apart. Prints `PASS name` or `FAIL name: reason` per case and
// exits non-zero when any case fails.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'live_setup.dart';

/// The outcome of one case.
class CaseResult {
  const CaseResult(this.name, this.reason, {this.skipped = false});

  final String name;

  /// Null when the case passed; the failure, or why it was skipped.
  final String? reason;

  /// True when the case was not run (see `needsFixtureAircraft`). A skipped
  /// case is neither passed nor failed.
  final bool skipped;

  bool get passed => reason == null;

  bool get failed => reason != null && !skipped;
}

const _defaultFixtures = 'testing/fixtures/protocol';

/// Runs the cases and returns one result per case, in file order.
Future<List<CaseResult>> runContract(
  Uri base, {
  String scenario = 'default',
  bool includePluginOnly = true,
  bool http = true,
  bool stream = true,
  String fixtureDir = _defaultFixtures,
  bool live = false,
  Uri? simApi,
  bool requireFixtureAircraft = false,
}) async {
  final results = <CaseResult>[];
  _tolerance = live ? 1e-6 : 0;
  final subs = live ? await _liveSubstitutions(base, simApi) : const <_Sub>[];
  // Cases tagged needsFixtureAircraft compare the aircraft and the checklist
  // text with the fixtures, so against a real sim they only make sense when
  // the loaded aircraft is the fixture one; otherwise they are skipped.
  String? skipReason;
  if (live && http && !requireFixtureAircraft) {
    skipReason = await _notFixtureAircraft(base, fixtureDir);
  }
  if (http) {
    final cases = _readList('$fixtureDir/cases.json', subs);
    final client = HttpClient();
    try {
      for (final c in cases) {
        if ((c['scenario'] ?? 'default') != scenario) continue;
        if (c['pluginOnly'] == true && !includePluginOnly) continue;
        final name = c['name']! as String;
        if (skipReason != null && c['needsFixtureAircraft'] == true) {
          results.add(CaseResult(name, skipReason, skipped: true));
          continue;
        }
        results.add(
          CaseResult(
            name,
            await _guard(
              () => _httpCase(client, base, c, fixtureDir, live: live),
            ),
          ),
        );
      }
    } finally {
      client.close(force: true);
    }
  }
  if (stream) {
    final cases = _readList('$fixtureDir/stream_cases.json', subs);
    for (final c in cases) {
      final name = c['name']! as String;
      results.add(
        CaseResult('stream: $name', await _guard(() => _streamCase(base, c))),
      );
    }
  }
  return results;
}

/// The command-line entry point; returns the exit code.
Future<int> contractMain(
  List<String> args, {
  void Function(String)? out,
}) async {
  final void Function(String) write = out ?? (s) => stdout.writeln(s);
  String? url;
  var scenario = 'default';
  var pluginOnly = true;
  var http = true;
  var stream = true;
  var fixtures = _defaultFixtures;
  var live = false;
  var setup = true;
  var requireFixture = false;
  var simApi = 'http://127.0.0.1:8086';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--scenario':
        if (++i >= args.length) return _usage(write);
        scenario = args[i];
      case '--fixtures':
        if (++i >= args.length) return _usage(write);
        fixtures = args[i];
      case '--live':
        live = true;
      case '--sim-api':
        if (++i >= args.length) return _usage(write);
        simApi = args[i];
      case '--no-setup':
        setup = false;
      case '--require-fixture-aircraft':
        requireFixture = true;
      case '--no-plugin-only':
        pluginOnly = false;
      case '--http-only':
        stream = false;
      case '--stream-only':
        http = false;
      default:
        if (args[i].startsWith('--') || url != null) return _usage(write);
        url = args[i];
    }
  }
  if (url == null) return _usage(write);
  SimSetup? sim;
  if (live && stream && setup) {
    sim = await applySimState(Uri.parse(simApi));
    sim.lines.forEach(write);
    if (!sim.ok) {
      (await sim.restore()).forEach(write);
      write('could not set the sim state; fix it or pass --no-setup');
      return 1;
    }
  }
  final List<CaseResult> results;
  try {
    results = await runContract(
      Uri.parse(url),
      scenario: scenario,
      includePluginOnly: pluginOnly,
      http: http,
      stream: stream,
      fixtureDir: fixtures,
      live: live,
      simApi: sim == null ? null : Uri.parse(simApi),
      requireFixtureAircraft: requireFixture,
    );
  } finally {
    if (sim != null) (await sim.restore()).forEach(write);
  }
  for (final r in results) {
    write(
      r.skipped
          ? 'SKIP ${r.name}: ${r.reason}'
          : r.passed
          ? 'PASS ${r.name}'
          : 'FAIL ${r.name}: ${r.reason}',
    );
  }
  final failed = results.where((r) => r.failed).length;
  final skipped = results.where((r) => r.skipped).length;
  final passed = results.length - failed - skipped;
  write(
    '$passed passed, $failed failed'
    '${skipped > 0 ? ', $skipped skipped' : ''}',
  );
  if (skipped > 0) {
    write(
      '$skipped cases skipped: load the fixture aircraft (C172 With '
      'Checklist, see BUILDING.md) for a full run, or pass '
      '--require-fixture-aircraft to fail instead of skip.',
    );
  }
  return failed == 0 ? 0 : 1;
}

Future<void> main(List<String> args) async {
  exitCode = await contractMain(args);
}

int _usage(void Function(String) write) {
  write(
    'usage: protocol_contract.dart <baseUrl> [--scenario name] '
    '[--no-plugin-only] [--http-only | --stream-only] [--fixtures dir] '
    '[--live [--sim-api url] [--no-setup] [--require-fixture-aircraft]]',
  );
  return 2;
}

/// Null when the aircraft the server reports is the fixture aircraft (the
/// same icao and description, and a checklist byte for byte the fixture
/// text); otherwise why it is not, for the `SKIP` line.
Future<String?> _notFixtureAircraft(Uri base, String fixtureDir) async {
  final client = HttpClient();
  try {
    final want = jsonDecode(
      File('$fixtureDir/aircraft_with_checklist.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final aircraft = await _getBody(client, base.replace(path: '/v1/aircraft'));
    final got = jsonDecode(utf8.decode(aircraft)) as Map<String, Object?>;
    final loaded = '${got['icao']} ${got['description']}';
    if (got['icao'] != want['icao'] ||
        got['description'] != want['description']) {
      return 'needs the fixture aircraft (C172 With Checklist); loaded: '
          '$loaded';
    }
    final list = await _getBody(client, base.replace(path: '/v1/checklist'));
    final fixture = File('$fixtureDir/checklist_sample.txt').readAsBytesSync();
    if (!_sameBytes(list, fixture)) {
      return 'needs the fixture checklist (checklist_sample.txt); loaded: '
          '$loaded with a different checklist';
    }
    return null;
  } on Object catch (e) {
    return 'could not read the loaded aircraft ($e)';
  } finally {
    client.close(force: true);
  }
}

Future<List<int>> _getBody(HttpClient client, Uri url) async {
  final res = await (await client.getUrl(url)).close();
  final bytes = <int>[];
  await for (final chunk in res) {
    bytes.addAll(chunk);
  }
  if (res.statusCode != 200) {
    throw StateError('${url.path} gave ${res.statusCode}');
  }
  return bytes;
}

List<Map<String, Object?>> _readList(
  String path, [
  List<_Sub> subs = const [],
]) {
  var text = File(path).readAsStringSync();
  for (final s in subs) {
    text = text.replaceAllMapped(s.pattern, s.replace);
  }
  return (jsonDecode(text) as List<Object?>).cast<Map<String, Object?>>();
}

/// A rewrite of the fixture text for `--live`.
class _Sub {
  const _Sub(this.pattern, this.replace);
  final RegExp pattern;
  final String Function(Match) replace;
}

const _throttleName = 'sim/cockpit2/engine/actuators/throttle_ratio';
const _latitudeName = 'sim/flightmodel/position/latitude';

/// The expectation of the range case with stream id [id]: elements [from] to
/// [to] (inclusive) of [array], cut short where the array ends.
_Sub _rangeSub(String id, List<num> array, int from, int to) {
  final start = from < array.length ? from : array.length;
  final end = to + 1 < array.length ? to + 1 : array.length;
  final slice = jsonEncode(array.sublist(start, end));
  return _Sub(RegExp('("$id"\\s*:\\s*)\\[[^\\]]*\\]'), (m) => '${m[1]}$slice');
}

/// Reads the aircraft from the server and rewrites the fixture values that a
/// real sim decides itself: generation, checklist modification time and size.
Future<List<_Sub>> _liveSubstitutions(Uri base, Uri? simApi) async {
  final throttle = simApi == null
      ? null
      : await readArray(simApi, _throttleName);
  // The double case reads the latitude, which depends on where the aircraft is
  // parked, so its expectation is read from the same dataref via the web API.
  final latitude = simApi == null
      ? null
      : await readNumber(simApi, _latitudeName);
  final client = HttpClient();
  try {
    final req = await client.getUrl(base.replace(path: '/v1/aircraft'));
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    final a = jsonDecode(body) as Map<String, Object?>;
    final gen = a['generation'];
    final mod = a['checklistModified'];
    final size = a['checklistSize'];
    return [
      if (gen is int) ...[
        _Sub(
          RegExp(r'("X-Aircraft-Generation"\s*:\s*)"12"'),
          (m) => '${m[1]}"$gen"',
        ),
        _Sub(RegExp(r'("1"\s*:\s*)12(\s*\})'), (m) => '${m[1]}$gen${m[2]}'),
      ],
      // Stream kinds: a real sim has no 77.5 airspeed, so the float case reads
      // the barometer setting, which tools/live_setup.dart sets to 29.92.
      _Sub(
        RegExp(r'sim/flightmodel/position/indicated_airspeed'),
        (_) => 'sim/cockpit/misc/barometer_setting',
      ),
      _Sub(RegExp(r'("1"\s*:\s*)77\.5'), (m) => '${m[1]}29.92'),
      // The range cases: how long the throttle array is, and what an aircraft
      // keeps past the first four elements, differ between aircraft, so what
      // the plugin must answer is read from the same array through the web
      // API (an independent reader).
      if (latitude != null)
        _Sub(RegExp(r'44.491250047029595'), (_) => '$latitude'),
      if (throttle != null) ...[
        _rangeSub('20', throttle, 0, 2),
        _rangeSub('21', throttle, 2, 9),
        _rangeSub('22', throttle, 10, 12),
      ],
      if (mod is int) _Sub(RegExp('1761206400123'), (_) => '$mod'),
      if (size is int) ...[
        _Sub(RegExp(r'-267"'), (_) => '-$size"'),
        _Sub(RegExp(r'-268"'), (_) => '-${size + 1}"'),
      ],
    ];
  } finally {
    client.close(force: true);
  }
}

/// Turns a thrown failure into a reason; null when [body] returns normally.
Future<String?> _guard(Future<void> Function() body) async {
  try {
    await body();
    return null;
  } on _Mismatch catch (e) {
    return e.message;
  } on Object catch (e) {
    return 'error: $e';
  }
}

/// Aircraft fields that a real sim decides itself.
const _simOwned = [
  'generation',
  'aircraftPath',
  'checklistPath',
  'checklistModified',
];

class _Mismatch implements Exception {
  _Mismatch(this.message);
  final String message;
}

Never _fail(String message) => throw _Mismatch(message);

// ---------------------------------------------------------------- HTTP

Future<void> _httpCase(
  HttpClient client,
  Uri base,
  Map<String, Object?> c,
  String fixtureDir, {
  bool live = false,
}) async {
  final method = c['method']! as String;
  final path = c['path']! as String;
  final expect = c['expect']! as Map<String, Object?>;
  final uri = base.replace(
    path: path.split('?').first,
    query: path.contains('?') ? path.substring(path.indexOf('?') + 1) : null,
  );
  final req = await client.openUrl(method, uri);
  ((c['headers'] as Map<String, Object?>?) ?? {}).forEach(
    (k, v) => req.headers.set(k, v! as String),
  );
  final res = await req.close();
  final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));

  final status = expect['status'];
  if (status != null && res.statusCode != status) {
    _fail('status ${res.statusCode}, expected $status');
  }
  String? header(String name) => res.headers.value(name);
  ((expect['headers'] as Map<String, Object?>?) ?? {}).forEach((k, v) {
    final got = header(k);
    if (got != v) {
      _fail(
        'header $k is ${got == null ? 'missing' : '"$got"'}, expected "$v"',
      );
    }
  });
  for (final k in (expect['headersPresent'] as List<Object?>?) ?? const []) {
    if (header(k! as String) == null) _fail('header $k is missing');
  }
  ((expect['headersLengthOfFile'] as Map<String, Object?>?) ?? {}).forEach((
    k,
    f,
  ) {
    // The aircraft body carries the sim's own path, so its size differs.
    if (live && (f! as String).endsWith('.json')) return;
    final len = File('$fixtureDir/$f').lengthSync();
    final got = header(k);
    // The aircraft file may be pretty-printed on disk, so compare the
    // compact JSON length when the file is JSON.
    final want = (f! as String).endsWith('.json')
        ? utf8
              .encode(
                jsonEncode(
                  jsonDecode(File('$fixtureDir/$f').readAsStringSync()),
                ),
              )
              .length
        : len;
    if (got != '$want') {
      _fail('header $k is ${got ?? 'missing'}, expected $want');
    }
  });
  if (expect['bodyEmpty'] == true && body.isNotEmpty) {
    _fail('body has ${body.length} bytes, expected none');
  }
  final ignore = ((expect['jsonIgnore'] as List<Object?>?) ?? const [])
      .cast<String>();
  final bodyFile = expect['bodyFile'] as String?;
  if (bodyFile != null) {
    final file = File('$fixtureDir/$bodyFile');
    if (bodyFile.endsWith('.json')) {
      final got = _json(body);
      final want = jsonDecode(file.readAsStringSync());
      if (got is Map<String, Object?> && want is Map<String, Object?>) {
        for (final k in ignore) {
          if (!got.containsKey(k)) _fail('field $k is missing');
          got.remove(k);
          want.remove(k);
        }
        if (live) {
          for (final k in _simOwned) {
            got.remove(k);
            want.remove(k);
          }
        }
      }
      if (jsonEncode(got) != jsonEncode(want)) {
        _fail('body ${jsonEncode(got)} differs from $bodyFile');
      }
    } else {
      final want = file.readAsBytesSync();
      if (!_sameBytes(body, want)) {
        _fail(
          'body (${body.length} bytes) differs from $bodyFile (${want.length} bytes)',
        );
      }
    }
  }
  final subset = expect['jsonSubset'];
  if (subset != null) {
    final got = _json(body);
    if (!_isSubset(subset, got)) {
      _fail('body ${jsonEncode(got)} lacks ${jsonEncode(subset)}');
    }
  }
  if (expect['portMatchesUrl'] == true) {
    final got = _json(body);
    if (got is! Map || got['port'] != base.port) {
      _fail('port is ${got is Map ? got['port'] : got}, expected ${base.port}');
    }
  }
}

Object? _json(List<int> body) {
  try {
    return jsonDecode(utf8.decode(body));
  } on FormatException {
    return _fail('body is not JSON');
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// True when every key in [want] is in [got] with a matching value, deeply.
bool _isSubset(Object? want, Object? got) {
  if (want is Map) {
    return got is Map &&
        want.entries.every(
          (e) => got.containsKey(e.key) && _isSubset(e.value, got[e.key]),
        );
  }
  if (want is List) {
    return got is List &&
        want.length == got.length &&
        Iterable<int>.generate(want.length)
            .every((i) => _isSubset(want[i], got[i]));
  }
  if (want is num && got is num) return (want - got).abs() <= _tolerance;
  return want == got;
}

/// How far two numbers may differ and still match. Zero, except with `--live`:
/// a parked aircraft's latitude still moves in the eighth decimal, and a
/// float32 value arrives as its nearest double. 1e-6 is below a float32's
/// error on a latitude, so the double case still tells the two kinds apart.
double _tolerance = 0;

// -------------------------------------------------------------- stream

class _Conn {
  _Conn(this.socket) {
    socket.listen((m) {
      try {
        final f = jsonDecode(m as String);
        if (f is Map<String, Object?>) frames.add(f);
      } on FormatException {
        // Not a JSON frame; no case expects one.
      }
    }, onError: (Object _) {});
  }

  final WebSocket socket;
  final List<Map<String, Object?>> frames = [];

  /// Removes and returns the first frame matching [match], waiting up to
  /// [within]; null when none arrives.
  Future<Map<String, Object?>?> take(
    Map<String, Object?> match,
    Duration within,
  ) async {
    final end = DateTime.now().add(within);
    while (true) {
      final i = frames.indexWhere((f) => _isSubset(match, f));
      if (i >= 0) return frames.removeAt(i);
      if (!DateTime.now().isBefore(end)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}

Uri _wsUri(Uri base) => base.replace(scheme: 'ws', path: '/v1/stream');

Future<void> _streamCase(Uri base, Map<String, Object?> c) async {
  final main = _Conn(await _connectWithRetry(base));
  final extras = <_Conn>[];
  try {
    for (final step
        in (c['steps']! as List<Object?>).cast<Map<String, Object?>>()) {
      await _step(base, main, extras, step);
    }
  } finally {
    for (final e in [main, ...extras]) {
      await e.socket.close().timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
    }
  }
}

Future<void> _step(
  Uri base,
  _Conn conn,
  List<_Conn> extras,
  Map<String, Object?> step,
) async {
  Duration ms(Object? v) => Duration(milliseconds: v! as int);
  if (step.containsKey('send')) {
    conn.socket.add(jsonEncode(step['send']));
  } else if (step.containsKey('sendRaw')) {
    conn.socket.add(step['sendRaw']! as String);
  } else if (step.containsKey('expect')) {
    final want = step['expect']! as Map<String, Object?>;
    final got = await conn.take(want, ms(step['withinMs']));
    if (got == null) {
      _fail(
        'no frame matching ${jsonEncode(want)} within ${step['withinMs']} ms; saw ${jsonEncode(conn.frames)}',
      );
    }
  } else if (step.containsKey('expectNone')) {
    final unwanted = step['expectNone']! as Map<String, Object?>;
    final got = await conn.take(unwanted, ms(step['forMs']));
    if (got != null) _fail('unexpected frame ${jsonEncode(got)}');
  } else if (step.containsKey('collect')) {
    final spec = step['collect']! as Map<String, Object?>;
    final match = spec['match']! as Map<String, Object?>;
    final end = DateTime.now().add(ms(spec['forMs']));
    var n = 0;
    while (true) {
      final left = end.difference(DateTime.now());
      if (left <= Duration.zero) break;
      if (await conn.take(match, left) != null) n++;
    }
    final min = spec['min'] as int?;
    final max = spec['max'] as int?;
    if ((min != null && n < min) || (max != null && n > max)) {
      _fail(
        'collected $n frames matching ${jsonEncode(match)}, expected $min..$max',
      );
    }
  } else if (step.containsKey('wait')) {
    await Future<void>.delayed(ms(step['wait']));
    // Frames from before the pause are not interesting any more.
    conn.frames.clear();
  } else if (step.containsKey('subscribeMany')) {
    final s = step['subscribeMany']! as Map<String, Object?>;
    final first = s['firstId']! as int;
    for (var i = 0; i < (s['count']! as int); i++) {
      conn.socket.add(
        jsonEncode({
          'op': 'subscribe',
          'id': first + i,
          'name': s['name'],
          'hz': s['hz'],
        }),
      );
    }
  } else if (step.containsKey('openExtraClients')) {
    for (var i = 0; i < (step['openExtraClients']! as int); i++) {
      extras.add(_Conn(await _connectWithRetry(base)));
    }
    // A round trip proves the server has registered every client.
    for (final e in extras) {
      e.socket.add(jsonEncode({'op': 'ping'}));
      if (await e.take({'op': 'pong'}, const Duration(seconds: 2)) == null) {
        _fail('extra client got no pong');
      }
    }
  } else if (step.containsKey('expectUpgradeStatus')) {
    final client = HttpClient();
    try {
      final req = await client.getUrl(base.replace(path: '/v1/stream'));
      req.headers
        ..set('connection', 'Upgrade')
        ..set('upgrade', 'websocket')
        ..set('sec-websocket-version', '13')
        ..set('sec-websocket-key', base64.encode(List.filled(16, 7)));
      final res = await req.close();
      await res.drain<void>();
      if (res.statusCode != step['expectUpgradeStatus']) {
        _fail(
          'upgrade status ${res.statusCode}, expected ${step['expectUpgradeStatus']}',
        );
      }
    } finally {
      client.close(force: true);
    }
  } else {
    _fail('unknown step ${jsonEncode(step)}');
  }
}

/// Opens a stream socket, retrying while the server answers 503.
///
/// The previous case's connection may still hold one of the four slots for a
/// moment after it closed, so an early 503 is not yet a real refusal. After two
/// seconds the error is passed on.
Future<WebSocket> _connectWithRetry(Uri base) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (true) {
    try {
      return await WebSocket.connect(_wsUri(base).toString());
    } on WebSocketException {
      if (DateTime.now().isAfter(deadline)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
