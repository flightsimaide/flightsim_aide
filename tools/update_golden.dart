// Regenerates test/data/parsers/golden/lookalike_aircraft.json.
// Run from the project root: dart run tools/update_golden.dart
import 'dart:convert';
import 'dart:io';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';

import '../testing/checklist_json.dart';

void main() {
  final text = File('testing/fixtures/lookalike_aircraft.txt')
      .readAsStringSync();
  final doc = const AircraftWorkflowParser().parse(text);
  const encoder = JsonEncoder.withIndent('  ');
  File('test/data/parsers/golden/lookalike_aircraft.json')
      .writeAsStringSync('${encoder.convert(documentToJson(doc))}\n');
  stdout.writeln('wrote ${doc.checklists.length} checklists');
}
