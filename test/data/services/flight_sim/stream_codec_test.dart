import 'dart:io';
import 'dart:math';

import 'package:flightsim_aide/data/services/flight_sim/model/raw_frame.dart';
import 'package:flightsim_aide/data/services/flight_sim/stream_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subscribe frame equals the golden', () {
    final golden = File('testing/fixtures/protocol/frame_subscribe.json')
        .readAsStringSync();
    expect(
      encodeSubscribe(1, 'sim/flightmodel/failures/onground_any', 2),
      golden,
    );
  });

  test('unsubscribe and ping frames', () {
    expect(encodeUnsubscribe(3), '{"op":"unsubscribe","id":3}');
    expect(encodePing(), '{"op":"ping"}');
  });

  test('subscribed frame decodes', () {
    expect(decodeFrame('{"op":"subscribed","id":1}'), const Subscribed(1));
  });

  test('values frame decodes', () {
    final frame = decodeFrame(
      '{"op":"values","t":1761206400123,"v":{"1":1,"2":100.5,"3":null}}',
    );
    expect(frame, const Values(1761206400123, {1: 1, 2: 100.5, 3: null}));
  });

  test('error frame carries the code', () {
    expect(
      decodeFrame('{"op":"error","id":2,"code":"unknown_name","message":"x"}'),
      const StreamError('unknown_name', id: 2),
    );
    expect(
      decodeFrame('{"op":"error","code":"bad_request"}'),
      const StreamError('bad_request'),
    );
  });

  test('heartbeat and pong decode', () {
    expect(decodeFrame('{"op":"hb"}'), const Heartbeat());
    expect(decodeFrame('{"op":"pong"}'), const Pong());
  });

  test('unknown fields are ignored', () {
    expect(
      decodeFrame('{"op":"subscribed","id":1,"extra":[1,2]}'),
      const Subscribed(1),
    );
  });

  test('unknown op gives null', () {
    expect(decodeFrame('{"op":"dance"}'), isNull);
    expect(decodeFrame('{"id":1}'), isNull);
  });

  test('invalid json gives null', () {
    expect(decodeFrame('not json'), isNull);
    expect(decodeFrame(''), isNull);
    expect(decodeFrame('[1,2]'), isNull);
    expect(decodeFrame('{"op":"values"'), isNull);
  });

  test('wrong shapes give null', () {
    expect(decodeFrame('{"op":"subscribed","id":"1"}'), isNull);
    expect(decodeFrame('{"op":"values","t":1,"v":[1]}'), isNull);
    expect(decodeFrame('{"op":"values","t":1,"v":{"x":1}}'), isNull);
    expect(decodeFrame('{"op":"values","t":1,"v":{"1":"high"}}'), isNull);
    expect(decodeFrame('{"op":"values","v":{}}'), isNull);
  });

  test('non-string error code is rejected', () {
    expect(decodeFrame('{"op":"error","id":1,"code":5}'), isNull);
    expect(decodeFrame('{"op":"error","id":1}'), isNull);
  });

  test('an invalid subscription is refused before it is sent', () {
    expect(() => encodeSubscribe(1, '', 2), throwsArgumentError);
    expect(() => encodeSubscribe(1, 'a' * 201, 2), throwsArgumentError);
    expect(() => encodeSubscribe(1, 'a\nb', 2), throwsArgumentError);
    expect(() => encodeSubscribe(1, 'x', 0), throwsArgumentError);
    expect(() => encodeSubscribe(1, 'x', 61), throwsArgumentError);
    expect(() => encodeSubscribe(-1, 'x', 2), throwsArgumentError);
  });

  test('1000 seeded random strings never throw', () {
    final random = Random(7);
    const pieces = [
      '{',
      '}',
      '"op"',
      ':',
      '"values"',
      '"v"',
      ',',
      '1',
      'null',
      '[',
    ];
    for (var i = 0; i < 1000; i++) {
      final text = i.isEven
          ? String.fromCharCodes(
              List.generate(random.nextInt(60), (_) => random.nextInt(0x250)),
            )
          : List.generate(
              random.nextInt(14),
              (_) => pieces[random.nextInt(pieces.length)],
            ).join();
      expect(() => decodeFrame(text), returnsNormally, reason: text);
    }
  });

  test('a values frame can carry lists for range subscriptions', () {
    final frame = decodeFrame(
      '{"op":"values","t":5,"v":{"1":2,"7":[1,0.5,null],"8":[]}}',
    );
    expect(
      frame,
      const Values(
        5,
        {1: 2},
        lists: {
          7: [1, 0.5, null],
          8: [],
        },
      ),
    );
  });

  test('a list holding something else than numbers is not a frame', () {
    expect(decodeFrame('{"op":"values","t":5,"v":{"7":[1,"x"]}}'), isNull);
    expect(decodeFrame('{"op":"values","t":5,"v":{"7":{"a":1}}}'), isNull);
  });
}
