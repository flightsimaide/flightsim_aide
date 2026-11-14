import 'dart:io';

import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_item_tile.dart';
import 'package:flightsim_aide/ui/checklist_list/widgets/checklist_list_screen.dart';
import 'package:flightsim_aide/ui/checklist_list/widgets/checklist_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../testing/e2e_harness.dart';
import '../testing/open_checklist.dart';

/// Titles of the `lookalike_aircraft` checklists, read from the oracle table in
/// testing/fixtures/EXPECTED.md (rows `| n | line | `Title` | items | notes |`).
List<String> oracleTitles() {
  final lines = File('testing/fixtures/EXPECTED.md').readAsLinesSync();
  final start = lines.indexWhere((l) => l == '## `lookalike_aircraft.txt`');
  final row = RegExp(r'^\| \d+ \| \d+ \| `(.+)` \| \d+ \| \d+ \|$');
  return [
    for (final l in lines.skip(start))
      if (row.firstMatch(l) case final m?) m.group(1)!,
  ];
}

void main() {
  // AC-1: an aircraft file shows all of its checklists with correct titles.
  // AC-2: every item shows label and result.
  // AC-3: tapping toggles items; progress and reset work.
  testWidgets('open file, list, check two rows, back, reset', (tester) async {
    await pumpApp(tester, fixtureSource('lookalike_aircraft'));

    await openChecklist(tester);
    await tester.pumpAndSettle();
    await tapChecklistsCard(tester);

    // AC-1: every title from the oracle is on the list.
    final titles = oracleTitles();
    expect(titles, hasLength(7));
    final tiles = tester
        .widgetList<ChecklistListTile>(find.byType(ChecklistListTile))
        .toList();
    expect(tiles, hasLength(7));
    final listed = [for (final t in tiles) t.summary.title];
    expect(listed, unorderedEquals(titles));
    for (final title in titles) {
      expect(find.text(title), findsWidgets);
    }

    // Open the first tile (flight order, not file order) that has at least
    // three check items. The first checklist in the file has only one.
    final index = tiles.indexWhere((t) => t.summary.total >= 3);
    final first = tiles[index].summary;
    final total = first.total;
    expect(find.text('0 / $total'), findsWidgets);
    await tester.tap(find.byType(ChecklistListTile).at(index));
    await tester.pumpAndSettle();

    // AC-2: each row shows its label and its result.
    final checklist = repositoryOf(tester).current!.checklists
        .firstWhere((c) => c.name == first.name);
    for (final item in checklist.items) {
      if (item.label.isNotEmpty) {
        expect(find.text(item.label), findsWidgets, reason: item.label);
      }
      if (item.result.isNotEmpty) {
        expect(find.text(item.result), findsWidgets, reason: item.result);
      }
    }

    // AC-3: tap two check rows.
    final checkRows = find.byWidgetPredicate(
      (w) => w is ChecklistItemTile && w.item.type != ChecklistItemType.note,
    );
    await tester.tap(checkRows.at(0));
    await tester.pumpAndSettle();
    await tester.tap(checkRows.at(1));
    await tester.pumpAndSettle();
    expect(find.text('2/$total'), findsOneWidget);

    // Back to the list: the tile shows the progress.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ChecklistListScreen), findsOneWidget);
    expect(find.text('2 / $total'), findsOneWidget);

    // Open again, reset, confirm.
    await tester.tap(find.byType(ChecklistListTile).at(index));
    await tester.pumpAndSettle();
    expect(find.text('2/$total'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Reset'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0/$total'), findsOneWidget);
  });
}
