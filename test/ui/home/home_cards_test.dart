import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/ui/checklist_list/widgets/checklist_list_screen.dart';
import 'package:flightsim_aide/ui/core/app_info.dart';
import 'package:flightsim_aide/ui/home/widgets/home_screen.dart';
import 'package:flightsim_aide/ui/settings/widgets/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../../testing/fakes/repositories/fake_checklist_repository.dart';

final _doc = ChecklistDocument(
  checklists: [
    Checklist(
      name: 'a',
      title: 'A',
      items: const [ChecklistItem(ChecklistItemType.check, 'item')],
    ),
    Checklist(
      name: 'b',
      title: 'B',
      items: const [ChecklistItem(ChecklistItemType.check, 'item')],
    ),
  ],
  warnings: const [],
  sourceName: 'a.txt',
);

Future<void> _pumpHome(WidgetTester tester, {ChecklistDocument? doc}) async {
  final router = createRouter();
  final repository = FakeChecklistRepository(current: doc);
  addTearDown(router.dispose);
  addTearDown(repository.dispose);
  await tester.pumpWidget(
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
  const procedures = Key('home-card-procedures');
  const checklists = Key('home-card-checklists');
  const settings = Key('home-card-settings');

  testWidgets('Home has a card for each main feature', (tester) async {
    await _pumpHome(tester, doc: _doc);
    expect(find.byKey(procedures), findsOneWidget);
    expect(find.byKey(checklists), findsOneWidget);
    expect(find.byKey(settings), findsOneWidget);
    expect(find.text('2 checklists for this aircraft'), findsOneWidget);
  });

  testWidgets('Home shows the flight-simulation-only notice', (tester) async {
    await _pumpHome(tester, doc: _doc);
    expect(find.byKey(const Key('home-disclaimer')), findsOneWidget);
    expect(find.text(simOnlyDisclaimer), findsOneWidget);
    expect(find.text(appName), findsOneWidget);
  });

  testWidgets('Procedures is greyed out: Coming soon, nothing opens', (
    tester,
  ) async {
    await _pumpHome(tester, doc: _doc);
    expect(find.text('Coming soon'), findsOneWidget);
    await tester.tap(find.byKey(procedures));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('without a checklist the Checklists card is greyed out', (
    tester,
  ) async {
    await _pumpHome(tester);
    expect(find.textContaining('No checklist yet'), findsOneWidget);
    await tester.tap(find.byKey(checklists));
    await tester.pumpAndSettle();
    expect(find.byType(ChecklistListScreen), findsNothing);
  });

  testWidgets('the Checklists card opens the list', (tester) async {
    await _pumpHome(tester, doc: _doc);
    await tester.tap(find.byKey(checklists));
    await tester.pumpAndSettle();
    expect(find.byType(ChecklistListScreen), findsOneWidget);
  });

  testWidgets('the Settings card opens Settings', (tester) async {
    await _pumpHome(tester, doc: _doc);
    await tester.tap(find.byKey(settings));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('a loaded checklist alone does not leave Home', (tester) async {
    await _pumpHome(tester, doc: _doc);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(ChecklistListScreen), findsNothing);
  });
}
