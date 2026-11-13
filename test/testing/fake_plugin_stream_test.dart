import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../testing/fakes/plugin/fake_companion_plugin_server.dart';

const _onGround = 'sim/flightmodel/failures/onground_any';

/// A WebSocket client that records every JSON frame.
class _Client {
  _Client(this.socket) {
    socket.listen((m) {
      final f = jsonDecode(m as String) as Map<String, Object?>;
      frames.add(f);
      _controller.add(f);
    }, onDone: _closed.complete);
  }

  final _closed = Completer<void>();

  /// Completes when the connection has ended, from either side.
  Future<void> get closed => _closed.future;

  final WebSocket socket;
  final List<Map<String, Object?>> frames = [];
  final _controller = StreamController<Map<String, Object?>>.broadcast();

  void send(Object frame) =>
      socket.add(frame is String ? frame : jsonEncode(frame));

  /// The next frame (after now) that contains all of [match].
  Future<Map<String, Object?>> next(
    Map<String, Object?> match, {
    Duration within = const Duration(seconds: 3),
  }) => _controller.stream
      .firstWhere((f) => match.entries.every((e) => f[e.key] == e.value))
      .timeout(within);

  Future<void> close() => socket.close();
}

void main() {
  late FakeCompanionPluginServer server;
  final clients = <_Client>[];

  setUp(() async {
    server = await FakeCompanionPluginServer.start(
      tickInterval: const Duration(milliseconds: 10),
    );
  });

  tearDown(() async {
    for (final c in clients) {
      await c.close();
    }
    clients.clear();
    await server.close();
  });

  Future<_Client> connect() async {
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}/v1/stream',
    );
    final c = _Client(ws);
    clients.add(c);
    // A round trip proves the server has registered this client.
    final pong = c.next({'op': 'pong'});
    c.send({'op': 'ping'});
    await pong;
    return c;
  }

  void sub(_Client c, int id, String name, int hz) =>
      c.send({'op': 'subscribe', 'id': id, 'name': name, 'hz': hz});

  group('stream', () {
    test('subscribe is acknowledged', () async {
      final c = await connect();
      final ack = c.next({'op': 'subscribed', 'id': 1});
      sub(c, 1, _onGround, 2);
      expect(await ack, {'op': 'subscribed', 'id': 1});
    });

    test('values arrive at the requested rate', () async {
      final c = await connect();
      sub(c, 1, _onGround, 20);
      await c.next({'op': 'subscribed'});
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      final n = c.frames.where((f) => f['op'] == 'values').length;
      expect(n, inInclusiveRange(15, 22));
      expect(c.frames.firstWhere((f) => f['op'] == 'values')['v'], {'1': 1});
    });

    test('unsubscribe stops values', () async {
      final c = await connect();
      sub(c, 1, _onGround, 20);
      await c.next({'op': 'values'});
      c.send({'op': 'unsubscribe', 'id': 1});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      c.frames.clear();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(c.frames.where((f) => f['op'] == 'values'), isEmpty);
    });

    test('ping gets pong', () async {
      final c = await connect();
      final pong = c.next({'op': 'pong'});
      c.send({'op': 'ping'});
      expect(await pong, {'op': 'pong'});
    });

    test('heartbeat when idle', () async {
      final c = await connect();
      expect(await c.next({'op': 'hb'}), {'op': 'hb'});
    });

    test(
      'generation is delivered at subscribe and at every aircraft load',
      () async {
        final c = await connect();
        sub(c, 1, 'flightsim_aide/aircraft_generation', 1);
        expect((await c.next({'op': 'values'}))['v'], {'1': 12});
        final changed = c.next({'op': 'values'});
        server.loadAircraft(
          icao: 'B738',
          description: 'Boeing 737-800',
          aircraftPath: 'Aircraft/B738/b738.acf',
        );
        expect((await changed)['v'], {'1': 13});
      },
    );

    test('the same generation is in the aircraft json', () async {
      final c = await connect();
      sub(c, 1, 'flightsim_aide/aircraft_generation', 1);
      final v = (await c.next({'op': 'values'}))['v']! as Map<String, Object?>;
      final http = HttpClient();
      final req = await http.getUrl(server.baseUri.resolve('/v1/aircraft'));
      final res = await req.close();
      final json =
          jsonDecode(await utf8.decodeStream(res)) as Map<String, Object?>;
      expect(v['1'], json['generation']);
      http.close();
    });
  });

  group('stream errors and faults', () {
    test('unknown name, unsupported type, bad request and set', () async {
      final c = await connect();
      final unknown = c.next({'op': 'error', 'id': 2});
      sub(c, 2, 'no/such/dataref', 1);
      expect((await unknown)['code'], 'unknown_name');
      final unsupported = c.next({'op': 'error', 'id': 3});
      sub(c, 3, 'sim/cockpit2/engine/actuators/throttle_ratio', 1);
      expect((await unsupported)['code'], 'unsupported');
      final bad = c.next({'op': 'error', 'code': 'bad_request'});
      c.send('this is not json');
      expect(await bad, isNotNull);
      final set = c.next({'op': 'error', 'id': 7});
      c.send({'op': 'set', 'id': 7, 'name': _onGround, 'value': 0});
      expect((await set)['code'], 'unsupported');
    });

    test('the 129th subscription is over the limit', () async {
      final c = await connect();
      for (var i = 1; i <= 129; i++) {
        sub(c, i, _onGround, 1);
      }
      expect((await c.next({'op': 'error', 'id': 129}))['code'], 'limit');
    });

    test('fifth client gets 503', () async {
      for (var i = 0; i < 4; i++) {
        await connect();
      }
      final http = HttpClient();
      final req = await http.getUrl(server.baseUri.resolve('/v1/stream'));
      req.headers
        ..set('connection', 'Upgrade')
        ..set('upgrade', 'websocket')
        ..set('sec-websocket-version', '13')
        ..set('sec-websocket-key', base64.encode(List.filled(16, 7)));
      final res = await req.close();
      expect(res.statusCode, 503);
      expect(
        jsonDecode(await utf8.decodeStream(res)),
        containsPair('error', 'limit'),
      );
      http.close();
    });

    test('a closed client frees its slot', () async {
      final first = await connect();
      for (var i = 0; i < 3; i++) {
        await connect();
      }
      await first.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await connect(), isNotNull);
    });

    test('dropStreamConnections closes the client', () async {
      final c = await connect();
      final closed = c.closed;
      await server.dropStreamConnections();
      await closed.timeout(const Duration(seconds: 2));
      expect(c.socket.closeCode, isNotNull);
    });

    test('restart closes streams and changes the port', () async {
      final c = await connect();
      final closed = c.closed;
      final old = server.port;
      await server.restart();
      await closed.timeout(const Duration(seconds: 2));
      expect(server.port, isNot(old));
      final again = await connect();
      final pong = again.next({'op': 'pong'});
      again.send({'op': 'ping'});
      expect(await pong, {'op': 'pong'});
    });

    test('silence sends no frame at all', () async {
      final c = await connect();
      sub(c, 1, _onGround, 20);
      await c.next({'op': 'values'});
      server.silence();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      c.frames.clear();
      c.send({'op': 'ping'});
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(c.frames, isEmpty);
    });

    test('delayAck holds back the acknowledgement', () async {
      server.delayAck(const Duration(milliseconds: 600));
      final c = await connect();
      final sw = Stopwatch()..start();
      sub(c, 1, _onGround, 2);
      await c.next({'op': 'subscribed'});
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(550));
    });
  });
}
