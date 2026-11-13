import 'dart:async';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository.dart';
import 'package:flightsim_aide/data/repositories/settings/settings_repository.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/routing/routes.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_detail_screen.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../testing/fakes/repositories/fake_checklist_repository.dart';
import '../../../testing/fakes/repositories/fake_flight_sim_repository.dart';
import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/services/manual_clock.dart';

// Task 0.24: Skip button, "n skipped", and the Continue caution dialog

const _text = '''
sw_checklist:one:First
sw_item:A|ok
sw_item:B|ok
sw_continue:two
sw_checklist:mid:Middle
sw_item:M|ok
sw_checklist:two:Second
sw_item:C|ok
''';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late ChecklistProgressRepositoryImpl progress;
  late FakeChecklistRepository repository;
  late FakeFlightSimRepository sim;
  late FakeSettingsRepository settings;
  late GoRouter router;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clock = ManualClock();
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
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    unawaited(router.push(Routes.detailPath('one')));
    await settle(tester);
  }

  FilledButton button(WidgetTester tester, String label) =>
      tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(FilledButton),
        ),
      );

  testWidgets('unticking in Auto switches to Manual and says so', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(checkKey));
    await settle(tester);
    expect(find.text('Auto'), findsOneWidget);
    await tester.tap(find.text('A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(manualNoticeText), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    // In Manual mode a second untick says nothing.
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).last))
        .clearSnackBars();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('A'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('A'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(manualNoticeText), findsNothing);
  });

  testWidgets('Skip skips the next open item, then greys out', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(skipKey));
    await settle(tester);
    expect(find.text('1 skipped'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);
    await tester.tap(find.byKey(skipKey));
    await settle(tester);
    expect(find.text('2 skipped'), findsOneWidget);
    expect(find.text('Complete'), findsOneWidget);
    expect(button(tester, 'Skip').onPressed, isNull);
    expect(button(tester, 'Check').onPressed, isNull);
  });

  testWidgets('the progress bar counts skipped items as done', (tester) async {
    await pump(tester);
    double bar() => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value!;
    expect(bar(), 0);
    await tester.tap(find.byKey(skipKey));
    await settle(tester);
    expect(bar(), 0.5);
    await tester.tap(find.text('Check'));
    await settle(tester);
    expect(bar(), 1);
  });

  testWidgets('no "skipped" text when nothing is skipped', (tester) async {
    await pump(tester);
    expect(find.textContaining('skipped'), findsNothing);
  });

  testWidgets('Continue with skipped items asks first; Cancel stays', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(skipKey));
    await settle(tester);
    await tester.tap(find.text('Check'));
    await settle(tester);
    await tester.tap(find.byKey(continueButtonKey));
    await settle(tester);
    expect(find.byKey(continueCautionDialogKey), findsOneWidget);
    expect(find.text('1 checklist item has been skipped'), findsOneWidget);
    expect(find.textContaining('disagree'), findsNothing);
    await tester.tap(find.byKey(continueCautionCancelKey));
    await settle(tester);
    expect(find.byKey(continueCautionDialogKey), findsNothing);
    expect(find.byKey(continueButtonKey), findsOneWidget);
  });

  testWidgets('Continue in the dialog goes on to the next checklist', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(skipKey));
    await tester.tap(find.byKey(skipKey));
    await settle(tester);
    await tester.tap(find.byKey(continueButtonKey));
    await settle(tester);
    expect(find.text('2 checklist items have been skipped'), findsOneWidget);
    await tester.tap(find.byKey(continueCautionContinueKey));
    await settle(tester);
    expect(find.byKey(continueCautionDialogKey), findsNothing);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('disagreeing items are counted beside skipped ones', (
    tester,
  ) async {
    await pump(tester);
    progress.toggle('one', 0, disagrees: true);
    await settle(tester);
    await tester.tap(find.byKey(skipKey));
    await settle(tester);
    await tester.tap(find.byKey(continueButtonKey));
    await settle(tester);
    expect(find.text('1 checklist item has been skipped'), findsOneWidget);
    expect(
      find.text('1 checklist item disagrees with the aircraft state'),
      findsOneWidget,
    );
  });

  testWidgets('only disagreeing items: that line alone', (tester) async {
    await pump(tester);
    progress.toggle('one', 0, disagrees: true);
    progress.toggle('one', 1);
    await settle(tester);
    await tester.tap(find.byKey(continueButtonKey));
    await settle(tester);
    expect(find.textContaining('skipped'), findsNothing);
    expect(
      find.text('1 checklist item disagrees with the aircraft state'),
      findsOneWidget,
    );
  });

  testWidgets('with neither, Continue goes straight on', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Check'));
    await settle(tester);
    await tester.tap(find.text('Check'));
    await settle(tester);
    await tester.tap(find.byKey(continueButtonKey));
    await settle(tester);
    expect(find.byKey(continueCautionDialogKey), findsNothing);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('checking the last item says the checklist is complete', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(checkKey));
    await settle(tester);
    expect(find.text(completeNoticeText), findsNothing);
    await tester.tap(find.byKey(checkKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(completeNoticeText), findsOneWidget);
  });

  testWidgets('no complete notice when an item was skipped', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(skipKey));
    await settle(tester);
    await tester.tap(find.byKey(checkKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(completeNoticeText), findsNothing);
  });
}
