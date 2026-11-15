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

// Task 0.30: the checklist button row, Continue hidden for the next one

const _text = '''
sw_checklist:one:First
sw_item:A|ok
sw_item:B|ok
sw_continue:two
sw_checklist:mid:Middle
sw_item:M|ok
sw_continue:two
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

  Future<void> pump(
    WidgetTester tester, {
    String text = _text,
    String open = 'one',
    double width = 800,
  }) async {
    tester.view.physicalSize = Size(width, 1200);
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
      current: const AircraftWorkflowParser().parse(text),
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
    unawaited(router.push(Routes.detailPath(open)));
    await settle(tester);
  }

  testWidgets('the row has one button per checklist, current one inert', (
    tester,
  ) async {
    await pump(tester);
    await tester.scrollUntilVisible(
      find.byKey(checklistButtonsKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    for (final name in ['one', 'mid', 'two']) {
      expect(find.byKey(checklistButtonKey(name)), findsOneWidget);
    }
    final current = tester.widget<ChoiceChip>(
      find.byKey(checklistButtonKey('one')),
    );
    expect(current.selected, isTrue);
    expect(current.onSelected, isNull);
  });

  testWidgets('a tap on a button opens that checklist at once when all done', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Check'));
    await tester.tap(find.text('Check'));
    await settle(tester);
    await tester.ensureVisible(find.byKey(checklistButtonKey('two')));
    await tester.tap(find.byKey(checklistButtonKey('two')));
    await settle(tester);
    expect(find.byKey(continueCautionDialogKey), findsNothing);
    expect(find.text('Second'), findsWidgets);
  });

  testWidgets('a tap with unchecked items opens the checklist at once', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Check'));
    await settle(tester);
    await tester.ensureVisible(find.byKey(checklistButtonKey('mid')));
    await tester.tap(find.byKey(checklistButtonKey('mid')));
    await settle(tester);
    expect(find.byKey(continueCautionDialogKey), findsNothing);
    expect(find.text('Middle'), findsWidgets);
  });

  testWidgets('a tap with skipped items opens the checklist at once', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(skipKey));
    await settle(tester);
    await tester.ensureVisible(find.byKey(checklistButtonKey('two')));
    await tester.tap(find.byKey(checklistButtonKey('two')));
    await settle(tester);
    expect(find.byKey(continueCautionDialogKey), findsNothing);
    expect(find.text('Second'), findsWidgets);
  });

  testWidgets('a tap on an earlier checklist opens it at once', (tester) async {
    await pump(tester, open: 'two');
    await tester.ensureVisible(find.byKey(checklistButtonKey('one')));
    await tester.tap(find.byKey(checklistButtonKey('one')));
    await settle(tester);
    expect(find.byKey(continueCautionDialogKey), findsNothing);
    expect(find.text('First'), findsWidgets);
  });

  testWidgets('Continue is hidden when its target is the next checklist', (
    tester,
  ) async {
    await pump(tester);
    // one links to two, which is not next (mid is): shown when complete.
    await tester.tap(find.text('Check'));
    await tester.tap(find.text('Check'));
    await settle(tester);
    expect(find.byKey(continueButtonKey), findsOneWidget);
    // mid links to two, which is next in the file: hidden.
    unawaited(router.pushReplacement(Routes.detailPath('mid')));
    await settle(tester);
    await tester.tap(find.text('Check'));
    await settle(tester);
    expect(find.byKey(continueButtonKey), findsNothing);
  });

  testWidgets('the row scrolls to centre the open checklist', (tester) async {
    final text = StringBuffer();
    for (var i = 1; i <= 12; i++) {
      text.writeln('sw_checklist:c$i:Checklist number $i');
      text.writeln('sw_item:Item|ok');
    }
    await pump(tester, text: text.toString(), open: 'c10', width: 400);
    final row = find.byKey(checklistButtonsKey);
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    final rowBox = tester.getRect(row);
    final chip = tester.getRect(find.byKey(checklistButtonKey('c10')));
    expect(
      (chip.center.dx - rowBox.center.dx).abs(),
      lessThan(2),
      reason: 'chip $chip in row $rowBox',
    );
  });
}
