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
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../testing/fakes/repositories/fake_checklist_repository.dart';
import '../../../testing/fakes/repositories/fake_flight_sim_repository.dart';
import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/services/manual_clock.dart';

// AC-33: the screen shows an auto-checked marker, no async work in build
// AC-38: the Continue button opens the target; absent when nothing matched; auto-continue opens it by itself
// AC-41: the "N items stay manual" notice shows when the sim cannot give a value
// AC-45: the notice counts the items that stay manual

const _text = '''
sw_checklist:Start
sw_item:Gear|DOWN:a/gear:1
sw_item:Flaps|SET:a/flaps:1
sw_continue:Taxi:a/ready:1
sw_continue:Other
sw_checklist:Mid
sw_item:M|ON
sw_checklist:Taxi
sw_item:Light|ON
sw_checklist:Other
sw_item:Spare|ON
''';

/// Lets routes finish; the connection indicator animates, so no pumpAndSettle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  const check = ChecklistItem(ChecklistItemType.check, 'Parking brake', 'SET');

  group('an auto-checked row', () {
    Future<void> pumpTile(
      WidgetTester tester, {
      required bool checked,
      required bool auto,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ChecklistItemTile(
            item: check,
            checked: checked,
            autoChecked: auto,
            onTap: () {},
          ),
        ),
      ),
    );

    testWidgets('an auto-checked row shows no icon, but is spoken as such', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpTile(tester, checked: true, auto: true);
      expect(find.byIcon(Icons.auto_mode), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('checked automatically')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('tapping still calls onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ChecklistItemTile(
              item: check,
              checked: true,
              autoChecked: true,
              onTap: () => taps++,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ChecklistItemTile));
      expect(taps, 1);
    });
  });

  group('the detail screen with a flight sim', () {
    late FakeChecklistRepository repository;
    late ChecklistProgressRepositoryImpl progress;
    late FakeFlightSimRepository sim;
    late FakeSettingsRepository settings;
    late GoRouter router;
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
      router = createRouter(initialLocation: Routes.list);
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

    testWidgets('a scripted value checks the row', (tester) async {
      await pump(tester);
      expect(find.byIcon(Icons.check), findsNothing);
      sim.signals.setValue('a/gear', 1);
      await advance(tester);
      expect(find.byIcon(Icons.check), findsOneWidget);
      // A manual uncheck is not undone.
      await tester.tap(find.text('Gear'));
      await tester.pump();
      expect(find.byIcon(Icons.check), findsNothing);
      await advance(tester);
      await advance(tester);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('no Continue button before a link matched', (tester) async {
      await pump(tester);
      expect(find.byKey(continueButtonKey), findsNothing);
    });

    testWidgets(
      'the Continue button shows when complete and opens the target',
      (tester) async {
        await pump(tester);
        sim.signals
          ..setValue('a/gear', 1)
          ..setValue('a/flaps', 1)
          ..setValue('a/ready', 1);
        await advance(tester);
        await advance(tester);
        expect(find.byKey(continueButtonKey), findsOneWidget);
        expect(find.text('Continue: Taxi'), findsOneWidget);
        // Two links, one button: no "Next:" buttons beside it.

        expect(find.textContaining('Next:'), findsNothing);
        await tester.tap(find.byKey(continueButtonKey));
        await settle(tester);
        expect(find.text('Light'), findsOneWidget);
      },
    );

    testWidgets('the notice shows how many items stay manual', (tester) async {
      await pump(tester);
      sim.signals.reject('a/flaps');
      // Reopen so the watch learns the rejection.
      router.pop();
      await settle(tester);
      unawaited(router.push(Routes.detailPath('Start')));
      await settle(tester);
      expect(find.text('1 item stays manual'), findsOneWidget);
    });
  });
}
