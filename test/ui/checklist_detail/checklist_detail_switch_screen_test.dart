import 'dart:async';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/routing/routes.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_item_tile.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../testing/fakes/repositories/fake_checklist_repository.dart';

// AC-54: a switch block's items count only while its switch is on; the total
// changes with the switch; items of an off switch are greyed out and cannot
// be ticked

// Rows: 0 Before, 1 Use GPU (switch), 2 GPU, 3 GPU power, 4 After.
const _text = '''
sw_checklist:Prepare
sw_item:Before|ON
sw_enable_start:Use GPU
sw_item:GPU|CONNECT
sw_item:GPU power|ON
sw_enable_end
sw_item:After|ON
''';

void main() {
  late FakeChecklistRepository repository;
  late ChecklistProgressRepositoryImpl progress;
  late GoRouter router;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository = FakeChecklistRepository(
      current: const AircraftWorkflowParser().parse(_text),
    );
    progress = ChecklistProgressRepositoryImpl();
    router = createRouter(initialLocation: Routes.list);
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
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    unawaited(router.push(Routes.detailPath('Prepare')));
    await tester.pumpAndSettle();
  }

  ChecklistItemTile tile(WidgetTester tester, int row) =>
      tester.widget<ChecklistItemTile>(find.byType(ChecklistItemTile).at(row));

  testWidgets('the block starts off: greyed rows, total 0/3', (tester) async {
    await pump(tester);
    expect(find.text('0/3'), findsOneWidget);
    expect(
      [for (var i = 0; i < 5; i++) tile(tester, i).enabled],
      [true, true, false, false, true],
    );
    expect(tile(tester, 1).optionOn, isFalse);
  });

  testWidgets('tapping a greyed row ticks nothing', (tester) async {
    await pump(tester);
    await tester.tap(find.text('GPU power'), warnIfMissed: false);
    await tester.pump();
    expect(progress.current.checked, isEmpty);
    expect(find.text('0/3'), findsOneWidget);
  });

  testWidgets('the switch enables the block and the total follows', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(optionSwitchKey));
    await tester.pumpAndSettle();
    expect(find.text('0/5'), findsOneWidget);
    expect([
      for (var i = 0; i < 5; i++) tile(tester, i).enabled,
    ], everyElement(isTrue));
    await tester.tap(find.text('GPU power'));
    await tester.pump();
    expect(find.text('1/5'), findsOneWidget);
    // Off again: the tick of its item is gone and the total drops.
    await tester.tap(find.byKey(optionSwitchKey));
    await tester.pumpAndSettle();
    expect(find.text('0/3'), findsOneWidget);
    expect(progress.current.checked['Prepare'] ?? const <int>{}, isEmpty);
  });

  testWidgets('the Check button passes over the greyed rows', (tester) async {
    await pump(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Check'));
      await tester.pump();
    }
    // 0, the switch row (an item), then past the greyed rows to 4.
    expect(progress.current.checked['Prepare'], {0, 1, 4});
    expect(find.text('Complete'), findsWidgets);
  });
}
