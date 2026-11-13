import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_local.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_cubit.dart';
import 'package:flightsim_aide/ui/connection/widgets/connection_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/services/manual_clock.dart';

const _cessna = AircraftIdentity(
  icao: 'C172',
  description: 'Cessna 172',
  aircraftPath: 'a.acf',
  checklistPath: 'clist.txt',
);

void main() {
  late FlightSimRepositoryLocal sim;
  late ConnectionCubit cubit;

  setUp(() {
    sim = FlightSimRepositoryLocal();
    cubit = ConnectionCubit(
      flightSim: sim,
      settings: FakeSettingsRepository(),
      clock: ManualClock(),
    );
  });

  tearDown(() async {
    await cubit.close();
    await sim.dispose();
  });

  Future<void> pumpPanel(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider.value(
          value: cubit,
          child: const SingleChildScrollView(child: ConnectionPanel()),
        ),
      ),
    ),
  );

  testWidgets('a finished reload shows "Checklist reloaded", then it goes', (
    tester,
  ) async {
    sim.setAircraft(_cessna);
    sim.setStatus(const ConnectionConnected());
    await pumpPanel(tester);
    await tester.pump();
    expect(find.text('Checklist reloaded'), findsNothing);

    await tester.tap(find.text('Reload'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Checklist reloaded'), findsOneWidget);

    // The 3 s timer starts when the entrance animation ends.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Checklist reloaded'), findsNothing);
  });
}
