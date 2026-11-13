import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/routing/routes.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_detail_screen.dart';
import 'package:flightsim_aide/ui/checklist_list/widgets/checklist_list_screen.dart';
import 'package:flightsim_aide/ui/home/widgets/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../testing/fakes/repositories/fake_checklist_repository.dart';

Future<void> pump(WidgetTester tester, {String? initialLocation}) {
  final router = initialLocation == null
      ? createRouter()
      : createRouter(initialLocation: initialLocation);
  addTearDown(router.dispose);
  final repository = FakeChecklistRepository();
  addTearDown(repository.dispose);
  return tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ChecklistRepository>.value(value: repository),
        RepositoryProvider<ChecklistProgressRepository>.value(
          value: FakeChecklistProgressRepository(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

void main() {
  testWidgets('initial location shows the home screen', (tester) async {
    await pump(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('/checklists shows the list screen', (tester) async {
    await pump(tester, initialLocation: Routes.list);
    expect(find.byType(ChecklistListScreen), findsOneWidget);
  });

  testWidgets(
    '/checklists/Before%20Start%20%2F%20Taxi gives the decoded name',
    (tester) async {
      await pump(
        tester,
        initialLocation: '/checklists/Before%20Start%20%2F%20Taxi',
      );
      expect(_detailName(tester), 'Before Start / Taxi');
    },
  );

  testWidgets('detailPath round-trips through the router', (tester) async {
    await pump(tester, initialLocation: Routes.detailPath('A/B c'));
    expect(_detailName(tester), 'A/B c');
  });
}

String _detailName(WidgetTester tester) => tester
    .widget<ChecklistDetailScreen>(find.byType(ChecklistDetailScreen))
    .checklistName;
