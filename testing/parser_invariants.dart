import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/colour_run.dart';
import 'package:flutter_test/flutter_test.dart';

final _colourMarker = RegExp(r'\\[^\\:|]+\\');
final _warningFormat = RegExp(r'^(Line \d+: .+|No checklists found)$');

/// Asserts the properties every parsed [doc] must have, whatever the input.
void expectParserInvariants(ChecklistDocument doc) {
  final names = doc.checklists.map((c) => c.name).toList();
  expect(names.toSet().length, names.length, reason: 'unique names');
  for (final w in doc.warnings) {
    expect(w, matches(_warningFormat));
  }
  for (var index = 0; index < doc.checklists.length; index++) {
    final c = doc.checklists[index];
    expect(c.items, isNotEmpty, reason: c.name);
    expect(c.title, isNotEmpty, reason: c.name);
    for (final link in c.continues) {
      if (link.isNext) {
        expect(
          index,
          lessThan(doc.checklists.length - 1),
          reason: 'a kept bare continue in "${c.name}" has a next checklist',
        );
      } else {
        expect(names, contains(link.target), reason: 'continue in "${c.name}"');
      }
    }
    for (final i in c.items) {
      if (i.type == ChecklistItemType.check) {
        expect(i.label, isNotEmpty);
        expect(i.result, isNot(contains(':')));
      }
      for (final t in [i.label, i.result]) {
        expect(t, isNot(contains('sim/')));
        expect(_colourMarker.hasMatch(t), isFalse, reason: t);
      }
      _expectRuns(doc, i.label, i.labelRuns, i.labelParts);
      _expectRuns(doc, i.result, i.resultRuns, i.resultParts);
    }
  }
}

/// Runs join to the plain text, are never empty, never repeat a colour next
/// to each other, and name a defined colour or have an `unknown colour` warning.
void _expectRuns(
  ChecklistDocument doc,
  String text,
  List<ColourRun> runs,
  List<ColourRun> parts,
) {
  expect(parts.map((r) => r.text).join(), text, reason: 'runs join to text');
  for (var n = 0; n < runs.length; n++) {
    expect(runs[n].text, isNotEmpty);
    if (n > 0) expect(runs[n].colour, isNot(runs[n - 1].colour));
    final colour = runs[n].colour;
    if (colour != null && !doc.colours.containsKey(colour)) {
      expect(
        doc.warnings.any((w) => w.endsWith('unknown colour "$colour"')),
        isTrue,
        reason: 'colour "$colour" is defined or reported',
      );
    }
  }
}
