import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'fake_plugin_stream_engine.dart';

/// Where the golden files live, relative to the project root.
const protocolFixtureDir = 'testing/fixtures/protocol';

/// A Dart implementation of the companion plugin protocol
/// (`plugin/PROTOCOL.md`) on loopback and an ephemeral port.
///
/// The fake is the specification: the plugin core and the real plugin must
/// answer the shared cases (`tools/protocol_contract.dart`) the same way.
/// State is set by the test; the defaults are the golden files.
class FakeCompanionPluginServer {
  FakeCompanionPluginServer._(this._server, this.stream, this._tickInterval) {
    final golden = jsonDecode(
      File('$protocolFixtureDir/aircraft_with_checklist.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    _generation = golden['generation']! as int;
    stream.setSignal(generationSignal, _generation);
    icao = golden['icao']! as String;
    description = golden['description']! as String;
    aircraftPath = golden['aircraftPath']! as String;
    checklistPath = golden['checklistPath'] as String?;
    mtime = golden['checklistModified']! as int;
    checklistBytes = File('$protocolFixtureDir/checklist_sample.txt')
        .readAsBytesSync();
    _listen();
  }

  /// Starts the server on loopback. [port] 0 picks a free port. [now] is the
  /// clock of the stream engine and [tickInterval] how often it ticks (real
  /// time) while the server runs.
  static Future<FakeCompanionPluginServer> start({
    int port = 0,
    Now? now,
    Duration tickInterval = const Duration(milliseconds: 10),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final values = jsonDecode(
      File('$protocolFixtureDir/stream_values.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final engine = FakePluginStreamEngine(
      now: now,
      signals: (values['signals']! as Map<String, Object?>).cast<String, num>(),
      arrays: {
        for (final e
            in (values['arrays'] as Map<String, Object?>? ?? {}).entries)
          e.key: (e.value! as List<Object?>).cast<num>(),
      },
      unsupported: (values['unsupported']! as List<Object?>)
          .cast<String>()
          .toSet(),
    );
    return FakeCompanionPluginServer._(server, engine, tickInterval);
  }

  /// How many requests each path has received (including failed ones).
  final Map<String, int> requests = {};

  /// The stream engine: set signals, faults and the ack delay here.
  final FakePluginStreamEngine stream;
  final Duration _tickInterval;
  Timer? _ticker;
  final List<WebSocket> _sockets = [];

  /// At most this many stream clients at once; the next gets 503.
  static const maxStreamClients = 4;

  /// The largest checklist the protocol serves.
  static const maxChecklistBytes = 2 * 1024 * 1024;

  HttpServer _server;

  Duration? _delayNext;
  bool _dropNext = false;
  bool _malformedNext = false;
  bool _changeAfterNextAircraft = false;

  // State set by the test.
  int protocolVersion = 1;
  String simKind = 'xplane';
  String simVersion = '12.1.4';

  /// The `os` the hello reports; null leaves the field out.
  String? os = 'windows';
  String pluginVersion = '0.1.0';

  /// The `runId` the hello reports; null leaves the field out. Tests change it
  /// to act out an X-Plane restart.
  String? runId = 'a1b2c3d4e5f60718';
  late int _generation;

  /// Incremented on every aircraft load. Setting it also updates the
  /// `flightsim_aide/aircraft_generation` stream signal.
  int get generation => _generation;
  set generation(int v) {
    _generation = v;
    stream.setSignal(generationSignal, v);
  }

  late String icao;
  late String description;
  late String aircraftPath;
  String? checklistPath;
  Uint8List? checklistBytes;
  late int mtime;

  int get port => _server.port;

  Uri get baseUri => Uri.parse('http://127.0.0.1:$port');

  /// The ETag of the current checklist, or null without one.
  String? get etag {
    final bytes = checklistBytes;
    return bytes == null ? null : '"$mtime-${bytes.length}"';
  }

  /// Puts the server in one of the shared scenarios of `PROTOCOL.md`
  /// section 8: `default`, `no_checklist` or `oversize`.
  void useScenario(String name) {
    switch (name) {
      case 'default':
        checklistBytes = File('$protocolFixtureDir/checklist_sample.txt')
            .readAsBytesSync();
      case 'no_checklist':
        checklistBytes = null;
      case 'oversize':
        checklistBytes = Uint8List(3 * 1024 * 1024);
      default:
        throw ArgumentError('unknown scenario $name');
    }
  }

  /// The aircraft the plugin reports after [loadAircraft]: the generation
  /// goes up by one (wrapping at 2^31) and the checklist, if any, is new.
  void loadAircraft({
    required String icao,
    required String description,
    required String aircraftPath,
    String? checklistPath,
    List<int>? checklistBytes,
  }) {
    generation = (generation + 1) & 0x7fffffff;
    this.icao = icao;
    this.description = description;
    this.aircraftPath = aircraftPath;
    if (checklistBytes == null) {
      this.checklistBytes = null;
      this.checklistPath = null;
    } else {
      this.checklistBytes = Uint8List.fromList(checklistBytes);
      this.checklistPath =
          checklistPath ??
          '${aircraftPath.substring(0, aircraftPath.lastIndexOf('/'))}/clist.txt';
      mtime += 60000;
    }
  }

  /// A file edit while the sim runs: new mtime and size, the **same**
  /// generation (the generation counts aircraft loads, not file changes).
  void editChecklist(String text) {
    checklistBytes = Uint8List.fromList(utf8.encode(text));
    mtime += 1000;
  }

  /// A restored backup: the mtime goes **down** (the app must refetch on
  /// any difference, not only a newer time).
  void restoreOlder() {
    mtime -= 120000;
  }

  /// The next HTTP request waits [d] before it is answered.
  void delayNext(Duration d) => _delayNext = d;

  /// The next HTTP request has its connection closed without a response.
  void dropNext() => _dropNext = true;

  /// The next `/v1/aircraft` answer is truncated JSON.
  void malformedAircraft() => _malformedNext = true;

  /// After the next `/v1/aircraft` answer is sent, another aircraft is
  /// loaded, so the checklist request that follows sees a new generation.
  void changeAircraftBetweenRequests() => _changeAfterNextAircraft = true;

  /// Stops and starts again on a new port. State is kept.
  Future<void> restart() async {
    await dropStreamConnections();
    await _server.close(force: true);
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _listen();
  }

  /// From now on the stream sends no frame at all (heartbeat, values, pong),
  /// so a client can exercise its stale rule.
  void silence() => stream.silenced = true;

  /// Subscribes are acknowledged [d] later than the next tick.
  void delayAck(Duration d) => stream.ackDelay = d;

  /// Closes every open stream connection from the server side.
  Future<void> dropStreamConnections() async {
    for (final ws in List.of(_sockets)) {
      await ws.close();
    }
    _sockets.clear();
  }

  Future<void> close() async {
    _ticker?.cancel();
    await dropStreamConnections();
    await _server.close(force: true);
  }

  void _listen() {
    _ticker ??= Timer.periodic(_tickInterval, (_) => stream.tick());
    _server.listen(_handle);
  }

  Future<void> _handle(HttpRequest request) async {
    requests.update(request.uri.path, (n) => n + 1, ifAbsent: () => 1);
    final delay = _delayNext;
    if (delay != null) {
      _delayNext = null;
      await Future<void>.delayed(delay);
    }
    if (_dropNext) {
      _dropNext = false;
      final socket = await request.response.detachSocket();
      socket.destroy();
      return;
    }
    final res = request.response;
    final path = request.uri.hasAuthority ? null : request.uri.path;
    final head = request.method == 'HEAD';
    const served = {'/v1/hello', '/v1/aircraft', '/v1/checklist', '/v1/stream'};
    if (path == null || !served.contains(path)) {
      await _error(res, 404, 'not_found', 'No such path.', head: head);
      return;
    }
    if (request.method != 'GET' && !head) {
      res.headers.set('allow', 'GET, HEAD');
      await _error(
        res,
        405,
        'method_not_allowed',
        'Only GET and HEAD are supported.',
        head: false,
      );
      return;
    }
    switch (path) {
      case '/v1/hello':
        await _hello(request, head);
      case '/v1/aircraft':
        await _aircraft(request, head);
      case '/v1/checklist':
        await _checklist(request, head);
      default:
        await _streamRequest(request, head);
    }
  }

  Future<void> _streamRequest(HttpRequest request, bool head) async {
    final res = request.response;
    if (head || !WebSocketTransformer.isUpgradeRequest(request)) {
      await _error(
        res,
        400,
        'upgrade_required',
        'This path needs a WebSocket upgrade.',
        head: head,
      );
      return;
    }
    if (_sockets.length >= maxStreamClients) {
      await _error(res, 503, 'limit', 'At most 4 stream clients.', head: false);
      return;
    }
    final ws = await WebSocketTransformer.upgrade(request);
    _sockets.add(ws);
    final client = stream.addClient((frame) {
      if (ws.readyState != WebSocket.open) return;
      try {
        ws.add(frame);
      } on StateError {
        // The socket closed between the check and the write (a client that
        // dropped or a restart); the listener's onDone removes the client.
      }
    });
    void gone() {
      stream.removeClient(client);
      _sockets.remove(ws);
    }

    ws.listen(
      (message) {
        if (message is String) {
          stream.receive(client, message);
        }
      },
      onDone: gone,
      onError: (Object _) => gone(),
    );
  }

  Future<void> _error(
    HttpResponse res,
    int status,
    String code,
    String message, {
    required bool head,
  }) => _json(res, status, {'error': code, 'message': message}, head: head);

  Future<void> _hello(HttpRequest request, bool head) async {
    await _json(request.response, 200, {
      'protocolVersion': protocolVersion,
      'sim': {'kind': simKind, 'version': simVersion},
      'os': ?os,
      'pluginVersion': pluginVersion,
      'runId': ?runId,
      'port': port,
      'streamPath': '/v1/stream',
    }, head: head);
  }

  Map<String, Object?> _aircraftMap() {
    final bytes = checklistBytes;
    return {
      'protocolVersion': protocolVersion,
      'generation': generation,
      'icao': icao,
      'description': description,
      'aircraftPath': aircraftPath,
      if (bytes != null) ...{
        'checklistPath': checklistPath,
        'checklistModified': mtime,
        'checklistSize': bytes.length,
      },
    };
  }

  Future<void> _aircraft(HttpRequest request, bool head) async {
    if (_malformedNext) {
      _malformedNext = false;
      final res = request.response;
      final bytes = utf8.encode('{"protocolVersion":1,"generation":');
      res.statusCode = 200;
      res.headers.set('content-type', 'application/json; charset=utf-8');
      res.contentLength = bytes.length;
      if (!head) res.add(bytes);
      await res.close();
      return;
    }
    await _json(request.response, 200, _aircraftMap(), head: head);
    if (_changeAfterNextAircraft) {
      _changeAfterNextAircraft = false;
      loadAircraft(
        icao: 'B738',
        description: 'Boeing 737-800',
        aircraftPath: 'Aircraft/Laminar Research/Boeing B737-800/b738.acf',
        checklistBytes: utf8.encode('sw_checklist:Other\nsw_item:A|B\n'),
      );
    }
  }

  Future<void> _checklist(HttpRequest request, bool head) async {
    final res = request.response;
    final bytes = checklistBytes;
    if (bytes == null) {
      await _error(
        res,
        404,
        'no_checklist',
        'The loaded aircraft has no checklist file.',
        head: head,
      );
      return;
    }
    if (bytes.length > maxChecklistBytes) {
      await _error(
        res,
        413,
        'too_large',
        'The checklist is larger than 2 MB.',
        head: head,
      );
      return;
    }
    final tag = etag!;
    if (_matches(request.headers.value('if-none-match'), tag)) {
      res.statusCode = 304;
      res.headers.set('etag', tag);
      await res.close();
      return;
    }
    res.statusCode = 200;
    res.headers
      ..set('content-type', 'text/plain')
      ..set('etag', tag)
      ..set(
        'last-modified',
        HttpDate.format(
          DateTime.fromMillisecondsSinceEpoch(mtime, isUtc: true),
        ),
      )
      ..set('x-aircraft-generation', '$generation');
    res.contentLength = bytes.length;
    if (!head) res.add(bytes);
    await res.close();
  }

  Future<void> _json(
    HttpResponse res,
    int status,
    Map<String, Object?> body, {
    required bool head,
  }) async {
    final bytes = utf8.encode(jsonEncode(body));
    res.statusCode = status;
    res.headers
      ..set('content-type', 'application/json; charset=utf-8')
      ..set('cache-control', 'no-store');
    res.contentLength = bytes.length;
    if (!head) res.add(bytes);
    await res.close();
  }

  /// `If-None-Match` matching: `*`, or a comma-separated list of (possibly
  /// weak) quoted values compared by exact string equality.
  static bool _matches(String? header, String etag) {
    if (header == null) return false;
    final h = header.trim();
    if (h == '*') return true;
    for (final part in h.split(',')) {
      var p = part.trim();
      if (p.startsWith('W/')) p = p.substring(2);
      if (p == etag) return true;
    }
    return false;
  }
}
