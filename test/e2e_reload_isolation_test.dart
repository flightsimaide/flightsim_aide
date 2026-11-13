import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_item_tile.dart';
import 'package:flightsim_aide/ui/checklist_list/widgets/checklist_list_tile.dart';
import 'package:flightsim_aide/ui/home/widgets/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../testing/e2e_harness.dart';
import '../testing/open_checklist.dart';

void main() {
  testWidgets('after reload every checklist shows 0 / 3', (tester) async {
    await pumpApp(tester, fixtureSource('minimal'));
    await openChecklist(tester);
    await tester.pumpAndSettle();
    await tapChecklistsCard(tester);

    await tester.tap(find.byType(ChecklistListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ChecklistItemTile).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ChecklistItemTile).at(2));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);

    // Back to the list, then back home.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);

    // Load the same file again: progress must not carry over (D-7).
    await openChecklist(tester);
    await tester.pumpAndSettle();
    await tapChecklistsCard(tester);
    final tiles = tester
        .widgetList<ChecklistListTile>(find.byType(ChecklistListTile))
        .toList();
    expect(tiles, isNotEmpty);
    for (final tile in tiles) {
      expect(tile.summary.done, 0);
      expect(tile.summary.total, 3);
    }
    expect(find.text('0 / 3'), findsNWidgets(tiles.length));
    expect(find.text('2 / 3'), findsNothing);
  });
}
