import 'dart:async';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository.dart';
import 'package:flightsim_aide/data/repositories/settings/settings_repository.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/routing/routes.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_detail_screen.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_item_tile.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flightsim_aide/ui/core/themes/status_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_checklist_repository.dart';
import '../../../testing/fakes/repositories/fake_flight_sim_repository.dart';
import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/services/manual_clock.dart';

// AC-34: a tick against the dataref opens a red dialog that needs an acknowledge press, and the row stays red

const _text = '''
sw_checklist:Start
sw_item:Gear|DOWN:a/gear:1
sw_item:Flaps|SET:a/flaps:1
sw_item:Manual|DONE
''';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  const check = ChecklistItem(ChecklistItemType.check, 'Parking brake', 'SET');

  group('the red mark on a row', () {
    Future<void> pumpTile(
      WidgetTester tester, {
      required bool disagreed,
      ThemeData? theme,
      bool checked = true,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: Scaffold(
          body: ChecklistItemTile(
            item: check,
            checked: checked,
            disagreed: disagreed,
            onTap: () {},
          ),
        ),
      ),
    );

    Color? rowBackground(WidgetTester tester) => tester
        .widget<Material>(
          find
              .descendant(
                of: find.byType(ChecklistItemTile),
                matching: find.byType(Material),
              )
              .first,
        )
        .color;

    testWidgets('shows the Material error icon on an error-colour row', (
      tester,
    ) async {
      await pumpTile(tester, disagreed: true);
      final icon = tester.widget<Icon>(find.byKey(disagreedMarkerKey));
      expect(icon.icon, Icons.error);
      final error = AppTheme.light.extension<StatusColors>()!.error;
      expect(rowBackground(tester), error);
      expect(icon.color, isNot(error));
    });

    testWidgets('uses the error colour of the dark theme too', (tester) async {
      await pumpTile(tester, disagreed: true, theme: AppTheme.dark);
      expect(
        rowBackground(tester),
        AppTheme.dark.extension<StatusColors>()!.error,
      );
    });

    testWidgets('is absent for a row that agrees', (tester) async {
      await pumpTile(tester, disagreed: false);
      expect(find.byKey(disagreedMarkerKey), findsNothing);
    });

    testWidgets('is absent on an open row even if the flag is set', (
      tester,
    ) async {
      await pumpTile(tester, disagreed: true, checked: false);
      expect(find.byKey(disagreedMarkerKey), findsNothing);
    });

    testWidgets('does not rely on colour alone: the row says why', (
      tester,
    ) async {
      await pumpTile(tester, disagreed: true);
      expect(find.bySemanticsLabel(RegExp('not set')), findsWidgets);
    });
  });

  group('the detail screen', () {
    late FakeChecklistRepository repository;
    late ChecklistProgressRepositoryImpl progress;
    late FakeFlightSimRepository sim;
    late FakeSettingsRepository settings;
    late ManualClock clock;

    Future<void> pump(WidgetTester tester) async {
      clock = ManualClock();
      settings = FakeSettingsRepository();
      sim = FakeFlightSimRepository(clock: clock, settings: settings)
        ..setStatus(const ConnectionConnected())
        ..setAircraft(
          const AircraftIdentity(
            icao: 'C172',
            description: 'Cessna',
            aircraftPath: 'c172.acf',
          ),
        );
      repository = FakeChecklistRepository(
        current: const AircraftWorkflowParser().parse(_text),
      );
      progress = ChecklistProgressRepositoryImpl();
      final router = createRouter(initialLocation: Routes.list);
      addTearDown(router.dispose);
      addTearDown(repository.dispose);
      addTearDown(progress.dispose);
      addTearDown(sim.dispose);
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<ChecklistRepository>.value(value: repository),
            RepositoryProvider<ChecklistProgressRepository>.value(
              value: progress,
            ),
            RepositoryProvider<FlightSimRepository>.value(value: sim),
            RepositoryProvider<SettingsRepository>.value(value: settings),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      unawaited(router.push(Routes.detailPath('Start')));
      await settle(tester);
    }

    Future<void> advance(WidgetTester tester, [int ms = 500]) async {
      clock.advance(Duration(milliseconds: ms));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('ticking a false item opens a red dialog and keeps the tick', (
      tester,
    ) async {
      await pump(tester);
      sim.signals.setValue('a/gear', 0);
      await advance(tester);
      await tester.tap(find.text('Gear'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(tickWarningDialogKey), findsOneWidget);
      expect(
        find.text('The simulation value for Gear down is false.'),
        findsOneWidget,
      );
      final icon = tester.widget<Icon>(find.byKey(tickWarningIconKey));
      expect(icon.icon, Icons.error);
      expect(find.byKey(disagreedMarkerKey), findsOneWidget);
    });

    testWidgets(
      'the dialog needs the button: a tap outside does not close it',
      (tester) async {
        await pump(tester);
        sim.signals.setValue('a/gear', 0);
        await advance(tester);
        await tester.tap(find.text('Gear'));
        await tester.pump();
        await tester.pump();
        await tester.tapAt(const Offset(2, 2));
        await tester.pump();
        expect(find.byKey(tickWarningDialogKey), findsOneWidget);
        await tester.tap(find.byKey(tickWarningAcknowledgeKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(tickWarningDialogKey), findsNothing);
      },
    );

    testWidgets('after the button the row stays ticked and red', (
      tester,
    ) async {
      await pump(tester);
      sim.signals.setValue('a/gear', 0);
      await advance(tester);
      await tester.tap(find.text('Gear'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(tickWarningAcknowledgeKey));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(disagreedMarkerKey), findsOneWidget);
      expect(progress.current.isChecked('Start', 0), isTrue);
    });

    testWidgets('Cancel backs out: the dialog closes and the item is open', (
      tester,
    ) async {
      await pump(tester);
      sim.signals.setValue('a/gear', 0);
      await advance(tester);
      await tester.tap(find.text('Gear'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(tickWarningCancelKey), findsOneWidget);
      await tester.tap(find.byKey(tickWarningCancelKey));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(tickWarningDialogKey), findsNothing);
      expect(find.byKey(disagreedMarkerKey), findsNothing);
      expect(progress.current.isChecked('Start', 0), isFalse);
    });

    testWidgets('unticking removes the red mark and opens no dialog', (
      tester,
    ) async {
      await pump(tester);
      sim.signals.setValue('a/gear', 0);
      await advance(tester);
      await tester.tap(find.text('Gear'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(tickWarningAcknowledgeKey));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Gear'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(tickWarningDialogKey), findsNothing);
      expect(find.byKey(disagreedMarkerKey), findsNothing);
    });

    testWidgets('a tick that agrees, is unknown or has no condition is quiet', (
      tester,
    ) async {
      await pump(tester);
      sim.signals.setValue('a/flaps', 1);
      await advance(tester);
      await tester.tap(find.text('Flaps')); // agrees
      await tester.pump();
      await tester.tap(find.text('Manual')); // no condition
      await tester.pump();
      await tester.tap(find.text('Gear')); // no value yet
      await tester.pump();
      await tester.pump();
      expect(find.byKey(tickWarningDialogKey), findsNothing);
      expect(find.byKey(disagreedMarkerKey), findsNothing);
    });
  });
}
