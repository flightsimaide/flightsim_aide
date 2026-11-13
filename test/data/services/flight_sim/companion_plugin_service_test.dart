import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flightsim_aide/data/services/flight_sim/companion_plugin_service.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/plugin_endpoint.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/raw_aircraft_info.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/raw_checklist_response.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/raw_hello.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../testing/fakes/plugin/fake_companion_plugin_server.dart';

void main() {
  late FakeCompanionPluginServer server;
  late HttpCompanionPluginService service;
  late PluginEndpoint endpoint;

  setUp(() async {
    server = await FakeCompanionPluginServer.start();
    service = HttpCompanionPluginService(
      client: http.Client(),
      timeout: const Duration(milliseconds: 400),
    );
    endpoint = PluginEndpoint(host: '127.0.0.1', port: server.port);
  });

  tearDown(() async {
    service.dispose();
    await server.close();
  });

  AppException? errorOf<T>(Result<T> r) => r.errorOrNull;

  HttpCompanionPluginService stubbed(int status, String body) =>
      HttpCompanionPluginService(client: _StubClient(status, body));

  group('hello', () {
    test('parses the golden hello', () async {
      final result = await service.getHello('127.0.0.1', server.port);
      expect(
        result.valueOrNull,
        RawHello(
          protocolVersion: 1,
          port: server.port,
          streamPath: '/v1/stream',
          runId: 'a1b2c3d4e5f60718',
          simKind: 'xplane',
          simVersion: '12.1.4',
          os: 'windows',
          pluginVersion: '0.1.0',
        ),
      );
    });

    test('a hello without os still parses, with os null', () async {
      final stub = stubbed(
        200,
        '{"protocolVersion":1,"port":18086,"streamPath":"/v1/stream",'
        '"runId":"r"}',
      );
      final result = await stub.getHello('h', 18086);
      expect(result.valueOrNull?.os, isNull);
      expect(result.valueOrNull?.protocolVersion, 1);
    });

    test('the hello carries the run id', () async {
      server.runId = 'run-7';
      final result = await service.getHello('127.0.0.1', server.port);
      expect(result.valueOrNull?.runId, 'run-7');
    });

    test('a hello without a run id is ProtocolError', () async {
      final stub = stubbed(
        200,
        '{"protocolVersion":1,"port":18086,"streamPath":"/v1/stream"}',
      );
      expect(errorOf(await stub.getHello('h', 18086)), isA<ProtocolError>());
    });

    test('a hello from another protocol version is still returned', () async {
      server.protocolVersion = 2;
      final result = await service.getHello('127.0.0.1', server.port);
      expect(result.valueOrNull?.protocolVersion, 2);
    });

    test('hello without port is ProtocolError', () async {
      final stub = stubbed(
        200,
        '{"protocolVersion":1,"streamPath":"/v1/stream"}',
      );
      expect(errorOf(await stub.getHello('h', 1)), isA<ProtocolError>());
    });

    test('a non-200 hello is ProtocolError', () async {
      final stub = stubbed(500, '{}');
      expect(errorOf(await stub.getHello('h', 1)), isA<ProtocolError>());
    });

    test('nothing listening gives PluginUnreachable', () async {
      final result = await service.getHello('127.0.0.1', 1);
      expect(errorOf(result), isA<PluginUnreachable>());
    });

    test('plain refusal is not flagged as no route', () async {
      final result = await service.getHello('127.0.0.1', 1);
      expect((errorOf(result)! as PluginUnreachable).noRouteToHost, isFalse);
    });

    test('errno 65 on a socket is flagged as no route', () async {
      final failing = HttpCompanionPluginService(
        client: _FailingClient(
          const SocketException(
            'Connection failed',
            osError: OSError('No route to host', 65),
          ),
        ),
      );
      final error = errorOf(await failing.getHello('h', 1));
      expect((error! as PluginUnreachable).noRouteToHost, isTrue);
    });

    test('errno 65 wrapped in a ClientException is flagged', () async {
      final failing = HttpCompanionPluginService(
        client: _FailingClient(
          http.ClientException(
            'SocketException: Connection failed '
            '(OS Error: No route to host, errno = 65), address = h, port = 1',
          ),
        ),
      );
      final error = errorOf(await failing.getHello('h', 1));
      expect((error! as PluginUnreachable).noRouteToHost, isTrue);
    });

    test('another errno is not flagged', () async {
      final failing = HttpCompanionPluginService(
        client: _FailingClient(
          const SocketException(
            'Connection failed',
            osError: OSError('Connection refused', 61),
          ),
        ),
      );
      final error = errorOf(await failing.getHello('h', 1));
      expect((error! as PluginUnreachable).noRouteToHost, isFalse);
    });
  });

  group('aircraft', () {
    test('parses the golden aircraft', () async {
      final result = await service.getAircraft(endpoint);
      expect(
        result.valueOrNull,
        const RawAircraftInfo(
          protocolVersion: 1,
          generation: 12,
          icao: 'C172',
          description: 'Cessna Skyhawk 172SP',
          aircraftPath:
              'Aircraft/Laminar Research/Cessna 172SP/Cessna_172SP.acf',
          checklistPath: 'Aircraft/Laminar Research/Cessna 172SP/clist.txt',
          checklistModified: 1761206400123,
          checklistSize: 267,
        ),
      );
    });

    test('no checklist fields stay null', () async {
      server.useScenario('no_checklist');
      final info = (await service.getAircraft(endpoint)).valueOrNull!;
      expect(info.checklistPath, isNull);
      expect(info.checklistModified, isNull);
      expect(info.checklistSize, isNull);
    });

    test('unknown fields are ignored', () async {
      final stub = stubbed(
        200,
        '{"protocolVersion":1,"generation":3,"aircraftPath":"a.acf",'
        '"extra":{"x":1}}',
      );
      final info = (await stub.getAircraft(endpoint)).valueOrNull!;
      expect(info.generation, 3);
      expect(info.icao, '');
    });

    test('malformed json gives ProtocolError', () async {
      server.malformedAircraft();
      expect(
        errorOf(await service.getAircraft(endpoint)),
        isA<ProtocolError>(),
      );
    });

    test('missing aircraftPath gives ProtocolError', () async {
      final stub = stubbed(200, '{"protocolVersion":1,"generation":3}');
      expect(errorOf(await stub.getAircraft(endpoint)), isA<ProtocolError>());
    });

    test('wrong protocol version gives PluginVersionMismatch', () async {
      server.protocolVersion = 2;
      final error = errorOf(await service.getAircraft(endpoint));
      expect(error, isA<PluginVersionMismatch>());
      expect((error! as PluginVersionMismatch).found, 2);
      expect((error as PluginVersionMismatch).required, 1);
    });

    test('timeout gives PluginUnreachable', () async {
      server.delayNext(const Duration(seconds: 2));
      expect(
        errorOf(await service.getAircraft(endpoint)),
        isA<PluginUnreachable>(),
      );
    });

    test('dropped connection gives PluginUnreachable', () async {
      server.dropNext();
      expect(
        errorOf(await service.getAircraft(endpoint)),
        isA<PluginUnreachable>(),
      );
    });

    test('server restart on a new port gives an error then success', () async {
      await server.restart();
      expect(
        errorOf(await service.getAircraft(endpoint)),
        isA<PluginUnreachable>(),
      );
      final moved = PluginEndpoint(host: '127.0.0.1', port: server.port);
      expect((await service.getAircraft(moved)).isOk, isTrue);
    });
  });

  group('checklist', () {
    test('200 returns bytes etag and generation', () async {
      final fetch = (await service.getChecklist(endpoint)).valueOrNull;
      expect(fetch, isA<RawChecklistResponse>());
      final response = fetch! as RawChecklistResponse;
      expect(response.bytes, server.checklistBytes);
      expect(response.etag, '"1761206400123-267"');
      expect(response.generation, 12);
    });

    test('304 returns NotModified', () async {
      final fetch = await service.getChecklist(
        endpoint,
        ifNoneMatch: server.etag,
      );
      expect(fetch.valueOrNull, isA<NotModified>());
    });

    test('if-none-match header is sent', () async {
      final stub = _StubClient(304, '');
      final svc = HttpCompanionPluginService(client: stub);
      await svc.getChecklist(endpoint, ifNoneMatch: '"1-2"');
      expect(stub.lastHeaders['if-none-match'], '"1-2"');
      await svc.getChecklist(endpoint);
      expect(stub.lastHeaders.containsKey('if-none-match'), isFalse);
    });

    test('404 gives NoChecklistForAircraft', () async {
      server.useScenario('no_checklist');
      expect(
        errorOf(await service.getChecklist(endpoint)),
        isA<NoChecklistForAircraft>(),
      );
    });

    test('413 gives ProtocolError', () async {
      server.useScenario('oversize');
      expect(
        errorOf(await service.getChecklist(endpoint)),
        isA<ProtocolError>(),
      );
    });

    test('crlf bytes are preserved exactly', () async {
      final bytes = utf8.encode('sw_checklist:A\r\nsw_item:x|y\r\n');
      server.loadAircraft(
        icao: 'X',
        description: 'x',
        aircraftPath: 'a/b.acf',
        checklistBytes: bytes,
      );
      final r =
          (await service.getChecklist(endpoint)).valueOrNull!
              as RawChecklistResponse;
      expect(r.bytes, bytes);
    });

    test('non-utf8 bytes are preserved exactly', () async {
      final bytes = Uint8List.fromList([0x73, 0x77, 0xe9, 0xff, 0x0a, 0x80]);
      server.loadAircraft(
        icao: 'X',
        description: 'x',
        aircraftPath: 'a/b.acf',
        checklistBytes: bytes,
      );
      final r =
          (await service.getChecklist(endpoint)).valueOrNull!
              as RawChecklistResponse;
      expect(r.bytes, bytes);
    });

    test('a 200 without an etag is ProtocolError', () async {
      final stub = stubbed(200, 'x');
      expect(errorOf(await stub.getChecklist(endpoint)), isA<ProtocolError>());
    });
  });
}

/// Answers every request with a fixed status and body, and remembers the
/// headers of the last request.
class _FailingClient extends http.BaseClient {
  _FailingClient(this.error);
  final Object error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(error);
}

class _StubClient extends http.BaseClient {
  _StubClient(this.status, this.body);
  final int status;
  final String body;
  Map<String, String> lastHeaders = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastHeaders = request.headers;
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      headers: const {'content-type': 'application/json'},
    );
  }
}
