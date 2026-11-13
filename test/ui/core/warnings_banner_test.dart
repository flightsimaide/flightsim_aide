import 'package:flightsim_aide/ui/core/widgets/warnings_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

List<String> _warnings(int n) => [
  for (var i = 1; i <= n; i++) 'Line $i: unrecognised directive',
];

void main() {
  group('WarningsBanner', () {
    testWidgets('plural text for 3', (tester) async {
      await tester.pumpWidget(
        _wrap(WarningsBanner(warnings: _warnings(3), onDismiss: () {})),
      );
      expect(find.text('3 lines were skipped'), findsOneWidget);
    });

    testWidgets('singular text for 1', (tester) async {
      await tester.pumpWidget(
        _wrap(WarningsBanner(warnings: _warnings(1), onDismiss: () {})),
      );
      expect(find.text('1 line was skipped'), findsOneWidget);
    });

    testWidgets('hidden when 0', (tester) async {
      await tester.pumpWidget(
        _wrap(WarningsBanner(warnings: const [], onDismiss: () {})),
      );
      expect(find.text('Details'), findsNothing);
      expect(find.text('Dismiss'), findsNothing);
      expect(find.textContaining('skipped'), findsNothing);
    });

    testWidgets('Details shows all warnings in a dialog', (tester) async {
      await tester.pumpWidget(
        _wrap(WarningsBanner(warnings: _warnings(3), onDismiss: () {})),
      );
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      for (final w in _warnings(3)) {
        expect(find.text(w), findsOneWidget);
      }
    });

    testWidgets('dialog list scrolls with 200 warnings and no overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(WarningsBanner(warnings: _warnings(200), onDismiss: () {})),
      );
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final last = find.text('Line 200: unrecognised directive');
      await tester.dragUntilVisible(
        last,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Scrollable),
        ),
        const Offset(0, -300),
      );
      expect(last, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Dismiss calls callback', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _wrap(WarningsBanner(warnings: _warnings(2), onDismiss: () => calls++)),
      );
      await tester.tap(find.text('Dismiss'));
      expect(calls, 1);
    });
  });
}
