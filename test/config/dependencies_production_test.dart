import 'package:flightsim_aide/config/dependencies_production.dart';
import 'package:flightsim_aide/config/network_link.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository.dart';
import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_remote.dart';
import 'package:flightsim_aide/data/repositories/settings/settings_repository.dart';
import 'package:flightsim_aide/data/services/checklist/network_checklist_source_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds [providers] and captures a [BuildContext] below them.
Future<BuildContext> resolve(
  WidgetTester tester,
  List<RepositoryProvider<dynamic>> providers,
) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: providers,
      child: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('network source', () {
    test('network wires NetworkChecklistSourceService', () async {
      final link = productionLink(simIp: '10.0.0.5');
      addTearDown(link.dispose);
      expect(link.source, isA<NetworkChecklistSourceService>());
      expect(link.simIp, '10.0.0.5');
    });

    testWidgets('network providers resolve without starting the link', (
      tester,
    ) async {
      final context = await resolve(
        tester,
        productionProviders(startLink: false),
      );
      expect(context.read<ChecklistRepository>(), isNotNull);
      final link = context.read<NetworkLink>();
      expect(link.flightSim.isStreamConnected, isFalse);
      expect(link.flightSim.pluginEndpoint, isNull);
    });
  });

  group('flight sim repositories', () {
    testWidgets('network provides FlightSimRepository and SettingsRepository', (
      tester,
    ) async {
      final context = await resolve(
        tester,
        productionProviders(simIp: '', startLink: false),
      );
      expect(
        context.read<FlightSimRepository>(),
        isA<FlightSimRepositoryRemote>(),
      );
      expect(context.read<SettingsRepository>(), isNotNull);
    });

    testWidgets('network provides a progress repository', (tester) async {
      final context = await resolve(
        tester,
        productionProviders(simIp: '', startLink: false),
      );
      expect(
        context.read<ChecklistProgressRepository>(),
        isA<ChecklistProgressRepositoryImpl>(),
      );
    });
  });
}
