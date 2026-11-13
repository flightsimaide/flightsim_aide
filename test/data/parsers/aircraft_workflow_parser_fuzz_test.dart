import 'dart:convert';
import 'dart:math';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/parser_invariants.dart';

const _seed = 1;
const _iterations = 2000;

const _keywords = [
  'sw_checklist',
  'sw_checklist',
  'sw_item',
  'sw_item_c',
  'sw_itemvoid',
  'sw_itemvoid_c',
  'sw_iteminfo',
  'sw_remark',
  'sw_continue',
  'SW_ITEM',
  'bogus',
];

const _endings = ['\n', '\n', '\r\n', '\r'];

const _pieces = [
  'sw_checklist',
  'sw_item',
  'sw_item_c',
  'sw_itemvoid',
  'sw_itemvoid_c',
  'sw_iteminfo',
  'sw_remark',
  'sw_continue',
  'SW_ITEM',
  'bogus',
  '|',
  ':',
  '@',
  '#',
  '\r',
  '\n',
  '\r\n',
  '\u00e9',
  '\u65e5\u672c',
  '\u{1F600}',
  '',
  ' ',
  '\uFEFF',
  'name',
  'A',
  '1',
];

String _randomPiece(Random random) {
  if (random.nextInt(60) == 0) return 'x' * 3000;
  return _pieces[random.nextInt(_pieces.length)];
}

/// Random pieces glued together, mostly on one line.
String _garbage(Random random) {
  final buffer = StringBuffer();
  for (var n = random.nextInt(40); n > 0; n--) {
    buffer.write(_randomPiece(random));
  }
  return buffer.toString();
}

/// Lines that start with a keyword so that real checklists form often.
String _structured(Random random) {
  final buffer = StringBuffer();
  for (var n = random.nextInt(15); n > 0; n--) {
    buffer
      ..write(_keywords[random.nextInt(_keywords.length)])
      ..write(':');
    for (var k = random.nextInt(4); k > 0; k--) {
      buffer.write(_randomPiece(random));
    }
    buffer.write(_endings[random.nextInt(_endings.length)]);
  }
  return buffer.toString();
}

String _randomInput(Random random) =>
    random.nextBool() ? _garbage(random) : _structured(random);

void main() {
  test('fuzz: parser never throws and keeps its invariants', () {
    final random = Random(_seed);
    var withChecklists = 0;
    for (var n = 0; n < _iterations; n++) {
      final input = _randomInput(random);
      try {
        final doc = const AircraftWorkflowParser().parse(input);
        if (doc.checklists.isNotEmpty) withChecklists++;
        expectParserInvariants(doc);
      } catch (e) {
        final shown = jsonEncode(
          input.length > 500 ? input.substring(0, 500) : input,
        );
        fail('seed=$_seed iteration=$n input=$shown error=$e');
      }
    }
    expect(
      withChecklists,
      greaterThan(200),
      reason: 'fuzz must hit checklists',
    );
  });
}
