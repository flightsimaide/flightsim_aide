import 'package:flightsim_aide/domain/models/checklist/checklist_colour.dart';
import 'package:flightsim_aide/domain/models/checklist/colour_run.dart';
import 'package:flightsim_aide/ui/checklist_detail/widgets/run_colours.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF000000);
const _palette = {
  'red': ChecklistColour('red', 0.6, 0, 0),
  'pale': ChecklistColour('pale', 0.9, 0.9, 0.9),
};

void main() {
  group('readableRunColour', () {
    test('a readable colour is returned as-is', () {
      final c = readableRunColour(
        name: 'red',
        palette: _palette,
        background: _white,
      );
      expect(c, const Color.fromARGB(255, 153, 0, 0));
    });

    test('null name means the default colour', () {
      expect(
        readableRunColour(name: null, palette: _palette, background: _white),
        isNull,
      );
    });

    test('an undefined name means the default colour', () {
      expect(
        readableRunColour(name: 'ghost', palette: _palette, background: _white),
        isNull,
      );
    });

    test('a pale colour falls back on a light background', () {
      expect(
        readableRunColour(name: 'pale', palette: _palette, background: _white),
        isNull,
      );
    });

    test('the same pale colour is kept on a dark background', () {
      expect(
        readableRunColour(name: 'pale', palette: _palette, background: _black),
        isNotNull,
      );
    });
  });

  group('contrastRatio', () {
    test('black on white is 21', () {
      expect(contrastRatio(_black, _white), closeTo(21, 0.01));
    });

    test('is symmetric', () {
      expect(contrastRatio(_white, _black), contrastRatio(_black, _white));
    });
  });

  group('runSpans', () {
    test('keeps text and order, colouring only readable runs', () {
      final spans = runSpans(
        const [ColourRun('a', 'red'), ColourRun('b'), ColourRun('c', 'pale')],
        _palette,
        _white,
      );
      expect(spans.map((s) => s.text), ['a', 'b', 'c']);
      expect(spans[0].style?.color, isNotNull);
      expect(spans[1].style, isNull);
      expect(spans[2].style, isNull);
    });
  });
}
