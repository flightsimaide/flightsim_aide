import 'dart:io';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository_impl.dart';
import 'package:flightsim_aide/data/services/checklist/model/raw_checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/checklist_detail_screen.dart';
import 'package:flightsim_aide/ui/checklist_list/widgets/checklist_list_screen.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flightsim_aide/utils/text_decoding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../testing/fakes/services/fake_checklist_source_service.dart';

// AC-4: dataref text (`sim/...` and the `:` that introduces it) never reaches
// the screen. The expected labels and results are the parser output that
// testing/fixtures/EXPECTED.md pins down.

Future<ChecklistRepository> _load(String fixture) async {
  final bytes = File('testing/fixtures/$fixture.txt').readAsBytesSync();
  final repository = ChecklistRepositoryImpl(
    source: FakeChecklistSourceService(
      Ok(
        RawChecklistDocument(
          name: '$fixture.txt',
          text: decodeChecklistText(bytes),
        ),
      ),
    ),
    parser: const AircraftWorkflowParser(),
  );
  final result = await repository.load();
  expect(result.isOk, isTrue);
  return repository;
}

List<String> _visibleTexts(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    text.data ?? text.textSpan?.toPlainText() ?? '',
];

void main() {
  for (final fixture in ['messy', 'lookalike_aircraft']) {
    testWidgets('$fixture: no dataref text on the list or any detail screen', (
      tester,
    ) async {
      final checklistRepository = await _load(fixture);
      final document = checklistRepository.current!;
      final progress = ChecklistProgressRepositoryImpl();
      addTearDown(progress.dispose);
      tester.view.physicalSize = const Size(800, 40000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Future<void> pumpScreen(Widget screen) => tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<ChecklistRepository>.value(
              value: checklistRepository,
            ),
            RepositoryProvider<ChecklistProgressRepository>.value(
              value: progress,
            ),
          ],
          child: MaterialApp(home: screen),
        ),
      );

      // Texts that legitimately contain ':' because the parsed label, result
      // or title does.
      final oracleColon = <String>{
        for (final c in document.checklists) ...[
          c.title,
          for (final item in c.items) ...[item.label, item.result],
        ],
      }..removeWhere((s) => !s.contains(':'));

      void expectNoDataref(List<String> texts) {
        for (final t in texts) {
          expect(t, isNot(contains('sim/')), reason: 'dataref in "$t"');
          if (t.contains(':')) {
            expect(oracleColon, contains(t), reason: 'stray ":" in "$t"');
          }
        }
      }

      await pumpScreen(const ChecklistListScreen());
      expect(find.textContaining('sim/'), findsNothing);
      final listTexts = _visibleTexts(tester);
      expectNoDataref(listTexts);
      for (final c in document.checklists) {
        expect(listTexts, contains(c.title));
      }

      for (final checklist in document.checklists) {
        await pumpScreen(
          ChecklistDetailScreen(
            key: ValueKey(checklist.name),
            checklistName: checklist.name,
          ),
        );
        final texts = _visibleTexts(tester);
        expectNoDataref(texts);
        expect(find.textContaining('sim/'), findsNothing);
        for (final item in checklist.items) {
          if (item.label.isNotEmpty) expect(texts, contains(item.label));
          if (item.result.isNotEmpty) {
            // Check rows show the result in capitals (task 0.21).
            expect(
              texts,
              contains(
                item.type == ChecklistItemType.check
                    ? item.result.toUpperCase()
                    : item.result,
              ),
            );
          }
        }
      }
    });
  }
}
