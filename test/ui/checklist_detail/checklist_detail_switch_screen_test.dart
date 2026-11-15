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

// AC-54: the items of the branch a switch hides are not shown and not
// counted; the total changes with the switch; the switch row is an item

// Rows: 0 Before, 1 Use GPU (switch), 2 GPU and 3 GPU power (ON branch),
// 4 Unplug (OFF branch), 5 After.
const _text = '''
sw_checklist:Prepare
sw_item:Before|ON
sw_switch:Use GPU|gpu|OFF
sw_item:GPU|CONNECT
sw_item:GPU power|ON
sw_else
sw_item:Unplug|CHECK
sw_end
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

  List<String> labels(WidgetTester tester) => [
    for (final t in tester.widgetList<ChecklistItemTile>(
      find.byType(ChecklistItemTile),
    ))
      t.item.label,
  ];

  testWidgets('the switch starts off: the OFF branch shows, total 0/4', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('0/4'), findsOneWidget);
    expect(labels(tester), ['Before', 'Use GPU', 'Unplug', 'After']);
    expect(find.text('GPU power'), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is Opacity && w.opacity == 0.38),
      findsNothing,
      reason: 'hidden, not greyed',
    );
    expect(tester.widget<Switch>(find.byKey(optionSwitchKey)).value, isFalse);
  });

  testWidgets('the switch swaps the branches and the total follows', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(optionSwitchKey));
    await tester.pumpAndSettle();
    expect(find.text('0/5'), findsOneWidget);
    expect(labels(tester), ['Before', 'Use GPU', 'GPU', 'GPU power', 'After']);
    await tester.tap(find.text('GPU power'));
    await tester.pump();
    expect(find.text('1/5'), findsOneWidget);
    // Off again: the tick of its item is gone and the total drops.
    await tester.tap(find.byKey(optionSwitchKey));
    await tester.pumpAndSettle();
    expect(find.text('0/4'), findsOneWidget);
    expect(progress.current.checked['Prepare'] ?? const <int>{}, isEmpty);
  });

  testWidgets('tapping the switch row ticks it and does not turn it on', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Use GPU'));
    await tester.pump();
    expect(progress.current.checked['Prepare'], {1});
    expect(tester.widget<Switch>(find.byKey(optionSwitchKey)).value, isFalse);
    expect(find.text('1/4'), findsOneWidget);
  });

  testWidgets('the Check button passes over the hidden rows', (tester) async {
    await pump(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Check'));
      await tester.pump();
    }
    // 0, the switch row (an item), 4 (the OFF branch), then 5.
    expect(progress.current.checked['Prepare'], {0, 1, 4, 5});
    expect(find.text('Complete'), findsWidgets);
  });
}
