import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/domain/models/checklist/attach_outcome.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_detail_screen.dart';
import 'package:flightsim_aide/ui/checklist_list/widgets/checklist_list_screen.dart';
import 'package:flightsim_aide/ui/home/cubit/home_cubit.dart';
import 'package:flightsim_aide/ui/home/widgets/home_screen.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../../testing/fakes/repositories/fake_checklist_repository.dart';
import '../../../testing/open_checklist.dart';

final _doc = ChecklistDocument(
  checklists: [
    Checklist(
      name: 'Taxi',
      title: 'Taxi',
      items: const [ChecklistItem(ChecklistItemType.check, 'Lights')],
    ),
    Checklist(
      name: 'A/B c',
      title: 'Odd name',
      items: const [ChecklistItem(ChecklistItemType.check, 'Flaps')],
    ),
  ],
  warnings: const [],
  sourceName: 'a.txt',
);

void main() {
  late FakeChecklistRepository checklists;
  late FakeChecklistProgressRepository progress;
  late GoRouter router;

  Future<void> pumpHome(WidgetTester tester, AttachOutcome? outcome) async {
    checklists = FakeChecklistRepository(loadResults: [Ok(_doc)]);
    progress = FakeChecklistProgressRepository()..forcedOutcome = outcome;
    router = createRouter();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ChecklistRepository>.value(value: checklists),
          RepositoryProvider<ChecklistProgressRepository>.value(
            value: progress,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await openChecklist(tester);
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    await checklists.dispose();
  }

  group('restore popup', () {
    testWidgets('dialog shows both buttons', (tester) async {
      await pumpHome(tester, const AttachNeedsPrompt());
      expect(find.text('Use saved progress'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      expect(find.byType(ChecklistListScreen), findsNothing);
      await finish(tester);
    });

    testWidgets('use saved restores the marks and opens the list', (
      tester,
    ) async {
      await pumpHome(tester, const AttachNeedsPrompt());
      await tester.tap(find.text('Use saved progress'));
      await tester.pumpAndSettle();
      expect(progress.promptAnswers, [true]);
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      await finish(tester);
    });

    testWidgets('reset clears and stays on Home', (tester) async {
      await pumpHome(tester, const AttachNeedsPrompt());
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(progress.promptAnswers, [false]);
      expect(find.byType(ChecklistListScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      await finish(tester);
    });

    testWidgets('dialog cannot be dismissed by tapping outside', (
      tester,
    ) async {
      await pumpHome(tester, const AttachNeedsPrompt());
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.text('Use saved progress'), findsOneWidget);
      expect(progress.promptAnswers, isEmpty);
      await finish(tester);
    });

    testWidgets('answer after the widget is disposed does not throw', (
      tester,
    ) async {
      await pumpHome(tester, const AttachNeedsPrompt());
      final cubit = tester
          .element(find.byType(HomeScreen, skipOffstage: false))
          .read<HomeCubit>();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => cubit.answerPrompt(useSaved: true));
      expect(tester.takeException(), isNull);
      router.dispose();
      await checklists.dispose();
    });
  });

  group('last viewed checklist', () {
    Future<void> useSaved(WidgetTester tester, String lastViewed) async {
      await pumpHome(tester, const AttachNeedsPrompt());
      progress.setLastViewed(lastViewed);
      await tester.tap(find.text('Use saved progress'));
      await tester.pumpAndSettle();
    }

    testWidgets('using the saved progress reopens the last viewed checklist', (
      tester,
    ) async {
      await useSaved(tester, 'Taxi');
      expect(find.byType(ChecklistDetailScreen), findsOneWidget);
      expect(
        tester
            .widget<ChecklistDetailScreen>(find.byType(ChecklistDetailScreen))
            .checklistName,
        'Taxi',
      );
      await finish(tester);
    });

    testWidgets('missing last viewed name falls back to the list', (
      tester,
    ) async {
      await useSaved(tester, 'Gone');
      expect(find.byType(ChecklistDetailScreen), findsNothing);
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      await finish(tester);
    });

    testWidgets('back navigation from the reopened checklist lands on the '
        'list, then home', (tester) async {
      await useSaved(tester, 'Taxi');
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      await finish(tester);
    });

    testWidgets('names with spaces and slashes survive the route round trip', (
      tester,
    ) async {
      await useSaved(tester, 'A/B c');
      expect(
        tester
            .widget<ChecklistDetailScreen>(find.byType(ChecklistDetailScreen))
            .checklistName,
        'A/B c',
      );
      await finish(tester);
    });

    testWidgets('a silent restore stays on Home', (tester) async {
      await pumpHome(tester, const AttachRestored('Taxi'));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ChecklistListScreen), findsNothing);
      expect(find.byType(ChecklistDetailScreen), findsNothing);
      await finish(tester);
    });

    testWidgets('a clean load stays on Home; the Checklists card opens the '
        'list', (tester) async {
      await pumpHome(tester, const AttachClean());
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ChecklistListScreen), findsNothing);
      await tapChecklistsCard(tester);
      expect(find.byType(ChecklistDetailScreen), findsNothing);
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      await finish(tester);
    });
  });
}
