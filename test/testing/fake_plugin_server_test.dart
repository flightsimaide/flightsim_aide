import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../testing/fakes/plugin/fake_companion_plugin_server.dart';

const _dir = 'testing/fixtures/protocol';

String _golden(String name) => File('$_dir/$name').readAsStringSync();

void main() {
  late FakeCompanionPluginServer server;

  setUp(() async {
    server = await FakeCompanionPluginServer.start();
  });

  tearDown(() async {
    await server.close();
  });

  Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  group('happy path', () {
    test('hello matches golden', () async {
      final r = await http.get(url('/v1/hello'));
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], 'application/json; charset=utf-8');
      expect(r.headers['cache-control'], 'no-store');
      final expected = _golden('hello.json')
          .replaceFirst('"port":18086', '"port":${server.port}');
      expect(utf8.decode(r.bodyBytes), expected);
    });

    test('aircraft json matches golden', () async {
      final r = await http.get(url('/v1/aircraft'));
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], 'application/json; charset=utf-8');
      expect(r.headers['cache-control'], 'no-store');
      expect(utf8.decode(r.bodyBytes), _golden('aircraft_with_checklist.json'));
    });

    test('checklist returns bytes and etag', () async {
      final r = await http.get(url('/v1/checklist'));
      final bytes = File('$_dir/checklist_sample.txt').readAsBytesSync();
      expect(r.statusCode, 200);
      expect(r.bodyBytes, bytes);
      expect(r.headers['content-type'], 'text/plain');
      expect(r.headers['content-length'], '${bytes.length}');
      expect(r.headers['x-aircraft-generation'], '12');
      expect(r.headers['last-modified'], isNotNull);
      expect(r.headers['etag'], isNotNull);
    });

    test('etag is quoted mtime-size', () async {
      final r = await http.get(url('/v1/checklist'));
      expect(r.headers['etag'], '"1761206400123-267"');
    });

    test('matching if-none-match gives 304', () async {
      final r = await http.get(
        url('/v1/checklist'),
        headers: {'If-None-Match': '"1761206400123-267"'},
      );
      expect(r.statusCode, 304);
      expect(r.headers['etag'], '"1761206400123-267"');
      expect(r.bodyBytes, isEmpty);
    });

    test('a list, a weak value and a star all match', () async {
      for (final h in ['"1-1", W/"1761206400123-267"', '*']) {
        final r = await http.get(
          url('/v1/checklist'),
          headers: {'If-None-Match': h},
        );
        expect(r.statusCode, 304, reason: h);
      }
    });

    test('a different etag gets the body', () async {
      final r = await http.get(
        url('/v1/checklist'),
        headers: {'If-None-Match': '"1761206400123-268"'},
      );
      expect(r.statusCode, 200);
    });

    test('head has no body', () async {
      final r = await http.head(url('/v1/aircraft'));
      expect(r.statusCode, 200);
      expect(r.bodyBytes, isEmpty);
      expect(
        r.headers['content-length'],
        '${_golden('aircraft_with_checklist.json').length}',
      );
    });
  });

  group('errors and edge responses', () {
    Map<String, Object?> body(http.Response r) =>
        jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;

    test('no checklist gives 404 and error body', () async {
      server.useScenario('no_checklist');
      final r = await http.get(url('/v1/checklist'));
      expect(r.statusCode, 404);
      expect(utf8.decode(r.bodyBytes), _golden('error_404.json'));
      final a = await http.get(url('/v1/aircraft'));
      expect(utf8.decode(a.bodyBytes), _golden('aircraft_no_checklist.json'));
    });

    test('POST gives 405', () async {
      final r = await http.post(url('/v1/aircraft'));
      expect(r.statusCode, 405);
      expect(r.headers['allow'], 'GET, HEAD');
      expect(body(r)['error'], 'method_not_allowed');
      expect((await http.put(url('/v1/checklist'))).statusCode, 405);
      expect((await http.delete(url('/v1/hello'))).statusCode, 405);
      expect((await http.post(url('/v1/stream'))).statusCode, 405);
    });

    test('unknown path gives 404', () async {
      for (final path in [
        '/',
        '/v1/other',
        '/v1/checklist/..%2f..%2fetc%2fpasswd',
        '/v1/%2e%2e/aircraft',
        '//v1/aircraft',
      ]) {
        final r = await http.get(url(path));
        expect(r.statusCode, 404, reason: path);
      }
      final r = await http.post(url('/nothing'));
      expect(r.statusCode, 404);
      expect(body(r)['error'], 'not_found');
    });

    test('query string is ignored', () async {
      final a = await http.get(url('/v1/aircraft?icao=B738&path=../x'));
      expect(utf8.decode(a.bodyBytes), _golden('aircraft_with_checklist.json'));
      final c = await http.get(url('/v1/checklist?path=../x'));
      expect(c.statusCode, 200);
      expect(c.bodyBytes, File('$_dir/checklist_sample.txt').readAsBytesSync());
    });

    test('oversize gives 413', () async {
      server.useScenario('oversize');
      final r = await http.get(url('/v1/checklist'));
      expect(r.statusCode, 413);
      expect(body(r)['error'], 'too_large');
    });

    test('plain GET on the stream path gives 400', () async {
      final r = await http.get(url('/v1/stream'));
      expect(r.statusCode, 400);
      expect(body(r)['error'], 'upgrade_required');
    });
  });

  group('scripting hooks', () {
    Map<String, Object?> aircraft(http.Response r) =>
        jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;

    void loadOther() => server.loadAircraft(
      icao: 'B738',
      description: 'Boeing 737-800',
      aircraftPath: 'Aircraft/Laminar Research/Boeing B737-800/b738.acf',
      checklistBytes: utf8.encode('sw_checklist:A\nsw_item:K|V\n'),
    );

    test('load aircraft bumps generation', () async {
      loadOther();
      final a = aircraft(await http.get(url('/v1/aircraft')));
      expect(a['generation'], 13);
      expect(a['icao'], 'B738');
      expect(a['checklistSize'], 27);
      final c = await http.get(url('/v1/checklist'));
      expect(c.headers['x-aircraft-generation'], '13');
    });

    test('load aircraft without a checklist omits the fields', () async {
      server.loadAircraft(
        icao: 'A320',
        description: 'Airbus A320',
        aircraftPath: 'Aircraft/A320/a320.acf',
      );
      final a = aircraft(await http.get(url('/v1/aircraft')));
      expect(a.containsKey('checklistModified'), isFalse);
      expect((await http.get(url('/v1/checklist'))).statusCode, 404);
    });

    test('generation wraps at 2^31', () async {
      server.generation = 0x7fffffff;
      loadOther();
      expect(server.generation, 0);
    });

    test('edit keeps generation', () async {
      final before = aircraft(await http.get(url('/v1/aircraft')));
      server.editChecklist('sw_checklist:Edited\nsw_item:X|Y\n');
      final after = aircraft(await http.get(url('/v1/aircraft')));
      expect(after['generation'], before['generation']);
      expect(
        after['checklistModified'],
        greaterThan(before['checklistModified']! as int),
      );
      expect(after['checklistSize'], isNot(before['checklistSize']));
      final c = await http.get(url('/v1/checklist'));
      expect(c.body, startsWith('sw_checklist:Edited'));
      expect(c.headers['etag'], server.etag);
    });

    test('restore older lowers the mtime', () async {
      final before = aircraft(await http.get(url('/v1/aircraft')));
      server.restoreOlder();
      final after = aircraft(await http.get(url('/v1/aircraft')));
      expect(
        after['checklistModified'],
        lessThan(before['checklistModified']! as int),
      );
      expect(after['generation'], before['generation']);
    });

    test('delayNext delays only the next request', () async {
      server.delayNext(const Duration(milliseconds: 400));
      final sw = Stopwatch()..start();
      await http.get(url('/v1/hello'));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(380));
      sw.reset();
      await http.get(url('/v1/hello'));
      expect(sw.elapsedMilliseconds, lessThan(300));
    });

    test('dropNext closes the connection, then recovers', () async {
      server.dropNext();
      await expectLater(http.get(url('/v1/hello')), throwsA(anything));
      expect((await http.get(url('/v1/hello'))).statusCode, 200);
    });

    test('malformedAircraft sends broken json once', () async {
      server.malformedAircraft();
      final bad = await http.get(url('/v1/aircraft'));
      expect(() => jsonDecode(bad.body), throwsFormatException);
      final good = await http.get(url('/v1/aircraft'));
      expect(aircraft(good)['icao'], 'C172');
    });

    test('protocolVersion shows in hello and aircraft', () async {
      server.protocolVersion = 2;
      final h = aircraft(await http.get(url('/v1/hello')));
      final a = aircraft(await http.get(url('/v1/aircraft')));
      expect(h['protocolVersion'], 2);
      expect(a['protocolVersion'], 2);
    });

    test(
      'changeAircraftBetweenRequests changes after the next aircraft',
      () async {
        server.changeAircraftBetweenRequests();
        final first = aircraft(await http.get(url('/v1/aircraft')));
        expect(first['icao'], 'C172');
        final c = await http.get(url('/v1/checklist'));
        expect(
          c.headers['x-aircraft-generation'],
          isNot('${first['generation']}'),
        );
        final second = aircraft(await http.get(url('/v1/aircraft')));
        expect(second['generation'], isNot(first['generation']));
        expect(second['icao'], isNot('C172'));
      },
    );

    test('restart changes the port and keeps the state', () async {
      loadOther();
      final oldPort = server.port;
      await server.restart();
      expect(server.port, isNot(oldPort));
      final a = aircraft(await http.get(url('/v1/aircraft')));
      expect(a['icao'], 'B738');
      await expectLater(
        http.get(Uri.parse('http://127.0.0.1:$oldPort/v1/hello')),
        throwsA(anything),
      );
    });
  });

  test('requests counts hits per path', () async {
    final server = await FakeCompanionPluginServer.start();
    addTearDown(server.close);
    final client = HttpClient();
    addTearDown(client.close);
    for (final path in ['/v1/aircraft', '/v1/aircraft', '/v1/hello']) {
      final req = await client.getUrl(server.baseUri.replace(path: path));
      await (await req.close()).drain<void>();
    }
    expect(server.requests['/v1/aircraft'], 2);
    expect(server.requests['/v1/hello'], 1);
    expect(server.requests['/v1/checklist'], isNull);
  });
}
