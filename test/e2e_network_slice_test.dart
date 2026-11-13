import 'dart:io';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository_impl.dart';
import 'package:flightsim_aide/data/services/checklist/network_checklist_source_service.dart';
import 'package:flightsim_aide/data/services/flight_sim/companion_plugin_service.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/plugin_endpoint.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/plugin_session.dart';
import 'package:flightsim_aide/data/services/local/checklist_cache_service.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../testing/fakes/plugin/fake_companion_plugin_server.dart';
import '../testing/fakes/services/fake_plugin_session_source.dart';

// AC-12: checklist equals what the parser produces from the real file

/// The network path without X-Plane or a phone: the real repository and parser read an
/// aircraft file through the network source, the cache and the HTTP
/// service, from the Dart fake plugin. The repository, parser and domain are
/// the original viewer code, unchanged.
void main() {
  test(
    'an aircraft file reaches the repository through the network source',
    () async {
      final server = await FakeCompanionPluginServer.start();
      addTearDown(server.close);
      final companion = HttpCompanionPluginService(client: http.Client());
      addTearDown(companion.dispose);
      final dir = Directory.systemTemp.createTempSync('slice_test');
      addTearDown(() => dir.deleteSync(recursive: true));

      server.loadAircraft(
        icao: 'TEST',
        description: 'Example twin turboprop',
        aircraftPath: 'Aircraft/Example/example.acf',
        checklistBytes: File('testing/fixtures/lookalike_aircraft.txt')
            .readAsBytesSync(),
      );
      final info = (await companion.getAircraft(
        PluginEndpoint(host: '127.0.0.1', port: server.port),
      )).valueOrNull!;
      final sessions = FakePluginSessionSource(
        PluginSession(host: '127.0.0.1', port: server.port, aircraft: info),
      );
      addTearDown(sessions.dispose);

      final repository = ChecklistRepositoryImpl(
        source: NetworkChecklistSourceService(
          sessions: sessions,
          companion: companion,
          cache: FileChecklistCacheService(dir),
        ),
        parser: const AircraftWorkflowParser(),
      );

      final first = await repository.load();
      expect(first, isA<Ok<ChecklistDocument>>());
      final document = (first as Ok<ChecklistDocument>).value;
      expect(document.checklists, hasLength(7));
      expect(document.sourceName, 'Example twin turboprop');
      expect(server.requests['/v1/checklist'], 1);

      final second = await repository.load();
      expect((second as Ok<ChecklistDocument>).value.checklists, hasLength(7));
      expect(
        server.requests['/v1/checklist'],
        1,
        reason: 'served from the cache',
      );
      expect(
        server.requests['/v1/aircraft'],
        1,
        reason: 'the source never asks',
      );
    },
  );
}
