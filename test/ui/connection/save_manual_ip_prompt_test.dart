import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_local.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_cubit.dart';
import 'package:flightsim_aide/ui/connection/widgets/save_manual_ip_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/services/manual_clock.dart';

// Only a typed address that connected is offered for saving

void main() {
  late FlightSimRepositoryLocal sim;
  late FakeSettingsRepository settings;
  late ConnectionCubit cubit;

  setUp(() {
    sim = FlightSimRepositoryLocal();
    settings = FakeSettingsRepository();
    cubit = ConnectionCubit(
      flightSim: sim,
      settings: settings,
      clock: ManualClock(),
    );
  });
  tearDown(() async {
    await cubit.close();
    await sim.dispose();
  });

  Future<void> pumpPrompt(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const SaveManualIpPrompt(child: Scaffold()),
        ),
      ),
    );
    sim.setManualIpWorked('10.0.0.7');
    await tester.runAsync(pumpEventQueue);
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('Save keeps the address that worked', (tester) async {
    await pumpPrompt(tester);
    expect(find.text('Save IP address?'), findsOneWidget);
    expect(find.textContaining('10.0.0.7'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.runAsync(pumpEventQueue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(await settings.manualIp(), '10.0.0.7');
  });

  testWidgets('No does not save it', (tester) async {
    await pumpPrompt(tester);
    await tester.tap(find.text('No'));
    await tester.runAsync(pumpEventQueue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(await settings.manualIp(), isNull);
    expect(find.text('Save IP address?'), findsNothing);
  });
}
