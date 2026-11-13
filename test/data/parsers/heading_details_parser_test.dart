import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/colour_run.dart';
import 'package:flutter_test/flutter_test.dart';

List<ChecklistItem> items(String body) => const AircraftWorkflowParser()
    .parse('sw_checklist:A\n$body')
    .checklists
    .single
    .items;

void main() {
  group('sw_item_heading', () {
    test('no justify word is centre', () {
      expect(
        items('sw_item_heading:Empennage').single,
        const ChecklistItem(
          ChecklistItemType.heading,
          'Empennage',
          '',
          [],
          [],
          null,
          ChecklistJustify.center,
        ),
      );
    });

    test('left, center and right (any case) set the justify', () {
      for (final (text, want) in [
        ('left', ChecklistJustify.left),
        ('center', ChecklistJustify.center),
        ('right', ChecklistJustify.right),
        ('Center', ChecklistJustify.center),
        ('RIGHT', ChecklistJustify.right),
        ('centre', ChecklistJustify.center),
        (' left ', ChecklistJustify.left),
      ]) {
        final item = items('sw_item_heading:Empennage|$text').single;
        expect(item.type, ChecklistItemType.heading, reason: text);
        expect(item.label, 'Empennage', reason: text);
        expect(item.justify, want, reason: text);
      }
    });

    test(
      'a single letter or other text after the bar stays in the heading',
      () {
        expect(items('sw_item_heading:Wings|c').single.label, 'Wings|c');
        final item = items('sw_item_heading:Wings | left and right').single;
        expect(item.label, 'Wings | left and right');
        expect(item.justify, ChecklistJustify.center);
      },
    );

    test('a colon is part of the text, a heading has no condition', () {
      final item = items('sw_item_heading:Zone 1: tail|center').single;
      expect(item.label, 'Zone 1: tail');
      expect(item.justify, ChecklistJustify.center);
      expect(item.condition, isNull);
    });

    test('sw_item_heading_c keeps colour runs', () {
      final doc = const AircraftWorkflowParser().parse(
        'sw_define_colour:red:1,0,0\n'
        'sw_checklist:A\n'
        r'sw_item_heading_c:\red\Fire|center',
      );
      final item = doc.checklists.single.items.single;
      expect(item.labelRuns, const [ColourRun('Fire', 'red')]);
      expect(item.justify, ChecklistJustify.center);
      expect(doc.warnings, isEmpty);
    });

    test('an empty heading is skipped and warned', () {
      final doc = const AircraftWorkflowParser().parse(
        'sw_checklist:A\nsw_item_heading:|center\nsw_item:K|V',
      );
      expect(doc.checklists.single.items.map((i) => i.label), ['K']);
      expect(doc.warnings, ['Line 2: heading has no text']);
    });

    test('is not unknown, and a heading is not a check item', () {
      final doc = const AircraftWorkflowParser().parse(
        'sw_checklist:A\nsw_item_heading:H\nsw_item:K|V',
      );
      expect(doc.warnings, isEmpty);
      expect(doc.checklists.single.items.first.type, ChecklistItemType.heading);
    });
  });

  group('sw_item_details', () {
    test('is a details line holding the whole text', () {
      expect(
        items('sw_item_details:Check the lugs.').single,
        const ChecklistItem(ChecklistItemType.details, 'Check the lugs.'),
      );
    });

    test('colons and bars are part of the text, there is no condition', () {
      final item = items('sw_item_details:Left | right: sim/x:1').single;
      expect(item.type, ChecklistItemType.details);
      expect(item.label, 'Left | right: sim/x:1');
      expect(item.result, '');
      expect(item.condition, isNull);
    });

    test('stays in file order, after its item', () {
      final list = items(
        'sw_item:Door|CLOSED\nsw_item_details:Look.\nsw_item:B|C',
      );
      expect(list.map((i) => i.type), [
        ChecklistItemType.check,
        ChecklistItemType.details,
        ChecklistItemType.check,
      ]);
    });

    test('sw_item_details_c has colour runs', () {
      final doc = const AircraftWorkflowParser().parse(
        'sw_define_colour:red:1,0,0\n'
        'sw_checklist:A\n'
        r'sw_item_details_c:Check \red\three greens',
      );
      final item = doc.checklists.single.items.single;
      expect(item.label, 'Check three greens');
      expect(item.labelRuns, const [
        ColourRun('Check '),
        ColourRun('three greens', 'red'),
      ]);
      expect(doc.warnings, isEmpty);
    });

    test('an empty details line is skipped and warned', () {
      final doc = const AircraftWorkflowParser().parse(
        'sw_checklist:A\nsw_item_details:\nsw_item:K|V',
      );
      expect(doc.checklists.single.items.map((i) => i.label), ['K']);
      expect(doc.warnings, ['Line 2: details has no text']);
    });
  });
}
