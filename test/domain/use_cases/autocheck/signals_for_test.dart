import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/flight_sim/dataref.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/signals_for.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../testing/fixtures/condition_fixtures.dart';

Checklist _parse(String text, [int index = 0]) =>
    const AircraftWorkflowParser().parse(text).checklists[index];

void main() {
  test('a checklist with no conditions needs nothing', () {
    expect(
      signalsFor(_parse('sw_checklist:A\nsw_item:one|OK\nsw_item:two|OK')),
      isEmpty,
    );
  });

  test('item and continue conditions, each once, in order', () {
    final c = _parse(
      'sw_checklist:A\n'
      'sw_item:one|OK:b/x:1\n'
      'sw_item:two|OK:a/y:1&&b/x:2\n'
      'sw_item:three|OK:c/z[2]:5\n'
      'sw_continue:B:d/w:1\n'
      'sw_checklist:B\n'
      'sw_item:four|OK',
    );
    expect(signalsFor(c), [
      const Dataref('b/x'),
      const Dataref('a/y'),
      const Dataref('c/z', 2),
      const Dataref('d/w'),
    ]);
  });

  test('right-side datarefs count', () {
    final c = _parse('sw_checklist:A\nsw_item:one|OK:a/x:>{a/y}');
    expect(signalsFor(c), [const Dataref('a/x'), const Dataref('a/y')]);
  });

  test('a note with a condition is not an input', () {
    final c = _parse('sw_checklist:A\nsw_iteminfo:info:a/x:1\nsw_item:one|OK');
    expect(c.items.first.type, ChecklistItemType.note);
    expect(signalsFor(c), isEmpty);
  });

  test('matches the condition fixtures: every fixture checklist is listed', () {
    for (final f in ConditionFixtures.all()) {
      final doc = const AircraftWorkflowParser().parse(f.text);
      for (final c in doc.checklists) {
        final signals = signalsFor(c);
        expect(
          signals.toSet().length,
          signals.length,
          reason: '${f.name}/${c.name}',
        );
        for (final item in c.items) {
          for (final d in item.condition?.signals ?? const <Dataref>[]) {
            expect(signals, contains(d), reason: '${f.name}/${c.name}');
          }
        }
      }
    }
  });
}
