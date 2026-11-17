import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flutter_test/flutter_test.dart';

// Challenge-response rows (GRAMMAR.md section 5d, D-84): sw_challenge: ON / OFF.
// AC-58

ChecklistDocument parse(String body) =>
    const AircraftWorkflowParser().parse(body);

List<ChecklistItem> items(String body) =>
    parse('sw_checklist:A\n$body').checklists.single.items;

/// The labels of the challenge rows.
List<String> challengeLabels(List<ChecklistItem> list) => [
  for (final i in list)
    if (i.challenge) i.label,
];

List<String> warningsOf(String body) => parse('sw_checklist:A\n$body').warnings;

void main() {
  group('sw_challenge: ON ... OFF (C1)', () {
    test('rows between the lines are challenge rows, the rest are flow', () {
      final list = items(
        'sw_item:One|SET\n'
        'sw_challenge: ON\n'
        'sw_item:Two|ON\n'
        'sw_item:Three|CHECK\n'
        'sw_challenge: OFF\n'
        'sw_item:Four|SET',
      );
      expect(list.map((i) => i.label), ['One', 'Two', 'Three', 'Four']);
      expect(list.map((i) => i.challenge), [false, true, true, false]);
    });

    test('the lines make no item and warn about nothing', () {
      final doc = parse(
        'sw_checklist:A\nsw_challenge: ON\nsw_item:X|ON\nsw_challenge: OFF',
      );
      expect(doc.checklists.single.items, hasLength(1));
      expect(doc.warnings, isEmpty);
    });

    test('headings, notes, details and a switch row are flagged too', () {
      final list = items(
        'sw_challenge: ON\n'
        'sw_item_heading:Head\n'
        'sw_item:X|ON\n'
        'sw_item_details:More\n'
        'sw_iteminfo:Note\n'
        'sw_switch:Use GPU|gpu|ON\n'
        'sw_end\n'
        'sw_challenge: OFF',
      );
      expect(list.every((i) => i.challenge), isTrue);
      expect(list.length, 5);
    });

    test('the value and the keyword ignore case and spaces', () {
      final list = items(
        'SW_CHALLENGE:on\nsw_item:X|ON\nsw_challenge:   Off  \nsw_item:Y|ON',
      );
      expect(list.map((i) => i.challenge), [true, false]);
    });

    test('a block can be used again in the same checklist', () {
      final list = items(
        'sw_challenge: ON\nsw_item:A|ON\nsw_challenge: OFF\n'
        'sw_item:B|ON\n'
        'sw_challenge: ON\nsw_item:C|ON\nsw_challenge: OFF',
      );
      expect(challengeLabels(list), ['A', 'C']);
    });

    test('the flag does not change the label, result or condition', () {
      final plain = items('sw_item:Flaps|SET:sim/x/y:1').single;
      final flagged = items(
        'sw_challenge: ON\nsw_item:Flaps|SET:sim/x/y:1\nsw_challenge: OFF',
      ).single;
      expect(flagged.label, plain.label);
      expect(flagged.result, plain.result);
      expect(flagged.condition, plain.condition);
    });
  });

  group('an unclosed block (C2)', () {
    test('ends at the next checklist, with a warning', () {
      final doc = parse(
        'sw_checklist:A\nsw_challenge: ON\nsw_item:X|ON\n'
        'sw_checklist:B\nsw_item:Y|ON',
      );
      expect(doc.checklists[0].items.single.challenge, isTrue);
      expect(doc.checklists[1].items.single.challenge, isFalse);
      expect(doc.warnings, [
        'Line 2: sw_challenge: ON has no OFF; closed at the end of the '
            'checklist',
      ]);
    });

    test('ends at the end of the file, with a warning', () {
      final w = warningsOf('sw_item:Z|ON\nsw_challenge: ON\nsw_item:X|ON');
      expect(w, [
        'Line 3: sw_challenge: ON has no OFF; closed at the end of the '
            'checklist',
      ]);
    });
  });

  group('stray lines (C3, C4)', () {
    test('OFF with no ON warns and changes nothing', () {
      final doc = parse('sw_checklist:A\nsw_challenge: OFF\nsw_item:X|ON');
      expect(doc.warnings, ['Line 2: sw_challenge: OFF without ON']);
      expect(doc.checklists.single.items.single.challenge, isFalse);
    });

    test('ON inside a block warns, and the first ON stays', () {
      final doc = parse(
        'sw_checklist:A\nsw_challenge: ON\nsw_challenge: ON\n'
        'sw_item:X|ON\nsw_challenge: OFF\nsw_item:Y|ON',
      );
      expect(doc.warnings, [
        'Line 3: sw_challenge: ON inside a challenge block; ignored',
      ]);
      expect(doc.checklists.single.items.map((i) => i.challenge), [
        true,
        false,
      ]);
    });

    test('a bad or missing value warns and is ignored', () {
      for (final line in [
        'sw_challenge: MAYBE',
        'sw_challenge:',
        'sw_challenge',
      ]) {
        final doc = parse('sw_checklist:A\n$line\nsw_item:X|ON');
        expect(doc.warnings, ['Line 2: sw_challenge needs ON or OFF; ignored']);
        expect(doc.checklists.single.items.single.challenge, isFalse);
      }
    });

    test('a line before any checklist warns like an item does', () {
      final doc = parse('sw_challenge: ON\nsw_checklist:A\nsw_item:X|ON');
      expect(doc.warnings, ['Line 1: item before any checklist']);
      expect(doc.checklists.single.items.single.challenge, isFalse);
    });
  });

  group('with switch blocks (C5)', () {
    test('a challenge block inside a branch ends with it, without a second '
        'warning at its OFF', () {
      final doc = parse(
        'sw_checklist:A\n'
        'sw_switch:Use GPU|gpu|ON\n'
        'sw_challenge: ON\n'
        'sw_item:In|ON\n'
        'sw_else\n'
        'sw_item:Other|ON\n'
        'sw_challenge: OFF\n'
        'sw_end\n'
        'sw_item:After|ON',
      );
      final list = doc.checklists.single.items;
      expect(list.map((i) => i.challenge), [false, true, false, false]);
      expect(doc.warnings, [
        'Line 5: sw_challenge crosses a switch block; '
            'closed at the block boundary',
      ]);
    });

    test('a challenge block that holds a whole switch block is fine', () {
      final doc = parse(
        'sw_checklist:A\n'
        'sw_challenge: ON\n'
        'sw_switch:Use GPU|gpu|ON\n'
        'sw_item:In|ON\n'
        'sw_else\n'
        'sw_item:Out|ON\n'
        'sw_end\n'
        'sw_item:After|ON\n'
        'sw_challenge: OFF',
      );
      expect(doc.warnings, isEmpty);
      expect(doc.checklists.single.items.every((i) => i.challenge), isTrue);
    });

    test('an OFF inside a switch block that began in the challenge block '
        'warns and closes it', () {
      final doc = parse(
        'sw_checklist:A\n'
        'sw_challenge: ON\n'
        'sw_switch:Use GPU|gpu|ON\n'
        'sw_item:In|ON\n'
        'sw_challenge: OFF\n'
        'sw_item:Still in the branch|ON\n'
        'sw_end',
      );
      expect(doc.checklists.single.items.map((i) => i.challenge), [
        true,
        true,
        false,
      ]);
      expect(doc.warnings, [
        'Line 5: sw_challenge crosses a switch block; '
            'closed at the block boundary',
      ]);
    });

    test('a block inside a branch and closed in it is fine', () {
      final doc = parse(
        'sw_checklist:A\n'
        'sw_switch:Use GPU|gpu|ON\n'
        'sw_challenge: ON\n'
        'sw_item:In|ON\n'
        'sw_challenge: OFF\n'
        'sw_item:Plain|ON\n'
        'sw_end',
      );
      expect(doc.warnings, isEmpty);
      expect(doc.checklists.single.items.map((i) => i.challenge), [
        false,
        true,
        false,
      ]);
    });
  });

  group('sw_continue look-ahead (C6)', () {
    test('a sw_challenge line between a link and the next item is skipped', () {
      final doc = parse(
        'sw_checklist:A\nsw_item:X|ON\nsw_continue\n'
        'sw_challenge: ON\nsw_checklist:B\nsw_item:Y|ON',
      );
      expect(doc.checklists, hasLength(2));
      expect(doc.checklists[0].continues, hasLength(1));
    });
  });
}
