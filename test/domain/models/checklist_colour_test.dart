import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_colour.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('equal colours are equal and share a hashCode', () {
    const a = ChecklistColour('white', 1, 1, 1);
    const b = ChecklistColour('white', 1, 1, 1);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('colours differing in name or any component are not equal', () {
    const base = ChecklistColour('white', 1, 1, 1);
    expect(base, isNot(const ChecklistColour('grey', 1, 1, 1)));
    expect(base, isNot(const ChecklistColour('white', 0, 1, 1)));
    expect(base, isNot(const ChecklistColour('white', 1, 0, 1)));
    expect(base, isNot(const ChecklistColour('white', 1, 1, 0)));
  });

  test('document palette is unmodifiable and part of equality', () {
    ChecklistDocument make(Map<String, ChecklistColour> colours) =>
        ChecklistDocument(
          checklists: <Checklist>[],
          warnings: const [],
          colours: colours,
        );
    const white = ChecklistColour('white', 1, 1, 1);
    final d = make({'white': white});
    expect(() => d.colours['x'] = white, throwsUnsupportedError);
    expect(d, make({'white': white}));
    expect(d.hashCode, make({'white': white}).hashCode);
    expect(d, isNot(make(const {})));
  });

  test('document without a palette has an empty one', () {
    final d = ChecklistDocument(checklists: const [], warnings: const []);
    expect(d.colours, isEmpty);
  });

  test('copyWith keeps the palette', () {
    const white = ChecklistColour('white', 1, 1, 1);
    final d = ChecklistDocument(
      checklists: const [],
      warnings: const [],
      colours: const {'white': white},
    );
    expect(d.copyWith(sourceName: 'x.txt').colours, d.colours);
  });
}
