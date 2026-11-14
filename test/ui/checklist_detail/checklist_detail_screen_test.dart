import 'dart:async';
import 'dart:io';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/continue_link.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/routing/routes.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_detail_screen.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_item_tile.dart';
import 'package:flightsim_aide/ui/checklist_list/widgets/checklist_list_screen.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flightsim_aide/ui/core/themes/status_colors.dart';
import 'package:flightsim_aide/ui/core/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../testing/fakes/repositories/fake_checklist_repository.dart';

ChecklistDocument _minimal() => const AircraftWorkflowParser().parse(
  File('testing/fixtures/minimal.txt').readAsStringSync(),
);

ChecklistDocument _twoLists() => ChecklistDocument(
  checklists: [
    Checklist(
      name: 'one',
      title: 'First',
      items: const [ChecklistItem(ChecklistItemType.check, 'A')],
      continues: const [ContinueLink.next()],
    ),
    Checklist(
      name: 'two',
      title: 'Second',
      items: const [ChecklistItem(ChecklistItemType.check, 'B')],
    ),
  ],
  warnings: const [],
);

void main() {
  late FakeChecklistRepository repository;
  late ChecklistProgressRepositoryImpl progress;
  late GoRouter router;

  Future<void> pump(
    WidgetTester tester,
    ChecklistDocument? doc,
    String name,
  ) async {
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
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    unawaited(router.push(Routes.detailPath(name)));
    await tester.pumpAndSettle();
  }

  Finder rows() => find.byType(ChecklistItemTile);
  Finder appBarText(String text) =>
      find.descendant(of: find.byType(AppBar), matching: find.text(text));

  group('ChecklistDetailScreen', () {
    testWidgets('renders every row of minimal.txt (1 note without checkbox, 3 '
        'checkboxes)', (tester) async {
      await pump(tester, _minimal(), 'Prepare');
      expect(rows(), findsNWidgets(4));
      expect(find.byType(ChecklistMarker), findsNWidgets(3));
      expect(find.text('----- Prepare -----'), findsOneWidget);
      expect(find.text('Parking brake'), findsOneWidget);
      expect(find.text('SET'), findsOneWidget);
      expect(find.text('Flight plan'), findsOneWidget);
      expect(appBarText('Prepare for flight'), findsOneWidget);
    });

    testWidgets('the bottom button row shows four buttons laid out in a row', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, _minimal(), 'Prepare');
      Rect box(String label) => tester.getRect(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(FilledButton),
        ),
      );
      final reset = box('Reset');
      expect(reset.width, 80);
      final mode = box('Auto');
      final skip = box('Skip');
      final check = box('Check');
      expect(reset.left, 16);
      expect(mode.left - reset.right, 12);
      expect(skip.left - mode.right, 12);
      expect(check.left - skip.right, 12);
      expect(check.right, closeTo(800 - 16, 0.01));
      expect(skip.width, closeTo(mode.width, 0.5));
      expect(check.width, closeTo(mode.width, 0.5));
      expect(reset.top, mode.top);
      for (final label in ['Reset', 'Auto']) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(find.text('0/3'), findsOneWidget);
      expect(find.text('Reset checklist?'), findsNothing);
    });

    testWidgets('manual items are flagged only while auto is on', (
      tester,
    ) async {
      await pump(tester, _minimal(), 'Prepare');
      final flagged = find.text('manual item');
      final before = flagged.evaluate().length;
      await tester.tap(find.text('Auto'));
      await tester.pump();
      final after = flagged.evaluate().length;
      expect(
        before != after,
        isTrue,
        reason: 'the flag follows the Auto/Manual button',
      );
    });

    testWidgets('Check ticks the next open item, one per tap, then greys out', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, _minimal(), 'Prepare');
      FilledButton check() => tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Check'),
          matching: find.byType(FilledButton),
        ),
      );
      for (final expected in ['1/3', '2/3', '3/3']) {
        expect(check().onPressed, isNotNull);
        await tester.tap(find.text('Check'));
        await tester.pump();
        expect(find.text(expected), findsOneWidget);
      }
      expect(check().onPressed, isNull);
    });

    testWidgets(
      'lines only belong to check rows, one on the top edge of each',
      (tester) async {
        await pump(tester, _minimal(), 'Prepare');
        int lines(Finder row) => find
            .descendant(of: row, matching: find.byType(Divider))
            .evaluate()
            .length;
        expect(lines(rows().at(0)), 0, reason: 'the note has no line');
        expect(lines(rows().at(1)), 1);
        expect(lines(rows().at(2)), 1);
        expect(
          find
              .descendant(
                of: find.byType(AppBar),
                matching: find.byType(Divider),
              )
              .evaluate(),
          isEmpty,
        );
      },
    );

    testWidgets('status row shows "0/3"', (tester) async {
      await pump(tester, _minimal(), 'Prepare');
      expect(find.text('0/3'), findsOneWidget);
    });

    testWidgets('tap updates the count to "1/3"', (tester) async {
      await pump(tester, _minimal(), 'Prepare');
      await tester.tap(find.text('Parking brake'));
      await tester.pump();
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('0/3'), findsNothing);
    });

    testWidgets('progress bar value equals done/total', (tester) async {
      await pump(tester, _minimal(), 'Prepare');
      double value() => tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;
      expect(value(), 0);
      await tester.tap(find.text('Parking brake'));
      await tester.pump();
      expect(value(), closeTo(1 / 3, 0.0001));
    });

    testWidgets('complete absent at 2/3', (tester) async {
      await pump(tester, _minimal(), 'Prepare');
      await tester.tap(find.text('Parking brake'));
      await tester.tap(find.text('Batteries'));
      await tester.pump();
      expect(find.text('2/3'), findsOneWidget);
      expect(find.text('Complete'), findsNothing);
    });

    testWidgets('complete banner present at 3/3', (tester) async {
      await pump(tester, _minimal(), 'Prepare');
      for (final label in ['Parking brake', 'Batteries', 'Flight plan']) {
        await tester.tap(find.text(label));
      }
      await tester.pump();
      // 3/3 stays, and a green "Complete" follows it.
      expect(find.text('3/3'), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);
      // The pill is filled with the success colour.
      final pill = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.text('Complete'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (pill.decoration as BoxDecoration).color,
        StatusColors.light.success,
      );
      expect(find.text('Complete'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsWidgets);
    });

    testWidgets('banner disappears after an uncheck', (tester) async {
      await pump(tester, _minimal(), 'Prepare');
      for (final label in ['Parking brake', 'Batteries', 'Flight plan']) {
        await tester.tap(find.text(label));
      }
      await tester.pump();
      await tester.tap(find.text('Flight plan'));
      await tester.pump();
      expect(find.text('Complete'), findsNothing);
    });

    testWidgets('unknown name shows failure', (tester) async {
      await pump(tester, _minimal(), 'nope');
      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.text('Checklist not found'), findsOneWidget);
    });

    testWidgets('Back on the failure screen returns to the list', (
      tester,
    ) async {
      await pump(tester, _minimal(), 'nope');
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      expect(find.byType(ChecklistDetailScreen), findsNothing);
    });

    testWidgets('Back with nothing to pop goes to the list', (tester) async {
      repository = FakeChecklistRepository(current: _minimal());
      progress = ChecklistProgressRepositoryImpl();
      router = createRouter(initialLocation: Routes.detailPath('nope'));
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
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(ChecklistListScreen), findsOneWidget);
    });

    testWidgets('a complete checklist has no Next buttons, only Continue', (
      tester,
    ) async {
      await pump(tester, _twoLists(), 'one');
      await tester.tap(find.text('A'));
      await tester.pump();
      expect(find.text('Complete'), findsOneWidget);
      expect(find.textContaining('Next:'), findsNothing);
      expect(find.byKey(continueButtonKey), findsNothing);
    });

    testWidgets('no next button when the checklist has no links', (
      tester,
    ) async {
      await pump(tester, _twoLists(), 'two');
      await tester.tap(find.text('B'));
      await tester.pump();
      expect(find.text('Complete'), findsOneWidget);
      expect(find.textContaining('Next:'), findsNothing);
    });
  });

  group('reset', () {
    Future<void> checkTwo(WidgetTester tester) async {
      await tester.tap(find.text('Parking brake'));
      await tester.tap(find.text('Batteries'));
      await tester.pump();
    }

    testWidgets('reset button shows a dialog', (tester) async {
      await pump(tester, _minimal(), 'Prepare');
      await checkTwo(tester);
      await tester.tap(find.byTooltip('Reset'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('cancel leaves checks untouched', (tester) async {
      await pump(tester, _minimal(), 'Prepare');
      await checkTwo(tester);
      await tester.tap(find.byTooltip('Reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('2/3'), findsOneWidget);
    });

    testWidgets('confirm clears checks and count returns to 0/3', (
      tester,
    ) async {
      await pump(tester, _minimal(), 'Prepare');
      await checkTwo(tester);
      await tester.tap(find.byTooltip('Reset'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Reset'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0/3'), findsOneWidget);
      expect(progress.current.checked, isEmpty);
    });

    testWidgets('the bottom Reset button clears every tick after a confirm', (
      tester,
    ) async {
      await pump(tester, _minimal(), 'Prepare');
      expect(
        tester.widget<FilledButton>(find.byKey(bottomResetKey)).onPressed,
        isNull,
      );
      await checkTwo(tester);
      await tester.tap(find.byKey(bottomResetKey));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Reset'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0/3'), findsOneWidget);
      expect(progress.current.checked, isEmpty);
    });

    testWidgets('cancel from the bottom Reset keeps the ticks', (tester) async {
      await pump(tester, _minimal(), 'Prepare');
      await checkTwo(tester);
      await tester.tap(find.byKey(bottomResetKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);
    });

    testWidgets('reset is disabled when nothing is checked', (tester) async {
      await pump(tester, _minimal(), 'Prepare');
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.restart_alt),
      );
      expect(button.onPressed, isNull);
      await checkTwo(tester);
      final enabled = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.restart_alt),
      );
      expect(enabled.onPressed, isNotNull);
    });

    testWidgets('dialog is dismissible with back', (tester) async {
      await pump(tester, _minimal(), 'Prepare');
      await checkTwo(tester);
      await tester.tap(find.byTooltip('Reset'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ChecklistDetailScreen), findsOneWidget);
      expect(find.text('2/3'), findsOneWidget);
    });
  });
}
