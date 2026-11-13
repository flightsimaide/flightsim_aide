import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_local.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/domain/models/flight_sim/discovered_sim.dart';
import 'package:flightsim_aide/domain/models/flight_sim/simulator.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_cubit.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_state.dart';
import 'package:flightsim_aide/ui/connection/cubit/known_address.dart';
import 'package:flightsim_aide/ui/connection/widgets/connection_messages.dart';
import 'package:flightsim_aide/ui/connection/widgets/connection_panel.dart';
import 'package:flightsim_aide/ui/connection/widgets/manual_ip_dialog.dart';
import 'package:flightsim_aide/ui/connection/widgets/sim_chooser.dart';
import 'package:flightsim_aide/ui/connection/widgets/spinning_hourglass.dart';
import 'package:flightsim_aide/ui/core/themes/status_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/services/manual_clock.dart';

// AC-8: manual IP dialog rejects an invalid address and saves a valid one

const _cessna = AircraftIdentity(
  icao: 'C172',
  description: 'Cessna 172',
  aircraftPath: 'a.acf',
  checklistPath: 'clist.txt',
);

void main() {
  late FlightSimRepositoryLocal sim;
  late FakeSettingsRepository settings;
  late ConnectionCubit cubit;
  late ManualClock clock;

  setUp(() {
    sim = FlightSimRepositoryLocal();
    settings = FakeSettingsRepository();
    clock = ManualClock();
    cubit = ConnectionCubit(flightSim: sim, settings: settings, clock: clock);
  });
  tearDown(() async {
    await cubit.close();
    await sim.dispose();
  });

  /// Lets the stream events reach the cubit (they run outside fake async),
  /// then draws the frame.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
  }

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

  group('ConnectionPanel', () {
    testWidgets('each state shows its text', (tester) async {
      await pumpPanel(tester);
      expect(find.text('Waiting for connection'), findsOneWidget);
      final script = <(ConnectionStatus, String)>[
        (const ConnectionConnecting(), 'Waiting for aircraft to load'),
        (const ConnectionNoNetwork(), 'Network is off'),
        (
          const ConnectionSimUnreachable(),
          'X-Plane is not responding. Retrying...',
        ),
        (
          const ConnectionPluginVersionMismatch(found: 2, required: 1),
          'Update the plugin to continue.',
        ),
      ];
      for (final (status, text) in script) {
        sim.setStatus(status);
        await settle(tester);
        expect(find.text(text), findsOneWidget, reason: text);
      }
    });

    testWidgets('connected shows icao and description', (tester) async {
      sim.setAircraft(_cessna);
      sim.setStatus(const ConnectionConnected());
      await pumpPanel(tester);
      await tester.pump();
      expect(find.text('Connected to X-Plane'), findsOneWidget);
      expect(find.text('Cessna 172 (C172)'), findsOneWidget);
    });

    testWidgets('connected names the computer and lists the others', (
      tester,
    ) async {
      sim.setAircraft(_cessna);
      sim.currentTarget = const DiscoveredSim(
        host: '192.168.1.10',
        name: 'WIN',
        simulator: Simulator.xplane,
      );
      sim.setSims(const [
        DiscoveredSim(host: '192.168.1.10', name: 'WIN'),
        DiscoveredSim(host: '192.168.1.117', name: 'MAC', os: HostOs.macos),
      ]);
      sim.setStatus(const ConnectionConnected());
      await pumpPanel(tester);
      await tester.pump();
      expect(find.text('Connected to X-Plane on WIN'), findsOneWidget);
      expect(find.byKey(const Key('other-computers')), findsOneWidget);
      expect(find.text('MAC'), findsOneWidget);
      // A bordered choice with an empty circle in front.
      expect(
        find.descendant(
          of: find.byKey(const Key('other-computers')),
          matching: find.byIcon(Icons.radio_button_unchecked),
        ),
        findsOneWidget,
      );
      expect(find.text('WIN'), findsNothing, reason: 'only in the title');
    });

    testWidgets('no other computer, no box', (tester) async {
      sim.setAircraft(_cessna);
      sim.currentTarget = const DiscoveredSim(
        host: '192.168.1.10',
        name: 'WIN',
      );
      sim.setSims(const [DiscoveredSim(host: '192.168.1.10', name: 'WIN')]);
      sim.setStatus(const ConnectionConnected());
      await pumpPanel(tester);
      await tester.pump();
      expect(find.byKey(const Key('other-computers')), findsNothing);
    });

    testWidgets('a lost connection lists the other computers, and asks '
        '"were connected"', (tester) async {
      sim.currentTarget = const DiscoveredSim(
        host: '192.168.1.10',
        name: 'WIN',
      );
      sim.setSims(const [DiscoveredSim(host: '192.168.1.117', name: 'MAC')]);
      sim.setStatus(const ConnectionSimUnreachable());
      await pumpPanel(tester);
      await tester.pump();
      expect(find.byKey(const Key('other-computers')), findsOneWidget);
      await tester.tap(find.text('MAC'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('You were connected to X-Plane on WIN'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('switch-from-list-yes')));
      await tester.pumpAndSettle();
      expect(sim.selectedSim?.name, 'MAC');
    });

    testWidgets('tapping another computer asks, and Yes switches', (
      tester,
    ) async {
      sim.setAircraft(_cessna);
      sim.currentTarget = const DiscoveredSim(
        host: '192.168.1.10',
        name: 'WIN',
      );
      sim.setSims(const [
        DiscoveredSim(host: '192.168.1.10', name: 'WIN'),
        DiscoveredSim(host: '192.168.1.117', name: 'MAC'),
      ]);
      sim.setStatus(const ConnectionConnected());
      await pumpPanel(tester);
      await tester.pump();
      await tester.tap(find.text('MAC'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'You are connected to X-Plane on WIN (192.168.1.10). '
          'Do you want to switch to X-Plane on MAC (192.168.1.117)?',
        ),
        findsOneWidget,
      );
      expect(sim.selectedSim, isNull);
      await tester.tap(find.byKey(const Key('switch-from-list-yes')));
      await tester.pumpAndSettle();
      expect(sim.selectedSim?.name, 'MAC');
    });

    testWidgets('No leaves the connection alone', (tester) async {
      sim.setAircraft(_cessna);
      sim.currentTarget = const DiscoveredSim(
        host: '192.168.1.10',
        name: 'WIN',
      );
      sim.setSims(const [
        DiscoveredSim(host: '192.168.1.10', name: 'WIN'),
        DiscoveredSim(host: '192.168.1.117', name: 'MAC'),
      ]);
      sim.setStatus(const ConnectionConnected());
      await pumpPanel(tester);
      await tester.pump();
      await tester.tap(find.text('MAC'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('switch-from-list-no')));
      await tester.pumpAndSettle();
      expect(sim.selectedSim, isNull);
    });

    testWidgets('connected shows a filled check in the success green', (
      tester,
    ) async {
      sim.setAircraft(_cessna);
      sim.setStatus(const ConnectionConnected());
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [StatusColors.light]),
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: const SingleChildScrollView(child: ConnectionPanel()),
            ),
          ),
        ),
      );
      await tester.pump();
      final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
      expect(icon.color, StatusColors.light.success);
    });

    testWidgets('no checklist is a caution: yellow title, filled warning', (
      tester,
    ) async {
      sim.setAircraft(
        const AircraftIdentity(
          icao: 'PA28',
          description: 'Piper Archer',
          aircraftPath: 'b.acf',
        ),
      );
      sim.setStatus(const ConnectionConnected());
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [StatusColors.light]),
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: const SingleChildScrollView(child: ConnectionPanel()),
            ),
          ),
        ),
      );
      await tester.pump();
      final title = tester.widget<Text>(find.text(noChecklistHeadline));
      expect(title.style?.color, StatusColors.light.caution);
      final icon = tester.widget<Icon>(find.byIcon(Icons.warning));
      expect(icon.color, StatusColors.light.caution);
      expect(find.text('X-Plane Piper Archer'), findsOneWidget);
      expect(find.textContaining('then reload'), findsNothing);
      expect(find.text('Reload'), findsOneWidget);
    });

    testWidgets('network off is a warning: red title, filled error icon', (
      tester,
    ) async {
      sim.setStatus(const ConnectionNoNetwork());
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [StatusColors.light]),
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: const SingleChildScrollView(child: ConnectionPanel()),
            ),
          ),
        ),
      );
      await settle(tester);
      final title = tester.widget<Text>(find.text('Network is off'));
      expect(title.style?.color, StatusColors.light.error);
      final icon = tester.widget<Icon>(find.byIcon(Icons.error));
      expect(icon.color, StatusColors.light.error);
      expect(find.byIcon(Icons.wifi_off), findsNothing);
    });

    testWidgets('reload button calls reload', (tester) async {
      sim.setAircraft(_cessna);
      sim.setStatus(const ConnectionConnected());
      await pumpPanel(tester);
      await tester.pump();
      await tester.tap(find.text('Reload'));
      await tester.pump();
      expect(sim.reloads, 1);
    });

    testWidgets('retry button calls retry', (tester) async {
      sim.setStatus(const ConnectionLocalNetworkDenied());
      await pumpPanel(tester);
      await tester.pump();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(sim.retries, 1);
    });

    testWidgets('no text relies on colour alone (semantics label present)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      sim.setStatus(const ConnectionNoNetwork());
      await pumpPanel(tester);
      await tester.pump();
      expect(
        find.bySemanticsLabel(
          RegExp('Network is off.*turn on your device network'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('every state has an icon', (tester) async {
      for (final status in <ConnectionStatus>[
        const ConnectionConnecting(),
        const ConnectionNoNetwork(),
      ]) {
        sim.setStatus(status);
        await pumpPanel(tester);
        await tester.pump();
        // The waiting state shows the hourglass, which is painted, not an Icon.
        expect(
          find.byType(Icon).evaluate().isNotEmpty ||
              find.byType(SpinningHourglass).evaluate().isNotEmpty,
          isTrue,
        );
      }
    });

    testWidgets('a refused address is shown in the panel', (tester) async {
      sim.setStatus(const ConnectionConnecting());
      await pumpPanel(tester);
      await tester.pump();
      await tester.runAsync(() => cubit.setManualIp('abc'));
      await tester.pump();
      expect(find.textContaining('abc'), findsOneWidget);
      expect(find.text('Waiting for aircraft to load'), findsOneWidget);
    });

    testWidgets('enter IP opens the dialog and saving applies it', (
      tester,
    ) async {
      await pumpPanel(tester);
      sim.setStatus(const ConnectionSimUnreachable());
      await settle(tester);
      await tester.tap(find.text('Enter IP address'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '10.0.0.5');
      await tester.pump();
      await tester.tap(find.text('Try'));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(sim.manualIp, '10.0.0.5');
    });

    testWidgets('every state that is not connected has the three buttons', (
      tester,
    ) async {
      await pumpPanel(tester);
      for (final status in <ConnectionStatus>[
        const ConnectionLocalNetworkDenied(),
        const ConnectionPluginVersionMismatch(found: 2, required: 1),
      ]) {
        sim.setStatus(status);
        await settle(tester);
        for (final label in ['Retry', 'Enter IP address', 'Details']) {
          expect(find.text(label), findsOneWidget, reason: '$status $label');
        }
      }
    });

    testWidgets('X-Plane is not responding has Retry and Enter IP address '
        'but no Details', (tester) async {
      await pumpPanel(tester);
      sim.setStatus(const ConnectionSimUnreachable());
      await settle(tester);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Enter IP address'), findsOneWidget);
      expect(find.text('Details'), findsNothing);
    });

    testWidgets('no network shows the message and no buttons', (tester) async {
      sim.setStatus(const ConnectionNoNetwork());
      await pumpPanel(tester);
      await tester.pump();
      expect(find.text('Network is off'), findsOneWidget);
      expect(
        find.textContaining('turn on your device network'),
        findsOneWidget,
      );
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('searching has Enter IP address and Details but no Retry', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.pump();
      expect(find.text('Waiting for connection'), findsOneWidget);
      expect(find.text('Enter IP address'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('an unanswered typed address shows the warning', (
      tester,
    ) async {
      sim.setStatus(const ConnectionSimUnreachable(manualAddress: '10.0.0.7'));
      await pumpPanel(tester);
      await tester.pump();
      expect(find.text('Waiting for connection'), findsOneWidget);
      expect(find.text('Using Manual IP address 10.0.0.7'), findsOneWidget);
      expect(find.byIcon(Icons.error), findsNothing);
      expect(find.text('Enter IP address'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Rediscover IP address'),
        findsOneWidget,
      );
      for (final label in ['Retry', 'Details']) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('Cancel on an unanswered typed address goes back to the '
        'search', (tester) async {
      sim.setStatus(const ConnectionSimUnreachable(manualAddress: '10.0.0.7'));
      await pumpPanel(tester);
      await tester.pump();
      await tester.tap(find.text('Rediscover IP address'));
      await tester.pump();
      expect(sim.manualIp, isNull);
      expect(find.text('Connect to X-Plane'), findsNothing);
    });

    testWidgets('a long wait shows the red note about the Plugin Admin', (
      tester,
    ) async {
      sim.setStatus(const ConnectionConnecting());
      await pumpPanel(tester);
      await tester.pump();
      expect(find.text(waitingHint), findsNothing);
      clock.advance(waitingHintDelay);
      await tester.pump();
      expect(find.text(waitingHint), findsOneWidget);
      expect(find.text('Waiting for aircraft to load'), findsOneWidget);
    });

    testWidgets('connecting shows only Cancel', (tester) async {
      sim.setStatus(const ConnectionConnecting());
      await pumpPanel(tester);
      await tester.pump();
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
      for (final label in ['Retry', 'Enter IP address', 'Details']) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('the buttons stay with a chooser on screen', (tester) async {
      sim.setSims(const [
        DiscoveredSim(host: '10.0.0.5', name: 'A'),
        DiscoveredSim(host: '10.0.0.6', name: 'B'),
      ]);
      await pumpPanel(tester);
      await tester.pump();
      expect(find.byType(SimChooser), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Enter IP address'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
    });

    testWidgets('no activity shows the message, also for one computer', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.pump();
      expect(find.text('Waiting for connection'), findsOneWidget);
      expect(
        find.textContaining('requires a network connection'),
        findsOneWidget,
      );
      sim.setSims(const [DiscoveredSim(host: '10.0.0.5', name: 'A')]);
      await settle(tester);
      expect(
        find.textContaining('requires a network connection'),
        findsOneWidget,
      );
    });

    testWidgets('connected has no Details button', (tester) async {
      sim.setAircraft(_cessna);
      sim.setStatus(const ConnectionConnected());
      await pumpPanel(tester);
      await tester.pump();
      expect(find.text('Details'), findsNothing);
    });

    testWidgets('Details toggles a boxed section below the buttons', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.pump();
      final button = find.widgetWithText(OutlinedButton, 'Details');
      expect(find.text(noActivityDetails), findsNothing);
      await tester.tap(button);
      await tester.pump();
      expect(find.text(noActivityDetails), findsOneWidget);
      // The box carries the title "Details" on its outline.
      expect(find.byType(InputDecorator), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(noActivityDetails)).dy,
        greaterThan(tester.getBottomLeft(button).dy),
      );
      await tester.tap(button);
      await tester.pump();
      expect(find.text(noActivityDetails), findsNothing);
    });

    testWidgets('chooser appears with 2 sims while searching', (tester) async {
      sim.setSims(const [
        DiscoveredSim(host: '10.0.0.5', name: 'A'),
        DiscoveredSim(host: '10.0.0.6', name: 'B'),
      ]);
      await pumpPanel(tester);
      await tester.pump();
      expect(find.byType(SimChooser), findsOneWidget);
    });

    testWidgets(
      'picking a computer has the title Select Connection and no icon',
      (tester) async {
        await pumpPanel(tester);
        await tester.pump();
        expect(find.byType(SpinningHourglass), findsOneWidget);
        sim.setSims(const [
          DiscoveredSim(host: '10.0.0.5', name: 'A'),
          DiscoveredSim(host: '10.0.0.6', name: 'B'),
        ]);
        await settle(tester);
        expect(find.byType(SpinningHourglass), findsNothing);
        expect(find.byIcon(Icons.hourglass_top), findsNothing);
        expect(find.text(selectConnectionHeadline), findsOneWidget);
      },
    );
  });

  group('ManualIpDialog', () {
    Future<void> pumpDialog(
      WidgetTester tester, {
      String? initial,
      List<KnownAddress> known = const [],
      void Function(ManualIpChoice?)? onResult,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final r = await showDialog<ManualIpChoice>(
                  context: context,
                  builder: (_) =>
                      ManualIpDialog(initial: initial, known: known),
                );
                onResult?.call(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    FilledButton saveButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Try'));

    testWidgets('one known address is described above the box', (tester) async {
      await pumpDialog(
        tester,
        known: const [
          KnownAddress(
            address: '192.168.1.117',
            description: 'MAC, macOS, X-Plane, declined this session',
          ),
        ],
      );
      expect(find.byKey(const Key('known-computer')), findsOneWidget);
      expect(find.text('192.168.1.117'), findsOneWidget);
      expect(
        find.text('MAC, macOS, X-Plane, declined this session'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('known-computer')));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '192.168.1.117',
      );
      expect(saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('the example address gets no note', (tester) async {
      await pumpDialog(
        tester,
        known: const [
          KnownAddress(address: exampleAddress, description: 'example'),
        ],
      );
      expect(find.byKey(const Key('known-computer')), findsNothing);
    });

    testWidgets('invalid input shows an error and disables Save', (
      tester,
    ) async {
      await pumpDialog(tester);
      expect(saveButton(tester).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '300.1.1.1');
      await tester.pump();
      expect(find.textContaining('Enter four numbers'), findsOneWidget);
      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets('the error stays on screen above a tall keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1024, 600);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 360);
      addTearDown(tester.view.reset);
      await pumpDialog(tester);
      await tester.enterText(find.byType(TextField), '300.1.1.1');
      await tester.pumpAndSettle();
      final error = find.textContaining('Enter four numbers');
      expect(error, findsOneWidget);
      final bottom = tester.getBottomLeft(error).dy;
      expect(bottom, lessThanOrEqualTo(600 - 360));
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty input shows no error yet', (tester) async {
      await pumpDialog(tester);
      expect(find.textContaining('Enter four numbers'), findsNothing);
    });

    testWidgets('valid input saves', (tester) async {
      ManualIpChoice? result;
      await pumpDialog(tester, onResult: (r) => result = r);
      await tester.enterText(find.byType(TextField), ' 192.168.1.20 ');
      await tester.pump();
      await tester.tap(find.text('Try'));
      await tester.pumpAndSettle();
      expect(result, isA<ManualIpTry>());
      expect((result! as ManualIpTry).address, '192.168.1.20');
    });

    testWidgets('clear removes it', (tester) async {
      ManualIpChoice? result;
      await pumpDialog(
        tester,
        initial: '10.0.0.5',
        onResult: (r) => result = r,
      );
      await tester.tap(find.text('Erase saved IP'));
      await tester.pumpAndSettle();
      expect(result, isA<ManualIpClear>());
    });

    testWidgets('Erase saved IP is greyed out when nothing is saved', (
      tester,
    ) async {
      await pumpDialog(tester);
      final erase = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Erase saved IP'),
      );
      expect(erase.onPressed, isNull);
    });

    testWidgets('Erase saved IP is enabled when an IP is saved', (
      tester,
    ) async {
      await pumpDialog(tester, initial: '10.0.0.5');
      final erase = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Erase saved IP'),
      );
      expect(erase.onPressed, isNotNull);
    });

    testWidgets('the drop-down lists each known address with its facts', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        initial: '10.0.0.5',
        known: const [
          KnownAddress(address: '10.0.0.5', description: 'saved and connected'),
          KnownAddress(address: '10.0.0.9', description: 'MacBook, macOS'),
          KnownAddress(address: '10.0.0.10', description: 'unknown'),
        ],
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('saved and connected'), findsWidgets);
      expect(find.text('MacBook, macOS'), findsWidgets);
      expect(find.text('unknown'), findsWidgets);
      await tester.tap(find.text('MacBook, macOS').last);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '10.0.0.9');
    });

    testWidgets('the list opens on tap and closes while typing', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        known: const [
          KnownAddress(address: '10.0.0.9', description: 'MacBook, macOS'),
          KnownAddress(address: '10.0.0.10', description: 'unknown'),
        ],
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('MacBook, macOS'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '10.0.0.');
      await tester.pumpAndSettle();
      expect(find.text('MacBook, macOS'), findsNothing);
      expect(find.text('Try'), findsOneWidget);
      // The arrow opens it again.
      await tester.tap(find.byIcon(Icons.arrow_drop_down));
      await tester.pumpAndSettle();
      expect(find.text('MacBook, macOS'), findsOneWidget);
    });

    testWidgets('typed text that is not in the list is accepted', (
      tester,
    ) async {
      ManualIpChoice? result;
      await pumpDialog(
        tester,
        known: const [
          KnownAddress(address: '192.168.1.20', description: 'example'),
          KnownAddress(address: '192.168.1.30', description: 'unknown'),
        ],
        onResult: (r) => result = r,
      );
      await tester.enterText(find.byType(TextField), '10.1.2.3');
      await tester.pump();
      await tester.tap(find.text('Try'));
      await tester.pumpAndSettle();
      expect((result! as ManualIpTry).address, '10.1.2.3');
    });

    testWidgets(
      'one known address gives a text box starting with its network',
      (tester) async {
        await pumpDialog(
          tester,
          known: const [
            KnownAddress(address: '192.168.1.12', description: 'MacBook'),
          ],
        );
        expect(find.byType(MenuAnchor), findsNothing);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller?.text, '192.168.1.');
        expect(field.controller?.selection.baseOffset, 10);
        expect(find.textContaining('Enter four numbers'), findsNothing);
        await tester.enterText(find.byType(TextField), '192.168.1.7');
        await tester.pump();
        expect(saveButton(tester).onPressed, isNotNull);
      },
    );

    testWidgets('a saved ip wins over the network prefix', (tester) async {
      await pumpDialog(
        tester,
        initial: '10.0.0.5',
        known: const [
          KnownAddress(address: '192.168.1.12', description: 'MacBook'),
        ],
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '10.0.0.5');
    });

    testWidgets('pre-filled with the saved ip', (tester) async {
      await pumpDialog(tester, initial: '10.0.0.5');
      expect(find.text('10.0.0.5'), findsOneWidget);
      expect(saveButton(tester).onPressed, isNotNull);
    });

    testWidgets('cancel returns nothing', (tester) async {
      var called = false;
      ManualIpChoice? result = const ManualIpClear();
      await pumpDialog(
        tester,
        onResult: (r) {
          called = true;
          result = r;
        },
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(called, isTrue);
      expect(result, isNull);
    });

    testWidgets('uses a number keyboard', (tester) async {
      await pumpDialog(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );
    });
  });

  group('SimChooser', () {
    const sims = [
      DiscoveredSim(host: '10.0.0.5', name: 'Cockpit PC'),
      DiscoveredSim(host: '10.0.0.6'),
    ];

    Future<void> pumpChooser(
      WidgetTester tester,
      List<DiscoveredSim> list, {
      String? selected,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: SimChooser(sims: list, selectedHost: selected),
          ),
        ),
      ),
    );

    testWidgets('each computer shows its OS and simulator when known', (
      tester,
    ) async {
      await pumpChooser(tester, const [
        DiscoveredSim(
          host: '10.0.0.5',
          name: 'Cockpit PC',
          simulator: Simulator.xplane,
          os: HostOs.windows,
        ),
        DiscoveredSim(
          host: '10.0.0.6',
          name: 'Mac',
          simulator: Simulator.xplane,
          os: HostOs.macos,
        ),
      ]);
      expect(find.text('Windows · X-Plane'), findsOneWidget);
      expect(find.text('macOS · X-Plane'), findsOneWidget);
      expect(find.text('Waiting for connection'), findsNothing);
    });

    testWidgets('only the known fact is shown, none is guessed', (
      tester,
    ) async {
      await pumpChooser(tester, const [
        DiscoveredSim(host: '10.0.0.5', simulator: Simulator.xplane),
        DiscoveredSim(host: '10.0.0.6', os: HostOs.linux),
      ]);
      expect(find.text('X-Plane'), findsOneWidget);
      expect(find.text('Linux'), findsOneWidget);
    });

    testWidgets('a computer with neither fact shows only a status word', (
      tester,
    ) async {
      await pumpChooser(tester, sims);
      expect(find.text('Waiting for connection'), findsNWidgets(2));
      await tester.tap(find.text('Cockpit PC'));
      await tester.pump();
      expect(find.text('Connecting'), findsOneWidget);
      expect(find.text('Waiting for connection'), findsOneWidget);
    });

    testWidgets('list appears only for 2 or more sims', (tester) async {
      await pumpChooser(tester, [sims.first]);
      expect(find.byType(ListTile), findsNothing);
      await pumpChooser(tester, sims);
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.text('Cockpit PC'), findsOneWidget);
      expect(find.text('10.0.0.6'), findsOneWidget);
    });

    testWidgets('tap selects the sim', (tester) async {
      await pumpChooser(tester, sims);
      await tester.tap(find.text('Cockpit PC'));
      await tester.pump();
      expect(sim.selectedSim, sims.first);
    });

    testWidgets('selected sim is marked', (tester) async {
      await pumpChooser(tester, sims, selected: '10.0.0.6');
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      await tester.tap(find.text('Cockpit PC'));
      await tester.pump();
      final checked = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .where((t) => t.selected)
          .toList();
      expect(checked, hasLength(1));
      expect((checked.single.title! as Text).data, 'Cockpit PC');
    });
  });
}
