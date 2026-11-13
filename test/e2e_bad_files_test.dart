import 'package:flightsim_aide/ui/checklist_list/widgets/checklist_list_screen.dart';
import 'package:flightsim_aide/ui/core/widgets/error_banner.dart';
import 'package:flightsim_aide/ui/home/widgets/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../testing/e2e_harness.dart';
import '../testing/open_checklist.dart';

void main() {
  // AC-5: a malformed file never crashes the app, and the app reports what was
  // skipped.
  for (final (label, source) in [
    ('empty text', textSource('empty.txt', '')),
    ('random bytes', textSource('random.txt', randomBytesText())),
  ]) {
    testWidgets('$label: stays home with a readable error banner', (
      tester,
    ) async {
      await pumpApp(tester, source);
      await openChecklist(tester);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ChecklistListScreen), findsNothing);
      final banner = find.byType(ErrorBanner);
      expect(banner, findsOneWidget);
      final message = tester.widget<ErrorBanner>(banner).message;
      expect(message.trim(), isNotEmpty);
      expect(find.text(message), findsOneWidget);
    });
  }

  testWidgets('messy.txt: opens the list with a skipped-lines banner', (
    tester,
  ) async {
    await pumpApp(tester, fixtureSource('messy'));
    await openChecklist(tester);
    await tester.pumpAndSettle();
    await tapChecklistsCard(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(ChecklistListScreen), findsOneWidget);
    // EXPECTED.md: messy.txt has exactly ten warnings.
    expect(find.text('9 lines were skipped'), findsOneWidget);

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Skipped lines'), findsOneWidget);
    for (final warning in [
      'Line 1: item before any checklist',
      'Line 4: unrecognized line',
      'Line 11: unknown keyword "bogus_keyword"',
      'Line 22: continue target "Nowhere" not found',
    ]) {
      expect(find.text(warning), findsOneWidget, reason: warning);
    }
  });
}
