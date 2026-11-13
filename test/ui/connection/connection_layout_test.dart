import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_local.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/domain/models/flight_sim/discovered_sim.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_cubit.dart';
import 'package:flightsim_aide/ui/connection/widgets/connection_panel.dart';
import 'package:flightsim_aide/ui/connection/widgets/manual_ip_dialog.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/services/manual_clock.dart';

const _cessna = AircraftIdentity(
  icao: 'C172',
  description: 'Cessna 172 Skyhawk with a rather long description',
  aircraftPath: 'a.acf',
  checklistPath: 'clist.txt',
);

void main() {
  final scenarios = <String, void Function(FlightSimRepositoryLocal)>{
    'searching timed out': (_) {},
    'connected': (s) {
      s.setAircraft(_cessna);
      s.setStatus(const ConnectionConnected());
    },
    'no network': (s) => s.setStatus(const ConnectionNoNetwork()),
    'sim unreachable': (s) => s.setStatus(
      ConnectionSimUnreachable(lastSeen: DateTime(2026, 10, 25, 14, 32)),
    ),
    'version mismatch': (s) => s.setStatus(
      const ConnectionPluginVersionMismatch(found: 2, required: 1),
    ),
    'two sims': (s) => s.setSims(const [
      DiscoveredSim(host: '192.168.2.200', name: 'Flight deck computer'),
      DiscoveredSim(host: '192.168.2.201'),
    ]),
  };

  for (final dark in [false, true]) {
    for (final entry in scenarios.entries) {
      testWidgets(
        '${entry.key} at 200% text on a narrow ${dark ? 'dark' : 'light'} '
        'screen does not overflow',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final sim = FlightSimRepositoryLocal();
          entry.value(sim);
          final clock = ManualClock();
          final cubit = ConnectionCubit(
            flightSim: sim,
            settings: FakeSettingsRepository(),
            clock: clock,
          );
          if (entry.key == 'searching timed out') {
            clock.advance(const Duration(seconds: 10));
          }
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: BlocProvider.value(
                  value: cubit,
                  child: const SingleChildScrollView(child: ConnectionPanel()),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          for (final button in tester.widgetList<ButtonStyleButton>(
            find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )) {
            expect(button.onPressed, isNotNull);
          }
          for (final element in find.byType(TextButton).evaluate()) {
            final size = tester.getSize(find.byWidget(element.widget));
            expect(size.height, greaterThanOrEqualTo(48));
          }
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            await cubit.close();
            await sim.dispose();
          });
        },
      );
    }
  }

  testWidgets('manual IP dialog at 200% text does not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(body: ManualIpDialog(initial: '192.168.2.200')),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
