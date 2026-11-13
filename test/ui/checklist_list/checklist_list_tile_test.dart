import 'package:flightsim_aide/ui/checklist_list/cubit/checklist_list_state.dart';
import 'package:flightsim_aide/ui/checklist_list/widgets/checklist_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ChecklistSummary _summary({
  String title = 'Prepare for flight',
  int done = 4,
  int total = 9,
  bool isComplete = false,
}) => ChecklistSummary(
  name: 'prep',
  title: title,
  done: done,
  total: total,
  isComplete: isComplete,
);

Future<void> _pump(
  WidgetTester tester,
  ChecklistSummary summary, {
  VoidCallback? onTap,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ChecklistListTile(summary: summary, onTap: onTap ?? () {}),
    ),
  ),
);

void main() {
  group('ChecklistListTile', () {
    testWidgets('shows title', (tester) async {
      await _pump(tester, _summary());
      expect(find.text('Prepare for flight'), findsOneWidget);
    });

    testWidgets('shows "4 / 9"', (tester) async {
      await _pump(tester, _summary());
      expect(find.text('4 / 9'), findsOneWidget);
    });

    testWidgets('complete tile shows icon and word', (tester) async {
      await _pump(tester, _summary(done: 9, isComplete: true));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);
    });

    testWidgets('incomplete tile does not', (tester) async {
      await _pump(tester, _summary());
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.text('Complete'), findsNothing);
    });

    testWidgets('height at least 48', (tester) async {
      await _pump(tester, _summary(title: 'A', done: 0, total: 1));
      expect(
        tester.getSize(find.byType(ChecklistListTile)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('semantics label matches', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _summary());
      expect(
        find.bySemanticsLabel('Prepare for flight, 4 of 9 complete'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('tap calls the callback', (tester) async {
      var taps = 0;
      await _pump(tester, _summary(), onTap: () => taps++);
      await tester.tap(find.byType(ChecklistListTile));
      expect(taps, 1);
    });

    testWidgets('very long title wraps without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pump(tester, _summary(title: 'Very long title ' * 30));
      expect(tester.takeException(), isNull);
    });
  });
}
