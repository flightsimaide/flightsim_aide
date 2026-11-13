import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_local.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/domain/models/flight_sim/discovered_sim.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_cubit.dart';
import 'package:flightsim_aide/ui/connection/widgets/connection_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/services/manual_clock.dart';

// Cancel while waiting for the aircraft: a question, then the IP dialog

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

  Future<void> pumpWaiting(WidgetTester tester) async {
    sim.setStatus(const ConnectionConnecting());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: const SingleChildScrollView(child: ConnectionPanel()),
          ),
        ),
      ),
    );
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.runAsync(pumpEventQueue);
    // Not pumpAndSettle: the hourglass behind the dialogs never stops turning.
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Taps a button of the dialog on top; the panel behind has a Cancel too.
  Future<void> tapInDialog(WidgetTester tester, String text) async {
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.text(text),
      ),
    );
    await tester.runAsync(pumpEventQueue);
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> openIpDialog(WidgetTester tester) async {
    await pumpWaiting(tester);
    await tapText(tester, 'Cancel');
    await tapInDialog(tester, 'No');
  }

  const question =
      'FlightSim Aide is waiting for the aircraft to load. '
      'Continue waiting on aircraft.';

  testWidgets('Cancel asks whether to keep waiting, with no icon and no red', (
    tester,
  ) async {
    await pumpWaiting(tester);
    await tapText(tester, 'Cancel');
    final text = find.text(question);
    expect(text, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
    expect(tester.widget<Text>(text).style?.color, isNull);
    expect(sim.cancels, 0, reason: 'nothing stopped yet');
  });

  testWidgets('Yes closes the dialog and keeps waiting', (tester) async {
    await pumpWaiting(tester);
    await tapText(tester, 'Cancel');
    await tapInDialog(tester, 'Yes');
    expect(find.text(question), findsNothing);
    expect(sim.cancels, 0);
    expect(find.text('Waiting for aircraft to load'), findsOneWidget);
  });

  testWidgets('No stops connecting and opens the IP address dialog', (
    tester,
  ) async {
    await openIpDialog(tester);
    expect(find.text(question), findsNothing);
    expect(sim.cancels, 1);
    expect(find.text('X-Plane IP address'), findsOneWidget);
    expect(find.text('Connect to X-Plane'), findsNothing);
  });

  testWidgets(
    'the IP dialog names the computer and address X-Plane was found at',
    (tester) async {
      sim.currentTarget = const DiscoveredSim(
        host: '192.168.1.12',
        name: 'MacBook',
      );
      await openIpDialog(tester);
      expect(
        find.text('X-Plane connected to MacBook on IP 192.168.1.12'),
        findsOneWidget,
      );
      expect(find.text('X-Plane IP address'), findsNothing);
    },
  );

  testWidgets('without a computer name the title shows the IP address', (
    tester,
  ) async {
    sim.currentTarget = const DiscoveredSim(host: '192.168.1.12');
    await openIpDialog(tester);
    expect(find.text('X-Plane on IP 192.168.1.12'), findsOneWidget);
  });

  testWidgets('Cancel in the IP dialog goes back to waiting', (tester) async {
    await openIpDialog(tester);
    await tapInDialog(tester, 'Cancel');
    expect(find.text('X-Plane IP address'), findsNothing);
    expect(sim.resumeCalls, 1);
  });

  testWidgets('Try in the IP dialog connects and does not resume', (
    tester,
  ) async {
    await openIpDialog(tester);
    await tester.enterText(find.byType(TextField), '10.0.0.5');
    await tester.pump();
    await tapText(tester, 'Try');
    expect(sim.manualIp, '10.0.0.5');
    expect(sim.resumeCalls, 0);
    expect(find.text('X-Plane IP address'), findsNothing);
  });

  testWidgets('Erase saved IP in the IP dialog does not resume', (
    tester,
  ) async {
    await settings.saveManualIp('10.0.0.5');
    await openIpDialog(tester);
    await tapText(tester, 'Erase saved IP');
    expect(sim.manualIp, isNull);
    expect(sim.resumeCalls, 0);
    expect(find.text('X-Plane IP address'), findsNothing);
  });
}
