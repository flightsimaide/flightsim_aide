import 'package:flightsim_aide/app.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/routing/routes.dart';
import 'package:flightsim_aide/ui/checklist_list/widgets/checklist_list_screen.dart';
import 'package:flightsim_aide/ui/home/widgets/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../testing/fakes/repositories/fake_checklist_repository.dart';

List<RepositoryProvider<dynamic>> fakes() => [
  RepositoryProvider<ChecklistRepository>.value(
    value: FakeChecklistRepository(),
  ),
  RepositoryProvider<ChecklistProgressRepository>.value(
    value: FakeChecklistProgressRepository(),
  ),
];

void main() {
  testWidgets('App builds with fake repositories', (tester) async {
    await tester.pumpWidget(App(providers: fakes()));
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('providers are readable below the app', (tester) async {
    await tester.pumpWidget(App(providers: fakes()));
    final context = tester.element(find.byType(HomeScreen));
    expect(context.read<ChecklistRepository>(), isA<FakeChecklistRepository>());
    expect(
      context.read<ChecklistProgressRepository>(),
      isA<FakeChecklistProgressRepository>(),
    );
  });

  testWidgets('uses system theme mode', (tester) async {
    await tester.pumpWidget(App(providers: fakes()));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
  });

  testWidgets('debug banner is hidden so it cannot cover app bar actions', (
    tester,
  ) async {
    await tester.pumpWidget(App(providers: fakes()));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.debugShowCheckedModeBanner, isFalse);
  });

  testWidgets('router can be injected', (tester) async {
    final router = createRouter(initialLocation: Routes.list);
    addTearDown(router.dispose);
    await tester.pumpWidget(App(providers: fakes(), router: router));
    expect(find.byType(ChecklistListScreen), findsOneWidget);
  });
}
