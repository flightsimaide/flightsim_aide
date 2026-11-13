import 'dart:async';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository.dart';
import 'package:flightsim_aide/data/repositories/settings/settings_repository.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/routing/routes.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_detail_screen.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_item_tile.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_checklist_repository.dart';
import '../../../testing/fakes/repositories/fake_flight_sim_repository.dart';
import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/services/manual_clock.dart';

const _count = 40;

ChecklistDocument _long([int count = _count]) =>
    const AircraftWorkflowParser().parse(
      [
        'sw_checklist:long:Long',
        for (var i = 1; i <= count; i++) 'sw_item:Item $i|OK',
        'sw_continue:after:a/ready:1',
        'sw_checklist:mid:Middle',
        'sw_item:M|OK',
        'sw_checklist:after:After',
        'sw_item:Z|OK',
      ].join('\n'),
    );

/// Every item has a dataref condition, so auto mode ticks it.
ChecklistDocument _conditional() => const AircraftWorkflowParser().parse(
  [
    'sw_checklist:long:Long',
    for (var i = 1; i <= _count; i++) 'sw_item:Item $i|OK:t/v$i:1',
  ].join('\n'),
);

/// The connection indicator animates, so no pumpAndSettle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeFlightSimRepository sim;
  late ManualClock clock;

  Future<void> pump(
    WidgetTester tester, {
    int count = _count,
    ChecklistDocument? doc,
  }) async {
    clock = ManualClock();
    final settings = FakeSettingsRepository();
    sim = FakeFlightSimRepository(clock: clock, settings: settings)
      ..setStatus(const ConnectionConnected())
      ..setAircraft(
        const AircraftIdentity(
          icao: 'C172',
          description: 'Cessna',
          aircraftPath: 'c172.acf',
        ),
      );
    addTearDown(sim.dispose);
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repository = FakeChecklistRepository(current: doc ?? _long(count));
    final progress = ChecklistProgressRepositoryImpl();
    final router = createRouter(initialLocation: Routes.list);
    addTearDown(router.dispose);
    addTearDown(repository.dispose);
    addTearDown(progress.dispose);
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
    unawaited(router.push(Routes.detailPath('long')));
    await settle(tester);
  }

  Future<void> tick(WidgetTester tester, int from, int to) async {
    for (var i = from; i <= to; i++) {
      await tester.tap(find.text('Item $i'));
      // The scroll starts on the frame after the tap, then runs 250 ms.
      for (var f = 0; f < 6; f++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
  }

  testWidgets('the list scrolls so the next item is visible', (tester) async {
    await pump(tester);
    final viewport = tester.getRect(find.byType(ListView));
    // Item 40 is far below the first screen.
    expect(find.text('Item $_count'), findsNothing);
    await tick(tester, 1, 12);
    // Ticking item 12 makes item 13 the next one.
    final next = tester.getRect(find.text('Item 13'));
    expect(next.top, greaterThanOrEqualTo(viewport.top));
    expect(next.bottom, lessThanOrEqualTo(viewport.bottom));
  });

  testWidgets('a next item that is already visible does not scroll', (
    tester,
  ) async {
    await pump(tester);
    await tick(tester, 1, 2);
    final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(list.position.pixels, 0);
  });

  testWidgets('opening a list whose button row is near does not scroll', (
    tester,
  ) async {
    // Showing the current checklist button sideways must not move the list.
    await pump(tester, count: 12);
    final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(list.position.maxScrollExtent, greaterThan(0));
    expect(list.position.pixels, 0);
  });

  testWidgets('Continue is at the bottom, above the buttons', (tester) async {
    await pump(tester);
    await tick(tester, 1, 12);
    // Tick the rest by tapping each as it scrolls into view.
    await tick(tester, 13, _count);
    sim.signals.setValue('a/ready', 1);
    clock.advance(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump();
    expect(find.text('Complete'), findsOneWidget);
    final button = tester.getRect(find.byKey(continueButtonKey));
    final reset = tester.getRect(find.text('Reset').last);
    final status = tester.getRect(find.text('$_count/$_count'));
    expect(button.top, greaterThan(status.bottom));
    expect(button.bottom, lessThanOrEqualTo(reset.top));
    expect(find.byType(ChecklistItemTile), findsWidgets);
  });

  testWidgets('checking the last items at once scrolls to the end', (
    tester,
  ) async {
    await pump(tester);
    await tick(tester, 1, 12);
    // Check the rest without waiting for the list to follow, as auto does.
    for (var i = 13; i <= _count; i++) {
      await tester.tap(find.byKey(checkKey));
      await tester.pump(const Duration(milliseconds: 10));
    }
    await settle(tester);
    final viewport = tester.getRect(find.byType(ListView));
    final row = tester.getRect(find.byKey(checklistButtonKey('long')));
    expect(row.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(row.top, greaterThanOrEqualTo(viewport.top));
    final last = tester.getRect(find.text('Item $_count'));
    expect(last.bottom, lessThanOrEqualTo(viewport.bottom));
  });

  testWidgets('items left open above a tick in the middle: still scrolls to '
      'the end when the rest is checked', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(
      find.text('Item 20'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Rows with no condition are taller now; bring the whole row into view.
    await tester.ensureVisible(find.text('Item 20'));
    await tester.pump();
    await tester.tap(find.text('Item 20'));
    await settle(tester);
    for (var i = 21; i <= _count; i++) {
      await tester.tap(find.byKey(checkKey));
      await tester.pump(const Duration(milliseconds: 10));
    }
    await settle(tester);
    // Item 1 to 19 are still open, so the list is not complete.
    expect(find.text('Complete'), findsNothing);
    final viewport = tester.getRect(find.byType(ListView));
    final row = tester.getRect(find.byKey(checklistButtonKey('long')));
    expect(row.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(row.top, greaterThanOrEqualTo(viewport.top));
  });

  testWidgets('the second button toggles Auto and Manual', (tester) async {
    await pump(tester);
    expect(find.text('Auto'), findsOneWidget);
    await tester.tap(find.byKey(autoToggleKey));
    await tester.pump();
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('Auto'), findsNothing);
    await tester.tap(find.byKey(autoToggleKey));
    await tester.pump();
    expect(find.text('Auto'), findsOneWidget);
  });

  testWidgets('Reset clears the ticks, goes to Manual and scrolls to the top', (
    tester,
  ) async {
    await pump(tester);
    await tick(tester, 1, 12);
    final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(list.position.pixels, greaterThan(0));
    await tester.tap(find.byKey(bottomResetKey));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Reset'),
      ),
    );
    for (var f = 0; f < 6; f++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('0/$_count'), findsOneWidget);
    expect(list.position.pixels, 0);
  });

  testWidgets('auto stopped on a false dataref, then ticks several items: the '
      'list follows to the new pointer item', (tester) async {
    await pump(tester, doc: _conditional());
    Future<void> set(int from, int to) async {
      for (var i = from; i <= to; i++) {
        sim.signals.setValue('t/v$i', 1);
      }
      clock.advance(const Duration(milliseconds: 500));
      await settle(tester);
    }

    await set(1, 24);
    final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(find.text('24/$_count'), findsOneWidget);
    // Auto waits on item 25 for a while.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1200)),
    );
    final viewport = tester.getRect(find.byType(ListView));
    await set(25, 29);
    expect(find.text('29/$_count'), findsOneWidget);
    final next = tester.getRect(find.text('Item 30'));
    expect(next.top, greaterThanOrEqualTo(viewport.top));
    expect(next.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(list.position.pixels, greaterThan(0));
  });
}
