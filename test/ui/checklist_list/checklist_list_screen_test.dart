import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/routing/routes.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_detail_screen.dart';
import 'package:flightsim_aide/ui/checklist_list/widgets/checklist_list_tile.dart';
import 'package:flightsim_aide/ui/core/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../testing/fakes/repositories/fake_checklist_repository.dart';

Checklist _list(String name, int checks) => Checklist(
  name: name,
  title: 'Title $name',
  items: [
    for (var i = 0; i < checks; i++)
      const ChecklistItem(ChecklistItemType.check, 'item'),
  ],
);

ChecklistDocument _doc({
  List<String> warnings = const [],
  List<Checklist>? checklists,
}) => ChecklistDocument(
  checklists: checklists ?? [_list('a', 2), _list('b', 1), _list('c', 3)],
  warnings: warnings,
  sourceName: 'cessna.txt',
);

List<String> _warnings(int n) => [for (var i = 1; i <= n; i++) 'Line $i: bad'];

void main() {
  late FakeChecklistRepository repository;
  late ChecklistProgressRepositoryImpl progress;
  late GoRouter router;

  Future<void> pump(WidgetTester tester, ChecklistDocument? doc) async {
    repository = FakeChecklistRepository(current: doc);
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
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  group('ChecklistListScreen', () {
    testWidgets('one tile per checklist', (tester) async {
      await pump(tester, _doc());
      expect(find.byType(ChecklistListTile), findsNWidgets(3));
      expect(find.text('Title a'), findsOneWidget);
      expect(find.text('0 / 2'), findsOneWidget);
    });

    testWidgets('source name in app bar', (tester) async {
      await pump(tester, _doc());
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('cessna.txt'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping a tile navigates to the encoded detail path', (
      tester,
    ) async {
      await pump(tester, _doc(checklists: [_list('Before Start / Taxi', 1)]));
      await tester.tap(find.byType(ChecklistListTile));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        Routes.detailPath('Before Start / Taxi'),
      );
      expect(
        tester
            .widget<ChecklistDetailScreen>(find.byType(ChecklistDetailScreen))
            .checklistName,
        'Before Start / Taxi',
      );
    });

    testWidgets('failure state shows ErrorBanner', (tester) async {
      await pump(tester, null);
      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.text('No checklist loaded'), findsOneWidget);
    });

    testWidgets('banner shows "3 lines were skipped" for 3 warnings', (
      tester,
    ) async {
      await pump(tester, _doc(warnings: _warnings(3)));
      expect(find.text('3 lines were skipped'), findsOneWidget);
    });

    testWidgets('no banner for 0 warnings', (tester) async {
      await pump(tester, _doc());
      expect(find.textContaining('skipped'), findsNothing);
    });

    testWidgets('dismiss hides the banner', (tester) async {
      await pump(tester, _doc(warnings: _warnings(3)));
      await tester.tap(find.text('Dismiss'));
      await tester.pump();
      expect(find.textContaining('skipped'), findsNothing);
      expect(find.byType(ChecklistListTile), findsNWidgets(3));
    });

    testWidgets('Details lists all warnings', (tester) async {
      await pump(tester, _doc(warnings: _warnings(3)));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      for (final w in _warnings(3)) {
        expect(find.text(w), findsOneWidget);
      }
    });

    testWidgets(
      'toggle via repository while list is mounted updates the tile text',
      (tester) async {
        await pump(tester, _doc());
        expect(find.text('0 / 2'), findsOneWidget);
        progress.toggle('a', 0);
        await tester.pump();
        expect(find.text('1 / 2'), findsOneWidget);
        expect(find.text('0 / 2'), findsNothing);
      },
    );

    testWidgets('counts refresh after returning from detail', (tester) async {
      await pump(tester, _doc());
      await tester.tap(find.text('Title a'));
      await tester.pumpAndSettle();
      progress.toggle('a', 0);
      progress.toggle('a', 1);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);
    });
  });
}
