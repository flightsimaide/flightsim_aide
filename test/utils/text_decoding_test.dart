import 'dart:math';
import 'dart:typed_data';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/utils/text_decoding.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../testing/checklist_json.dart';

void main() {
  test('ASCII decodes', () {
    expect(decodeChecklistText(Uint8List.fromList('abc'.codeUnits)), 'abc');
  });

  test('UTF-8 with accents decodes', () {
    expect(decodeChecklistText(Uint8List.fromList([0xC3, 0xA9])), 'é');
  });

  test('a lone 0xE9 falls back to Latin-1 and gives é', () {
    expect(decodeChecklistText(Uint8List.fromList([0xE9])), 'é');
  });

  test('empty bytes give empty string', () {
    expect(decodeChecklistText(Uint8List(0)), '');
  });

  test('BOM bytes are preserved', () {
    final text = decodeChecklistText(
      Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x41]),
    );
    expect(text, '﻿A');
  });

  test('UTF-8 BOM file parses through the parser to the same document', () {
    const body = 'sw_checklist:A:A\nsw_item:Gear|DOWN\n';
    final plain = decodeChecklistText(Uint8List.fromList(body.codeUnits));
    final bom = decodeChecklistText(
      Uint8List.fromList([0xEF, 0xBB, 0xBF, ...body.codeUnits]),
    );
    const parser = AircraftWorkflowParser();
    expect(
      documentToJson(parser.parse(bom)),
      documentToJson(parser.parse(plain)),
    );
  });

  test('random binary bytes never throw', () {
    final random = Random(42);
    for (var i = 0; i < 500; i++) {
      final bytes = Uint8List.fromList(
        List.generate(random.nextInt(64), (_) => random.nextInt(256)),
      );
      expect(() => decodeChecklistText(bytes), returnsNormally);
    }
  });
}
