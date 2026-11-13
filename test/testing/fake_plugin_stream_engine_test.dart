import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../testing/fakes/plugin/fake_plugin_stream_engine.dart';

const _onGround = 'sim/flightmodel/failures/onground_any';

class _Clock {
  DateTime now = DateTime.utc(2026, 10, 24, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  late _Clock clock;
  late FakePluginStreamEngine engine;
  late List<Map<String, Object?>> out;
  late FakeStreamClient client;

  setUp(() {
    clock = _Clock();
    engine = FakePluginStreamEngine(
      now: clock.call,
      signals: {_onGround: 1, 'flightsim_aide/aircraft_generation': 12},
      arrays: {
        'arr/float': [0.25, 0.5],
        'arr/int': [3, 0],
      },
      unsupported: {'array/dataref'},
    );
    out = [];
    client = engine.addClient(
      (s) => out.add(jsonDecode(s) as Map<String, Object?>),
    );
  });

  void send(Object frame) =>
      engine.receive(client, frame is String ? frame : jsonEncode(frame));

  void sub(int id, String name, int hz) =>
      send({'op': 'subscribe', 'id': id, 'name': name, 'hz': hz});

  /// Advances the fake clock in [step] ticks for [total].
  void run(Duration total, {Duration step = const Duration(milliseconds: 10)}) {
    var left = total;
    while (left > Duration.zero) {
      clock.advance(step);
      engine.tick();
      left -= step;
    }
  }

  Iterable<Map<String, Object?>> ops(String op) =>
      out.where((f) => f['op'] == op);

  group('subscribe', () {
    test('is acknowledged at the next tick, not before', () {
      sub(1, _onGround, 2);
      expect(out, isEmpty);
      engine.tick();
      expect(out.first, {'op': 'subscribed', 'id': 1});
      expect(out[1]['op'], 'values');
    });

    test('unknown name gets unknown_name and no values', () {
      sub(2, 'no/such', 1);
      engine.tick();
      expect(out.single['op'], 'error');
      expect(out.single['id'], 2);
      expect(out.single['code'], 'unknown_name');
      run(const Duration(seconds: 2));
      expect(ops('values'), isEmpty);
    });

    test('an unsupported type gets unsupported', () {
      sub(3, 'array/dataref', 1);
      engine.tick();
      expect(out.single['code'], 'unsupported');
    });

    group('array elements', () {
      test('an element reads its value, int and float', () {
        sub(1, 'arr/float[1]', 1);
        sub(2, 'arr/int[0]', 1);
        engine.tick();
        expect(ops('subscribed').map((f) => f['id']), [1, 2]);
        expect(ops('values').single['v'], {'1': 0.5, '2': 3});
      });

      test('an index past the end is accepted and reads null', () {
        sub(1, 'arr/float[99]', 1);
        engine.tick();
        expect(ops('subscribed').single['id'], 1);
        expect(ops('values').single['v'], {'1': null});
      });

      test(
        'the bare array is unsupported, an index on a scalar is unknown',
        () {
          sub(1, 'arr/float', 1);
          sub(2, '$_onGround[0]', 1);
          sub(3, 'no/such[0]', 1);
          engine.tick();
          expect(ops('error').map((f) => f['code']), [
            'unsupported',
            'unknown_name',
            'unknown_name',
          ]);
        },
      );

      test('a malformed index is a bad request', () {
        for (final name in [
          'arr/float[',
          'arr/float[]',
          'arr/float[a]',
          'arr/float[-1]',
          'arr/float[1]x',
          'arr/float[1][2]',
          'arr/float[1234567]',
        ]) {
          out.clear();
          sub(1, name, 1);
          expect(out.single['code'], 'bad_request', reason: name);
        }
      });
    });

    test('bad frames get bad_request', () {
      send('not json');
      send({'op': 'subscribe', 'id': 4, 'hz': 1});
      send({'op': 'subscribe', 'id': 5, 'name': _onGround, 'hz': 0});
      send({'op': 'subscribe', 'id': 6, 'name': _onGround, 'hz': 61});
      send({'op': 'subscribe', 'id': 7, 'name': _onGround, 'hz': 1.5});
      send({'op': 'subscribe', 'id': -1, 'name': _onGround, 'hz': 1});
      send({'op': 'frobnicate'});
      send([1, 2]);
      send('x' * 5000);
      expect(out, hasLength(9));
      expect(out.every((f) => f['code'] == 'bad_request'), isTrue);
      expect(out[1]['id'], 4);
      expect(out[0].containsKey('id'), isFalse);
    });

    test('unsubscribe without an id is a bad request', () {
      send({'op': 'unsubscribe'});
      expect(out.single, containsPair('code', 'bad_request'));
    });

    test('set is unsupported', () {
      send({'op': 'set', 'id': 7, 'name': _onGround, 'value': 0});
      expect(out.single, containsPair('code', 'unsupported'));
      expect(out.single['id'], 7);
    });
  });

  group('values', () {
    test('arrive at the requested rate', () {
      sub(1, _onGround, 2);
      run(const Duration(seconds: 2));
      expect(ops('values').length, inInclusiveRange(4, 5));
      expect(ops('values').first['v'], {'1': 1});
    });

    test('never faster than hz', () {
      sub(1, _onGround, 60);
      run(const Duration(seconds: 1), step: const Duration(milliseconds: 1));
      expect(ops('values').length, lessThanOrEqualTo(61));
      expect(ops('values').length, greaterThan(55));
    });

    test('latest value wins when the sender is late', () {
      sub(1, _onGround, 10);
      engine.tick();
      out.clear();
      clock.advance(const Duration(seconds: 1));
      engine.setSignal(_onGround, 0);
      engine.tick();
      expect(ops('values'), hasLength(1));
      expect(ops('values').single['v'], {'1': 0});
      clock.advance(const Duration(milliseconds: 20));
      engine.tick();
      expect(ops('values'), hasLength(1), reason: 'no catch-up burst');
    });

    test('t is the sample time in epoch milliseconds', () {
      sub(1, _onGround, 1);
      engine.tick();
      expect(ops('values').single['t'], clock.now.millisecondsSinceEpoch);
    });

    test('two subscriptions share one frame when due together', () {
      sub(1, _onGround, 2);
      sub(2, 'flightsim_aide/aircraft_generation', 2);
      engine.tick();
      expect(ops('values').single['v'], {'1': 1, '2': 12});
    });

    test('unsubscribe stops values', () {
      sub(1, _onGround, 10);
      run(const Duration(milliseconds: 300));
      send({'op': 'unsubscribe', 'id': 1});
      out.clear();
      run(const Duration(seconds: 1));
      expect(ops('values'), isEmpty);
    });

    test('a repeated id replaces the subscription', () {
      sub(1, _onGround, 1);
      engine.tick();
      sub(1, 'flightsim_aide/aircraft_generation', 1);
      run(const Duration(milliseconds: 100));
      expect(ops('values').last['v'], {'1': 12});
    });

    test('integers print as integers and non-finite as null', () {
      engine.setSignal('i', 7);
      engine.setSignal('nan', double.nan);
      final raw = <String>[];
      final c = engine.addClient(raw.add);
      engine.receive(
        c,
        jsonEncode({'op': 'subscribe', 'id': 1, 'name': 'i', 'hz': 1}),
      );
      engine.receive(
        c,
        jsonEncode({'op': 'subscribe', 'id': 2, 'name': 'nan', 'hz': 1}),
      );
      engine.tick();
      final values = raw.firstWhere((s) => s.contains('"values"'));
      expect(values, contains('"1":7,'));
      expect(values, contains('"2":null'));
    });
  });

  group('housekeeping', () {
    test('ping gets pong at once', () {
      send({'op': 'ping'});
      expect(out.single, {'op': 'pong'});
    });

    test('heartbeat after 1 s of idle, not before', () {
      run(const Duration(milliseconds: 900));
      expect(ops('hb'), isEmpty);
      run(const Duration(milliseconds: 200));
      expect(ops('hb'), hasLength(1));
    });

    test('values frames count as activity for the heartbeat', () {
      sub(1, _onGround, 5);
      run(const Duration(seconds: 3));
      expect(ops('hb'), isEmpty);
    });

    test('generation is delivered at subscribe and at every change', () {
      sub(1, 'flightsim_aide/aircraft_generation', 1);
      engine.tick();
      expect(ops('values').single['v'], {'1': 12});
      out.clear();
      engine.setSignal('flightsim_aide/aircraft_generation', 13);
      expect(ops('values').single['v'], {'1': 13}, reason: 'at once, no tick');
    });

    test('129th subscription is over the limit, a replaced id is not', () {
      for (var i = 1; i <= 128; i++) {
        sub(i, _onGround, 1);
      }
      expect(out, isEmpty);
      sub(129, _onGround, 1);
      expect(out.single['code'], 'limit');
      expect(out.single['id'], 129);
      out.clear();
      sub(1, _onGround, 2);
      expect(out, isEmpty);
    });

    test('removing a client stops its frames', () {
      sub(1, _onGround, 10);
      engine.removeClient(client);
      run(const Duration(seconds: 2));
      expect(out, isEmpty);
    });

    test('silence sends nothing at all', () {
      sub(1, _onGround, 10);
      engine.silenced = true;
      run(const Duration(seconds: 3));
      send({'op': 'ping'});
      expect(out, isEmpty);
    });

    test('ack delay holds back the acknowledgement', () {
      engine.ackDelay = const Duration(milliseconds: 500);
      sub(1, _onGround, 2);
      run(const Duration(milliseconds: 400));
      expect(out, isEmpty);
      run(const Duration(milliseconds: 200));
      expect(out.first['op'], 'subscribed');
    });
  });

  test(
    'clientCount and subscriptionCount follow clients and subscriptions',
    () {
      expect(engine.clientCount, 1);
      expect(engine.subscriptionCount, 0);
      sub(1, _onGround, 2);
      sub(2, 'flightsim_aide/aircraft_generation', 1);
      expect(engine.subscriptionCount, 2);
      send({'op': 'unsubscribe', 'id': 1});
      expect(engine.subscriptionCount, 1);
      engine.removeClient(client);
      expect(engine.clientCount, 0);
      expect(engine.subscriptionCount, 0);
    },
  );
}
