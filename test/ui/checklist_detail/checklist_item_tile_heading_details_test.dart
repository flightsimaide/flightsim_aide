import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_item_tile.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, ChecklistItem item) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ChecklistItemTile(item: item, checked: false, onTap: () {}),
          ),
        ),
      ),
    );

ChecklistItem _heading(ChecklistJustify j) => ChecklistItem(
  ChecklistItemType.heading,
  'Empennage',
  '',
  const [],
  const [],
  null,
  j,
);

void main() {
  group('heading', () {
    for (final (j, align) in [
      (ChecklistJustify.left, TextAlign.start),
      (ChecklistJustify.center, TextAlign.center),
      (ChecklistJustify.right, TextAlign.end),
    ]) {
      testWidgets('$j aligns the text', (tester) async {
        await _pump(tester, _heading(j));
        final text = tester.widget<Text>(find.text('Empennage'));
        expect(text.textAlign, align);
      });
    }

    testWidgets('has no marker', (tester) async {
      await _pump(tester, _heading(ChecklistJustify.center));
      expect(find.byType(ChecklistMarker), findsNothing);
    });
  });

  group('details', () {
    const item = ChecklistItem(
      ChecklistItemType.details,
      'Check lower lugs for condition.',
    );

    testWidgets('has no marker and is not tappable as a check', (tester) async {
      await _pump(tester, item);
      expect(find.text('Check lower lugs for condition.'), findsOneWidget);
      expect(find.byType(ChecklistMarker), findsNothing);
    });

    testWidgets('is indented to start under a check item label', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Column(
              children: [
                ChecklistItemTile(
                  item: const ChecklistItem(
                    ChecklistItemType.check,
                    'Cargo Door',
                    'CHECK',
                  ),
                  checked: false,
                  onTap: () {},
                ),
                ChecklistItemTile(item: item, checked: false, onTap: () {}),
              ],
            ),
          ),
        ),
      );
      final label = tester.getTopLeft(find.text('Cargo Door'));
      final details = tester.getTopLeft(
        find.text('Check lower lugs for condition.'),
      );
      expect(details.dy, greaterThan(label.dy));
      expect(details.dx, label.dx);
    });
  });
}
