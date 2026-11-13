import 'dart:async';

import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/routing/router.dart';
import 'package:flightsim_aide/routing/routes.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_detail_screen.dart';
import 'package:flightsim_aide/ui/checklist_list/widgets/checklist_list_screen.dart';
import 'package:flightsim_aide/ui/core/widgets/app_navigation_bar.dart';
import 'package:flightsim_aide/ui/home/widgets/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../../../testing/fakes/repositories/fake_checklist_repository.dart';

final _doc = ChecklistDocument(
  checklists: [
    Checklist(
      name: 'a',
      title: 'A',
      items: [const ChecklistItem(ChecklistItemType.check, 'item')],
    ),
  ],
  warnings: const [],
  sourceName: 'cessna.txt',
);

Future<GoRouter> _pumpHome(
  WidgetTester tester, {
  ChecklistDocument? doc,
}) async {
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
  return router;
}

/// A bar label; the home page cards repeat some of the same words.
Finder _inBar(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

bool _enabled(WidgetTester tester, String label) {
  final index = ['Home', 'Procedures', 'Checklists', 'Settings'].indexOf(label);
  return tester
      .widgetList<NavigationDestination>(find.byType(NavigationDestination))
      .toList()[index]
      .enabled;
}

void main() {
  testWidgets('shows the four entries; Home is selected', (tester) async {
    await _pumpHome(tester);
    for (final label in ['Home', 'Procedures', 'Checklists', 'Settings']) {
      expect(_inBar(label), findsOneWidget);
    }
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
  });

  testWidgets('Procedures is disabled, Settings is enabled', (tester) async {
    await _pumpHome(tester, doc: _doc);
    expect(_enabled(tester, 'Procedures'), isFalse);
    expect(_enabled(tester, 'Settings'), isTrue);
  });

  testWidgets('Checklists is disabled until a checklist is loaded', (
    tester,
  ) async {
    await _pumpHome(tester);
    expect(_enabled(tester, 'Checklists'), isFalse);
    await tester.tap(_inBar('Checklists'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Checklists opens the list when a checklist is loaded', (
    tester,
  ) async {
    await _pumpHome(tester, doc: _doc);
    expect(_enabled(tester, 'Checklists'), isTrue);
    await tester.tap(_inBar('Checklists'));
    await tester.pumpAndSettle();
    expect(find.byType(ChecklistListScreen), findsOneWidget);
  });

  int selected(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  testWidgets(
    'the bar stays on the list and detail pages, marking Checklists',
    (tester) async {
      final router = await _pumpHome(tester, doc: _doc);
      await tester.tap(_inBar('Checklists'));
      await tester.pumpAndSettle();
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(selected(tester), 2);
      unawaited(router.push(Routes.detailPath('a')));
      await tester.pumpAndSettle();
      expect(find.byType(ChecklistDetailScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(selected(tester), 2);
    },
  );

  testWidgets(
    'Home on another page goes home; Checklists on a detail goes back',
    (tester) async {
      final router = await _pumpHome(tester, doc: _doc);
      await tester.tap(_inBar('Checklists'));
      await tester.pumpAndSettle();
      unawaited(router.push(Routes.detailPath('a')));
      await tester.pumpAndSettle();
      await tester.tap(_inBar('Checklists'));
      await tester.pumpAndSettle();
      expect(find.byType(ChecklistDetailScreen), findsNothing);
      expect(find.byType(ChecklistListScreen), findsOneWidget);
      await tester.tap(_inBar('Home'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(selected(tester), 0);
    },
  );

  testWidgets('a tap anywhere in an entry counts, not only on the icon', (
    tester,
  ) async {
    await _pumpHome(tester, doc: _doc);
    final cell = find.byType(NavigationDestination).at(2);
    final rect = tester.getRect(cell);
    final icon = tester.getRect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.checklist),
      ),
    );
    final label = tester.getRect(_inBar('Checklists'));
    // Four spots of the cell that are neither icon nor label.
    final spots = [
      Offset(rect.left + 4, rect.top + 4),
      Offset(rect.right - 4, rect.bottom - 4),
      Offset(rect.left + 4, (icon.bottom + label.top) / 2),
      Offset(rect.right - 4, icon.center.dy),
    ];
    for (final spot in spots) {
      expect(icon.contains(spot) || label.contains(spot), isFalse);
      await _pumpHome(tester, doc: _doc);
      await tester.tapAt(spot);
      await tester.pumpAndSettle();
      expect(
        find.byType(ChecklistListScreen),
        findsOneWidget,
        reason: 'tap at $spot',
      );
    }
  });

  testWidgets('Home stays on the home page', (tester) async {
    await _pumpHome(tester, doc: _doc);
    await tester.tap(_inBar('Home'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('the bar calls back for Home, Checklists and Settings', (
    tester,
  ) async {
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppNavigationBar(
            selectedIndex: 0,
            checklistsEnabled: true,
            onHome: () => taps.add('home'),
            onChecklists: () => taps.add('checklists'),
            onSettings: () => taps.add('settings'),
          ),
        ),
      ),
    );
    for (final label in ['Procedures', 'Settings', 'Checklists', 'Home']) {
      await tester.tap(find.text(label));
    }
    expect(taps, ['settings', 'checklists', 'home']);
  });
}
