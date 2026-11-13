import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository_impl.dart';
import 'package:flightsim_aide/data/services/checklist/network_checklist_source_service.dart';
import 'package:flightsim_aide/data/services/flight_sim/companion_plugin_service.dart';
import 'package:flightsim_aide/data/services/flight_sim/model/plugin_endpoint.dart';
import 'package:flightsim_aide/data/services/flight_sim/plugin_session_service.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../testing/fakes/plugin/fake_companion_plugin_server.dart';
import '../testing/fakes/services/fake_flight_sim_service.dart';
import '../testing/fakes/services/in_memory_checklist_cache_service.dart';

// AC-13: Reload picks up an edit made while connected

const _original =
    'sw_checklist:Before start:Before start checklist\n'
    'sw_item:Parking brake|SET\n'
    'sw_item:Battery|ON\n';

const _edited =
    'sw_checklist:Before start:Before start checklist\n'
    'sw_item:Parking brake|SET\n'
    'sw_item:Battery|ON\n'
    'sw_item:Avionics|OFF\n';

/// The real session service, network source, cache and repository against the
/// Dart fake plugin: an edit on the "disk" followed by `reload()` must show up
/// in the next `load()`.
void main() {
  test('an edit while connected is loaded after the session reload', () async {
    final server = await FakeCompanionPluginServer.start();
    addTearDown(server.close);
    final companion = HttpCompanionPluginService(client: http.Client());
    addTearDown(companion.dispose);
    server.loadAircraft(
      icao: 'C172',
      description: 'Cessna Skyhawk 172SP',
      aircraftPath: 'Aircraft/Test/c172.acf',
      checklistBytes: _original.codeUnits,
    );

    final flightSim = FakeFlightSimService()
      ..pluginEndpoint = PluginEndpoint(host: '127.0.0.1', port: server.port);
    final sessions = PluginSessionService(
      flightSim: flightSim,
      companion: companion,
    );
    addTearDown(sessions.dispose);
    final first = await sessions.reload();
    expect(first, isA<Ok<Object?>>());

    final repository = ChecklistRepositoryImpl(
      source: NetworkChecklistSourceService(
        sessions: sessions,
        companion: companion,
        cache: InMemoryChecklistCacheService(),
      ),
      parser: const AircraftWorkflowParser(),
    );
    final before = (await repository.load() as Ok<ChecklistDocument>).value;
    expect(before.checklists.single.items, hasLength(2));

    server.editChecklist(_edited);
    final reloaded = await sessions.reload();
    expect(reloaded, isA<Ok<Object?>>());
    expect(sessions.current!.aircraft.checklistSize, _edited.length);

    final after = (await repository.load() as Ok<ChecklistDocument>).value;
    expect(after.checklists.single.items, hasLength(3));
  });
}
