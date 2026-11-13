import 'dart:io';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_sequence.dart';
import 'package:flightsim_aide/domain/models/checklist/shutdown_checklist.dart';
import 'package:flightsim_aide/utils/text_decoding.dart';
import 'package:flutter_test/flutter_test.dart';

Checklist c(String name) => Checklist(name: name, title: name, items: const []);

ChecklistDocument doc(List<Checklist> lists) =>
    ChecklistDocument(checklists: lists, warnings: const []);

void main() {
  test('returns the last checklist in file order', () {
    expect(shutdownChecklistOf(doc([c('A'), c('B'), c('C')]))!.name, 'C');
  });

  test('document with one checklist returns it', () {
    expect(shutdownChecklistOf(doc([c('A')]))!.name, 'A');
  });

  test('an empty document has none', () {
    expect(shutdownChecklistOf(doc([])), isNull);
  });

  test('used only through this function', () {
    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('shutdownChecklistOf('))
        .map((f) => f.path.replaceAll(r'\', '/'))
        .toList();
    expect(
      hits.where((p) => !p.endsWith('shutdown_checklist.dart')),
      everyElement(contains('data/repositories/')),
    );
  });

  test('on the fixtures: file order against flight order', () {
    const parser = AircraftWorkflowParser();
    for (final name in ['messy', 'minimal', 'lookalike_aircraft']) {
      final text = decodeChecklistText(
        File('testing/fixtures/$name.txt').readAsBytesSync(),
      );
      final document = parser.parse(text);
      final last = shutdownChecklistOf(document);
      if (document.checklists.isEmpty) {
        expect(last, isNull);
        continue;
      }
      final ordered = ChecklistSequence(document.checklists).ordered.last;
      // ignore: avoid_print
      print(
        '9.14 $name: file-last=${last!.name} | flight-last=${ordered.name}',
      );
    }
  });
}
