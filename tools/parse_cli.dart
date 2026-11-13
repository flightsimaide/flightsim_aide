// Prints what the parser makes of a checklist file.
// Run from the project root: dart run tools/parse_cli.dart <file>
import 'dart:io';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tools/parse_cli.dart <file>');
    exit(64);
  }
  final doc = const AircraftWorkflowParser().parse(
    File(args.single).readAsStringSync(),
  );
  var checks = 0;
  var notes = 0;
  for (final c in doc.checklists) {
    final cChecks = c.items.where((i) => i.type == ChecklistItemType.check);
    checks += cChecks.length;
    notes += c.items.length - cChecks.length;
    stdout.writeln('${c.title}: ${c.items.length} items');
  }
  for (final w in doc.warnings) {
    stdout.writeln('warning: $w');
  }
  final continues = doc.checklists.fold<int>(
    0,
    (sum, c) => sum + c.continues.length,
  );
  stdout.writeln(
    'TOTAL checklists=${doc.checklists.length} checks=$checks notes=$notes '
    'warnings=${doc.warnings.length} colours=${doc.colours.length} '
    'continues=$continues',
  );
}
