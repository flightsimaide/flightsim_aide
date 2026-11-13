import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flightsim_aide/data/services/checklist/model/raw_checklist_document.dart';
import 'package:flightsim_aide/data/services/checklist/network_checklist_source_service.dart';
import 'package:flightsim_aide/data/services/flight_sim/companion_plugin_service.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/plugin_endpoint.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/plugin_session.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/raw_aircraft_info.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/raw_checklist_response.dart';
import 'package:flightsim_aide/data/services/local/checklist_cache_service.dart';
import 'package:flightsim_aide/data/services/local/model/cached_checklist.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../testing/fakes/plugin/fake_companion_plugin_server.dart';
import '../../../../testing/fakes/services/fake_plugin_session_source.dart';

// AC-13: cache: unchanged file transfers no body, changed file is refetched
// AC-14: aircraft without checklist gives NoChecklistForAircraft
// AC-15: corrupt cache entry is refetched

void main() {
  late FakeCompanionPluginServer server;
  late HttpCompanionPluginService companion;
  late FakePluginSessionSource sessions;
  late Directory dir;
  late FileChecklistCacheService cache;
  late NetworkChecklistSourceService source;

  PluginEndpoint endpoint() =>
      PluginEndpoint(host: '127.0.0.1', port: server.port);

  /// What the session layer would hold right now.
  Future<PluginSession> sessionNow() async {
    final info = (await companion.getAircraft(endpoint())).valueOrNull!;
    return PluginSession(host: '127.0.0.1', port: server.port, aircraft: info);
  }

  setUp(() async {
    server = await FakeCompanionPluginServer.start();
    companion = HttpCompanionPluginService(
      client: http.Client(),
      timeout: const Duration(milliseconds: 500),
    );
    dir = Directory.systemTemp.createTempSync('network_source_test');
    cache = FileChecklistCacheService(dir);
    sessions = FakePluginSessionSource();
    source = NetworkChecklistSourceService(
      sessions: sessions,
      companion: companion,
      cache: cache,
      sessionWait: const Duration(milliseconds: 150),
    );
    sessions.onReload = () async {
      final info = await companion.getAircraft(endpoint());
      return switch (info) {
        Ok(:final value) => Ok(
          PluginSession(host: '127.0.0.1', port: server.port, aircraft: value),
        ),
        Error(:final error) => Error(error),
      };
    };
  });

  tearDown(() async {
    await sessions.dispose();
    companion.dispose();
    await server.close();
    dir.deleteSync(recursive: true);
  });

  Future<Result<RawChecklistDocument>> loadWithSession() async {
    sessions.current = await sessionNow();
    return source.load();
  }

  int checklistRequests() => server.requests['/v1/checklist'] ?? 0;

  group('happy path', () {
    test('first load fetches and returns text', () async {
      final result = await loadWithSession();
      expect(result.valueOrNull!.text, utf8.decode(server.checklistBytes!));
      expect(checklistRequests(), 1);
    });

    test('name is the description', () async {
      final doc = (await loadWithSession()).valueOrNull!;
      expect(doc.name, 'Cessna Skyhawk 172SP');
    });

    test('name falls back to the ICAO, then to a fixed word', () async {
      server.loadAircraft(
        icao: 'B738',
        description: '',
        aircraftPath: 'Aircraft/B738/b738.acf',
        checklistBytes: utf8.encode('sw_checklist:A\n'),
      );
      expect((await loadWithSession()).valueOrNull!.name, 'B738');
      server.loadAircraft(
        icao: '',
        description: '',
        aircraftPath: 'Aircraft/X/x.acf',
        checklistBytes: utf8.encode('sw_checklist:A\n'),
      );
      expect((await loadWithSession()).valueOrNull!.name, 'checklist');
    });

    test('non-utf8 bytes decode via latin-1', () async {
      server.loadAircraft(
        icao: 'X',
        description: 'x',
        aircraftPath: 'Aircraft/X/x.acf',
        checklistBytes: Uint8List.fromList([
          ...latin1.encode('sw_item:caf'),
          0xe9,
          0x0a,
        ]),
      );
      expect((await loadWithSession()).valueOrNull!.text, contains('café'));
    });

    test('aircraft without checklist gives NoChecklistForAircraft', () async {
      server.useScenario('no_checklist');
      expect(
        (await loadWithSession()).errorOrNull,
        isA<NoChecklistForAircraft>(),
      );
      expect(checklistRequests(), 0);
    });

    test('no session gives PluginNotDetected', () async {
      expect((await source.load()).errorOrNull, isA<PluginNotDetected>());
    });

    test('never returns SourceCancelled', () async {
      final results = <Result<RawChecklistDocument>>[
        await source.load(),
        await loadWithSession(),
      ];
      server.useScenario('no_checklist');
      results.add(await loadWithSession());
      for (final r in results) {
        expect(r.errorOrNull, isNot(isA<SourceCancelled>()));
      }
    });

    test('never calls getAircraft', () async {
      sessions.current = await sessionNow();
      final before = server.requests['/v1/aircraft'] ?? 0;
      await source.load();
      expect(server.requests['/v1/aircraft'] ?? 0, before);
    });
  });

  group('cache decision', () {
    test('second load makes no checklist request', () async {
      await loadWithSession();
      expect(checklistRequests(), 1);
      final again = await source.load();
      expect(again.isOk, isTrue);
      expect(checklistRequests(), 1);
      expect(again.valueOrNull!.text, utf8.decode(server.checklistBytes!));
    });

    test('cache is written after a fetch', () async {
      await loadWithSession();
      final entry = await cache.read(server.aircraftPath);
      expect(entry, isNotNull);
      expect(entry!.bytes, server.checklistBytes);
      expect(entry.mtime, server.mtime);
      expect(entry.size, server.checklistBytes!.length);
      expect(entry.checklistPath, server.checklistPath);
    });

    test('edited file is refetched', () async {
      await loadWithSession();
      server.editChecklist('sw_checklist:Edited\nsw_item:a|b\n');
      final result = await loadWithSession();
      expect(result.valueOrNull!.text, contains('Edited'));
      expect(checklistRequests(), 2);
      expect((await cache.read(server.aircraftPath))!.mtime, server.mtime);
    });

    test('older mtime (restored backup) is refetched', () async {
      await loadWithSession();
      server.restoreOlder();
      await loadWithSession();
      expect(checklistRequests(), 2);
    });

    test('different size with same mtime is refetched', () async {
      await loadWithSession();
      final entry = (await cache.read(server.aircraftPath))!;
      await cache.write(
        server.aircraftPath,
        CachedChecklist(
          bytes: entry.bytes,
          checklistPath: entry.checklistPath,
          mtime: entry.mtime,
          size: entry.size + 1,
        ),
      );
      await loadWithSession();
      expect(checklistRequests(), 2);
    });

    test('304 keeps cache and returns cached text', () async {
      await loadWithSession();
      final entry = (await cache.read(server.aircraftPath))!;
      final info = (await sessionNow()).aircraft;
      // The session claims another size, so the cache check misses; the
      // server still has the cached file, so the conditional request is a 304.
      sessions.current = PluginSession(
        host: '127.0.0.1',
        port: server.port,
        aircraft: RawAircraftInfo(
          protocolVersion: info.protocolVersion,
          generation: info.generation,
          icao: info.icao,
          description: info.description,
          aircraftPath: info.aircraftPath,
          checklistPath: info.checklistPath,
          checklistModified: info.checklistModified,
          checklistSize: info.checklistSize! + 1,
        ),
      );
      final before = checklistRequests();
      final result = await source.load();
      expect(result.valueOrNull!.text, utf8.decode(entry.bytes));
      expect(checklistRequests(), before + 1);
      expect(await cache.read(server.aircraftPath), entry);
    });

    test('corrupt entry is refetched', () async {
      await loadWithSession();
      final file = File(
        '${dir.path}/${cache.fileNameFor(server.aircraftPath)}',
      );
      await file.writeAsBytes([0xff, 0x00, 0x13]);
      final result = await loadWithSession();
      expect(result.isOk, isTrue);
      expect(checklistRequests(), 2);
      expect(await cache.read(server.aircraftPath), isNotNull);
    });

    test('unreachable plugin fails even with a cache entry', () async {
      await loadWithSession();
      server.editChecklist('sw_checklist:Edited\n');
      sessions.current = await sessionNow();
      await server.close();
      expect((await source.load()).errorOrNull, isA<PluginUnreachable>());
      sessions.current = null;
      expect((await source.load()).errorOrNull, isA<PluginNotDetected>());
    });

    test("aircraft change uses the other aircraft's entry", () async {
      await loadWithSession();
      final first = server.aircraftPath;
      server.loadAircraft(
        icao: 'B738',
        description: 'Boeing',
        aircraftPath: 'Aircraft/B738/b738.acf',
        checklistBytes: utf8.encode('sw_checklist:Boeing\n'),
      );
      final second = (await loadWithSession()).valueOrNull!;
      expect(second.text, contains('Boeing'));
      expect(checklistRequests(), 2);
      expect(await cache.read(first), isNotNull);
      expect(await cache.read('Aircraft/B738/b738.acf'), isNotNull);
      // Back to the first aircraft's data in the cache: no request.
      server.loadAircraft(
        icao: 'C172',
        description: 'Cessna Skyhawk 172SP',
        aircraftPath: first,
        checklistBytes: (await cache.read(first))!.bytes,
      );
      server.mtime = (await cache.read(first))!.mtime;
      final third = await loadWithSession();
      expect(third.isOk, isTrue);
      expect(checklistRequests(), 2);
    });
  });

  group('race rule', () {
    test('aircraft changing between session and fetch retries with the new session and succeeds', () async {
      server.changeAircraftBetweenRequests();
      sessions.current = await sessionNow(); // the change happens after this
      sessions.onReload = null;
      Future<void>.delayed(const Duration(milliseconds: 50), () async {
        sessions.emit(await sessionNow());
      });
      final result = await source.load();
      expect(result.valueOrNull!.text, contains('Other'));
      expect(sessions.reloads, 0);
      expect(
        (await cache.read(
          'Aircraft/Laminar Research/Boeing B737-800/b738.acf',
        )),
        isNotNull,
      );
    });

    test('file edited between requests retries and succeeds', () async {
      sessions.current = await sessionNow();
      server.editChecklist('sw_checklist:Edited\n');
      final result = await source.load();
      expect(result.valueOrNull!.text, contains('Edited'));
      expect(sessions.reloads, 1);
    });

    /// Every session the source gets is outdated by an edit right after.
    void alwaysChanging() {
      sessions.onReload = () async {
        final fresh = await sessionNow();
        server.editChecklist('sw_checklist:E${server.mtime}\n');
        return Ok(fresh);
      };
    }

    test('4 consecutive changes give ProtocolError', () async {
      sessions.current = await sessionNow();
      server.editChecklist('sw_checklist:First\n');
      alwaysChanging();
      final result = await source.load();
      expect(result.errorOrNull, isA<ProtocolError>());
      expect(sessions.reloads, 2);
    });

    test('mismatched response is not written to the cache', () async {
      sessions.current = await sessionNow();
      server.editChecklist('sw_checklist:First\n');
      alwaysChanging();
      await source.load();
      expect(await cache.read(server.aircraftPath), isNull);
    });

    test(
      'waits for the next session rather than fetching the aircraft itself',
      () async {
        sessions.current = await sessionNow();
        final before = server.requests['/v1/aircraft'] ?? 0;
        server.editChecklist('sw_checklist:Edited\n');
        Future<void>.delayed(const Duration(milliseconds: 40), () async {
          sessions.emit(await sessionNow());
        });
        final fresh = server.requests['/v1/aircraft'] ?? 0;
        final result = await source.load();
        expect(result.isOk, isTrue);
        // Only the test's own getAircraft call hit the server.
        expect((server.requests['/v1/aircraft'] ?? 0) - fresh, 1);
        expect(before, 1);
      },
    );
  });

  group('error mapping', () {
    test('connection refused gives PluginUnreachable', () async {
      sessions.current = await sessionNow();
      await server.close();
      expect((await source.load()).errorOrNull, isA<PluginUnreachable>());
    });

    test('timeout gives PluginUnreachable', () async {
      sessions.current = await sessionNow();
      server.delayNext(const Duration(seconds: 2));
      expect((await source.load()).errorOrNull, isA<PluginUnreachable>());
    });

    test('a 200 without validators gives ProtocolError', () async {
      sessions.current = await sessionNow();
      final stubbed = NetworkChecklistSourceService(
        sessions: sessions,
        companion: _FailingCompanion(
          ProtocolError('the checklist answer lacks ETag'),
        ),
        cache: cache,
      );
      expect((await stubbed.load()).errorOrNull, isA<ProtocolError>());
    });

    test('version mismatch carries both versions', () async {
      sessions.current = await sessionNow();
      final stubbed = NetworkChecklistSourceService(
        sessions: sessions,
        companion: _FailingCompanion(
          PluginVersionMismatch(found: 2, required: 1),
        ),
        cache: cache,
      );
      final error =
          (await stubbed.load()).errorOrNull! as PluginVersionMismatch;
      expect([error.found, error.required], [2, 1]);
    });

    test('no message contains http:// or an aircraft path', () async {
      final errors = <AppException>[];
      errors.add((await source.load()).errorOrNull!);
      sessions.current = await sessionNow();
      server.delayNext(const Duration(seconds: 2));
      errors.add((await source.load()).errorOrNull!);
      server.useScenario('oversize');
      sessions.current = await sessionNow();
      errors.add((await source.load()).errorOrNull!);
      server.useScenario('no_checklist');
      errors.add((await loadWithSession()).errorOrNull!);
      await server.close();
      sessions.current = null;
      errors.add((await source.load()).errorOrNull!);
      for (final e in errors) {
        expect(e.message, isNot(contains('http://')), reason: e.toString());
        expect(e.message, isNot(contains('Aircraft/')), reason: e.toString());
        expect(e.message, isNot(contains('127.0.0.1')), reason: e.toString());
      }
    });
  });
}

class _FailingCompanion implements CompanionPluginService {
  _FailingCompanion(this.error);
  final AppException error;

  @override
  Future<Result<RawChecklistFetch>> getChecklist(
    PluginEndpoint endpoint, {
    String? ifNoneMatch,
  }) async => Error(error);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
