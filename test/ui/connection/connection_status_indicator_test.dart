import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_local.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/domain/models/flight_sim/discovered_sim.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_cubit.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_state.dart';
import 'package:flightsim_aide/ui/connection/widgets/connection_status_indicator.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flightsim_aide/ui/core/themes/status_colors.dart';
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
  group('indicatorFor', () {
    test('every state maps to one of the four words', () {
      expect(indicatorFor(const LinkNoNetwork()), IndicatorKind.noNetwork);
      expect(indicatorFor(const LinkSearching()), IndicatorKind.connecting);
      expect(indicatorFor(const LinkConnecting()), IndicatorKind.connecting);
      expect(
        indicatorFor(const LinkSimUnreachable()),
        IndicatorKind.connecting,
        reason: 'a lost connection is retried, so it reads as connecting',
      );
      expect(
        indicatorFor(const LinkConnected(_cessna)),
        IndicatorKind.connected,
      );
      expect(
        indicatorFor(const LinkNoChecklist(_cessna)),
        IndicatorKind.connected,
      );
      expect(
        indicatorFor(const LinkLocalNetworkDenied()),
        IndicatorKind.notConnected,
      );
      expect(
        indicatorFor(const LinkVersionMismatch(found: 2, required: 1)),
        IndicatorKind.notConnected,
      );
    });
  });

  group('ConnectionStatusIndicator', () {
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

    Future<void> pump(WidgetTester tester, {bool withCubit = true}) async {
      final bar = Scaffold(
        appBar: AppBar(
          title: const Text('Page'),
          actions: const [ConnectionStatusIndicator()],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: withCubit ? BlocProvider.value(value: cubit, child: bar) : bar,
        ),
      );
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(pumpEventQueue);
      await tester.pump();
    }

    Color iconColour(WidgetTester tester, IconData icon) =>
        tester.widget<Icon>(find.byIcon(icon)).color!;

    testWidgets('is empty without a connection cubit', (tester) async {
      await pump(tester, withCubit: false);
      expect(find.byKey(const Key('connection-indicator')), findsNothing);
    });

    testWidgets('connecting: amber warning icon, no computer line yet', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Connecting'), findsOneWidget);
      expect(find.byIcon(Icons.warning), findsOneWidget);
      expect(iconColour(tester, Icons.warning), StatusColors.dark.caution);
      expect(find.byKey(const Key('connection-indicator-where')), findsNothing);
    });

    testWidgets('no network: red error icon', (tester) async {
      await pump(tester);
      sim.setStatus(const ConnectionNoNetwork());
      await settle(tester);
      expect(find.text('No network'), findsOneWidget);
      expect(iconColour(tester, Icons.error), StatusColors.dark.error);
    });

    testWidgets('connected: green check, computer and simulator above', (
      tester,
    ) async {
      sim.setAircraft(_cessna);
      sim.currentTarget = const DiscoveredSim(
        host: '192.168.1.10',
        name: 'WIN',
      );
      sim.setStatus(const ConnectionConnected());
      await pump(tester);
      await settle(tester);
      expect(find.text('Connected'), findsOneWidget);
      expect(iconColour(tester, Icons.check_circle), StatusColors.dark.success);
      expect(find.text('WIN · X-Plane'), findsOneWidget);
      // The computer line is above the status.
      expect(
        tester.getTopLeft(find.text('WIN · X-Plane')).dy,
        lessThan(tester.getTopLeft(find.text('Connected')).dy),
      );
    });

    testWidgets('a lost connection reads Connecting and keeps the computer', (
      tester,
    ) async {
      sim.currentTarget = const DiscoveredSim(
        host: '192.168.1.10',
        name: 'WIN',
      );
      sim.setStatus(const ConnectionSimUnreachable());
      await pump(tester);
      await settle(tester);
      expect(find.text('Connecting'), findsOneWidget);
      expect(find.text('WIN · X-Plane'), findsOneWidget);
    });

    testWidgets('tapping it does nothing', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('connection-indicator')));
      await tester.pump();
      expect(find.text('Page'), findsOneWidget);
    });
  });
}
