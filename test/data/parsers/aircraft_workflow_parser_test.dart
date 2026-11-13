import 'dart:convert';
import 'dart:io';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_colour.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_sequence.dart';
import 'package:flightsim_aide/domain/models/checklist/colour_run.dart';
import 'package:flightsim_aide/domain/models/checklist/continue_link.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/checklist_json.dart';
import '../../../testing/parser_invariants.dart';

ChecklistDocument p(String s) => const AircraftWorkflowParser().parse(s);

/// A minimal valid checklist, so palette tests are not dropped as empty.
const _item = 'sw_checklist:A\nsw_item:K|V';

/// Defines `white`, so tests using `\white\` markers see no unknown colour.
const _defWhite = 'sw_define_colour:white:1,1,1';

/// An item with its condition removed. `ChecklistItem.condition` holds the parsed
/// condition; these tests are about the label and result only.
ChecklistItem _noCondition(ChecklistItem i) =>
    ChecklistItem(i.type, i.label, i.result, i.labelRuns, i.resultRuns);

void main() {
  group('skeleton and empty input', () {
    test('empty string gives no checklists and one warning', () {
      final doc = p('');
      expect(doc.checklists, isEmpty);
      expect(doc.warnings, ['No checklists found']);
    });

    test('whitespace-only gives no checklists', () {
      final doc = p('  \n\t\n   ');
      expect(doc.checklists, isEmpty);
    });

    test('parse never returns null', () {
      expect(p(''), isNotNull);
      expect(p('anything'), isA<ChecklistDocument>());
    });
  });

  // End-to-end document comparisons are in 'line endings end to end' (3.19).
  group('line ending and BOM normalization', () {
    test('CRLF text parses same as LF text', () {
      expect(normalizeLineEndingsAndBom('a\r\nb\r\n'), 'a\nb\n');
    });

    test('lone CR text parses same as LF text', () {
      expect(normalizeLineEndingsAndBom('a\rb\r'), 'a\nb\n');
    });

    test('BOM then sw_checklist parses', () {
      expect(
        normalizeLineEndingsAndBom('﻿sw_checklist:Pre\n'),
        'sw_checklist:Pre\n',
      );
      expect(p('﻿sw_checklist:Pre\n'), isA<ChecklistDocument>());
    });

    test('BOM is not part of the first keyword', () {
      expect(
        normalizeLineEndingsAndBom('﻿sw_checklist').startsWith('sw_'),
        isTrue,
      );
    });

    test('only a leading BOM is stripped', () {
      expect(normalizeLineEndingsAndBom('a﻿'), 'a﻿');
    });
  });

  group('per-line preprocessing', () {
    test('blank lines are ignored', () {
      expect(preprocessLines('\n  \n\t\n'), isEmpty);
    });

    test('# comment ignored', () {
      expect(preprocessLines('# note\n  # indented\nsw_item:x'), [
        (number: 3, text: 'sw_item:x'),
      ]);
    });

    test('// line is not treated as a comment', () {
      expect(preprocessLines('// hi\n; hi'), [
        (number: 1, text: '// hi'),
        (number: 2, text: '; hi'),
      ]);
    });

    test('leading @ stripped', () {
      expect(preprocessLines('@sw_item:x'), [(number: 1, text: 'sw_item:x')]);
    });

    test('@ followed by spaces still works', () {
      expect(preprocessLines('  @   sw_item:x  '), [
        (number: 1, text: 'sw_item:x'),
      ]);
    });

    test('only one leading @ is stripped', () {
      expect(preprocessLines('@@x'), [(number: 1, text: '@x')]);
    });

    test('comment-only file gives the no-checklists warning', () {
      final doc = p('# a\n\n# b\n');
      expect(doc.checklists, isEmpty);
      expect(doc.warnings, ['No checklists found']);
    });

    test('line numbers count skipped lines', () {
      final lines = preprocessLines('# c\n\n@\n   \nbad line');
      expect(lines.single.number, 5);
    });
  });

  group('keyword and value split', () {
    test('SW_CHECKLIST uppercase accepted', () {
      expect(splitKeywordValue('SW_CHECKLIST:Pre')?.keyword, 'sw_checklist');
    });

    test('Sw_Item mixed case accepted', () {
      expect(splitKeywordValue('Sw_Item:A|B'), (
        keyword: 'sw_item',
        value: 'A|B',
      ));
    });

    test('splits on the first colon only', () {
      expect(splitKeywordValue('sw_checklist:A:B')?.value, 'A:B');
    });

    test('line without colon warns "unrecognized line"', () {
      expect(splitKeywordValue('hello'), isNull);
      expect(p('# c\nhello').warnings, [
        'Line 2: unrecognized line',
        'No checklists found',
      ]);
    });

    test('colon at index 0 warns', () {
      expect(splitKeywordValue(':x'), isNull);
      expect(p(':x').warnings.first, 'Line 1: unrecognized line');
    });
  });

  group('sw_checklist basic', () {
    Checklist only(String s) => p('$s\nsw_item:K|V').checklists.single;

    test('Name:Menu text gives title = menu text', () {
      final c = only('sw_checklist:Prepare:Prepare for flight');
      expect(c.name, 'Prepare');
      expect(c.title, 'Prepare for flight');
    });

    test('name only gives title = name', () {
      final c = only('sw_checklist:Prepare');
      expect(c.name, 'Prepare');
      expect(c.title, 'Prepare');
    });

    test('spaces after colon trimmed', () {
      final c = only('sw_checklist: Preliminary:Preliminary');
      expect(c.name, 'Preliminary');
      expect(c.title, 'Preliminary');
    });

    test('trailing colon with empty menu falls back to name', () {
      expect(only('sw_checklist:Foo:').title, 'Foo');
    });

    test('extra colons stay in menu text', () {
      expect(only('sw_checklist:A:B:C').title, 'B:C');
    });

    test('each sw_checklist starts a new checklist', () {
      final doc = p('sw_checklist:A\nsw_item:x\nsw_checklist:B\nsw_item:y');
      expect(doc.checklists.map((c) => c.name), ['A', 'B']);
      expect(doc.warnings, isEmpty);
    });
  });

  group('empty checklist name', () {
    test('empty name gets placeholder and warning', () {
      final doc = p('# c\nsw_checklist:\nsw_item:K|V');
      expect(doc.checklists.single.name, 'Untitled checklist 1');
      expect(doc.checklists.single.title, 'Untitled checklist 1');
      expect(doc.warnings, ['Line 2: checklist has no name']);
    });

    test('two empty names get distinct placeholders', () {
      final doc = p('sw_checklist:\nsw_item:x\nsw_checklist:\nsw_item:y');
      expect(doc.checklists.map((c) => c.name), [
        'Untitled checklist 1',
        'Untitled checklist 2',
      ]);
      expect(doc.warnings, [
        'Line 1: checklist has no name',
        'Line 3: checklist has no name',
      ]);
    });
  });

  group('items before any checklist', () {
    test('orphan item skipped with warning', () {
      final doc = p('# c\nsw_item:A|B');
      expect(doc.warnings, [
        'Line 2: item before any checklist',
        'No checklists found',
      ]);
    });

    test('orphan note skipped with warning', () {
      expect(
        p('sw_itemvoid:Hi').warnings.first,
        'Line 1: item before any checklist',
      );
    });

    test('items after a checklist starts are kept', () {
      final doc = p('sw_checklist:A\nsw_item:x\nsw_itemvoid:y');
      expect(doc.checklists.single.items.map((i) => i.type), [
        ChecklistItemType.check,
        ChecklistItemType.note,
      ]);
      expect(doc.warnings, isEmpty);
    });

    test('orphan does not leak into the first checklist', () {
      final doc = p('sw_item:orphan\nsw_checklist:A\nsw_item:K|V');
      expect(doc.checklists.single.items.map((i) => i.label), ['K']);
      expect(doc.warnings, ['Line 1: item before any checklist']);
    });
  });

  group('sw_item label and result', () {
    ChecklistItem item(String line) =>
        p('sw_checklist:A\n$line').checklists.single.items.single;

    test('label and result split on pipe', () {
      expect(
        item('sw_item:Batteries|ON'),
        const ChecklistItem(ChecklistItemType.check, 'Batteries', 'ON'),
      );
    });

    test('whitespace is trimmed', () {
      expect(
        item('sw_item: Flaps | UP '),
        const ChecklistItem(ChecklistItemType.check, 'Flaps', 'UP'),
      );
    });

    test('lower case result is kept', () {
      expect(item('sw_item:Flight plan|loaded').result, 'loaded');
    });

    test('extra pipes stay in the result', () {
      expect(item('sw_item:A|B|C').result, 'B|C');
    });

    test('a colon before the pipe starts the dataref part', () {
      final i = item('sw_item:Time: now|OK');
      expect(i.label, 'Time');
      expect(i.result, '');
    });

    test('result is cut at its first colon', () {
      expect(item('sw_item:A|B:dataref').result, 'B');
    });

    test('no pipe or colon gives label only', () {
      expect(
        item('sw_item:Just a label'),
        const ChecklistItem(ChecklistItemType.check, 'Just a label'),
      );
    });
  });

  group('duplicate checklist names', () {
    test('second duplicate becomes "(2)"', () {
      final doc = p('sw_checklist:A\nsw_item:x\nsw_checklist:A\nsw_item:x');
      expect(doc.checklists.map((c) => c.name), ['A', 'A (2)']);
      expect(doc.warnings, [
        'Line 3: duplicate checklist name "A"; renamed to "A (2)"',
      ]);
    });

    test('third becomes "(3)"', () {
      final doc = p(
        'sw_checklist:A\nsw_item:x\nsw_checklist:A\nsw_item:x\nsw_checklist:A\nsw_item:x',
      );
      expect(doc.checklists.last.name, 'A (3)');
    });

    test('all names in the document are unique', () {
      final names = p(List.filled(5, 'sw_checklist:A\nsw_item:x').join('\n'))
          .checklists
          .map((c) => c.name)
          .toList();
      expect(names.length, 5);
      expect(names.toSet().length, names.length);

      final messy = File('testing/fixtures/messy.txt').readAsStringSync();
      final messyNames = p(messy).checklists.map((c) => c.name).toList();
      expect(messyNames.toSet().length, messyNames.length);
    });

    test('title is not renamed when menu text is present', () {
      final doc = p(
        'sw_checklist:A:Menu\nsw_item:x\nsw_checklist:A:Menu\nsw_item:x',
      );
      expect(doc.checklists[1].name, 'A (2)');
      expect(doc.checklists[1].title, 'Menu');
    });
  });

  group('item without a pipe', () {
    ChecklistItem item(String line) =>
        p('sw_checklist:A\n$line').checklists.single.items.single;

    test('label only', () {
      expect(
        item('sw_item:Lights'),
        const ChecklistItem(ChecklistItemType.check, 'Lights'),
      );
    });

    test('trailing pipe gives empty result', () {
      expect(item('sw_item:A|').result, '');
    });

    test('label-only item with dataref colon', () {
      expect(
        _noCondition(
          item('sw_item:Test bigger than:checklist/test/int_dref1:>50'),
        ),
        const ChecklistItem(ChecklistItemType.check, 'Test bigger than'),
      );
    });

    test('pipe after the first colon belongs to the dataref', () {
      expect(
        _noCondition(item('sw_item:Cond:(a/b:44)||(c/d:44)')),
        const ChecklistItem(ChecklistItemType.check, 'Cond'),
      );
    });
  });

  group('dataref suffix dropped', () {
    ChecklistItem item(String line) =>
        p('sw_checklist:A\n$line').checklists.single.items.single;

    test('suffix after the result is dropped', () {
      expect(
        _noCondition(
          item(
            'sw_item:Parking brake|set:sim/flightmodel/controls/parkbrake:1',
          ),
        ),
        const ChecklistItem(ChecklistItemType.check, 'Parking brake', 'set'),
      );
    });

    test('suffix with several colons dropped', () {
      expect(item('sw_item:A|ON:x:y:z').result, 'ON');
    });

    test('empty result before the colon gives empty result', () {
      expect(item('sw_item:A|:sim/foo').result, '');
    });
  });

  group('empty label', () {
    test('empty label skipped and warned', () {
      final doc = p('sw_checklist:A\nsw_item:|ON\nsw_item:K|V');
      expect(doc.checklists.single.items.map((i) => i.label), ['K']);
      expect(doc.warnings, ['Line 2: item has no label']);
    });

    test('whitespace-only label skipped and warned', () {
      final doc = p('sw_checklist:A\nsw_item:   |ON\nsw_item:K|V');
      expect(doc.checklists.single.items.map((i) => i.label), ['K']);
      expect(doc.warnings, ['Line 2: item has no label']);
    });

    test('following items still parse', () {
      final doc = p('sw_checklist:A\nsw_item:|ON\nsw_item:B|OFF');
      expect(doc.checklists.single.items, [
        const ChecklistItem(ChecklistItemType.check, 'B', 'OFF'),
      ]);
    });
  });

  group('sw_itemvoid', () {
    List<ChecklistItem> items(String body) =>
        p('sw_checklist:A\n$body').checklists.single.items;

    test('note label is kept', () {
      expect(items('sw_itemvoid:----- Prepare -----'), const [
        ChecklistItem(ChecklistItemType.note, '----- Prepare -----'),
      ]);
    });

    test('note containing a colon keeps it', () {
      expect(
        items('sw_itemvoid:Note: check fuel').single.label,
        'Note: check fuel',
      );
    });

    test('note without a pipe has empty result', () {
      expect(items('sw_itemvoid:Hello').single.result, '');
    });

    test('note with a pipe has a result', () {
      expect(
        items('sw_itemvoid:Gear|DOWN').single,
        const ChecklistItem(ChecklistItemType.note, 'Gear', 'DOWN'),
      );
    });

    test('note keeps its position between items', () {
      final result = items('sw_item:A|1\nsw_itemvoid:N\nsw_item:B|2');
      expect(result.map((i) => i.type), [
        ChecklistItemType.check,
        ChecklistItemType.note,
        ChecklistItemType.check,
      ]);
    });
  });

  group('colour markers', () {
    List<ChecklistItem> items(String body) =>
        p('sw_checklist:A\n$body').checklists.single.items;

    test('markers are removed from text', () {
      expect(stripColourMarkers(r'\white\FLAPS\grey\, 15'), 'FLAPS, 15');
    });

    test('marker-only label counts as empty', () {
      final doc = p(
        'sw_checklist:A\n'
        r'sw_item:\white\|ON'
        '\nsw_item:K|V\n$_defWhite',
      );
      expect(doc.checklists.single.items.map((i) => i.label), ['K']);
      expect(doc.warnings, ['Line 2: item has no label']);
    });

    test('double backslash is removed like a marker', () {
      expect(stripColourMarkers(r'a\red\b\\c'), 'abc');
    });

    test('text without markers is unchanged', () {
      expect(stripColourMarkers('Flaps 15: up'), 'Flaps 15: up');
    });

    test('result markers removed', () {
      expect(
        items(r'sw_item:\white\Batteries|\white\ON').single,
        const ChecklistItem(
          ChecklistItemType.check,
          'Batteries',
          'ON',
          [ColourRun('Batteries', 'white')],
          [ColourRun('ON', 'white')],
        ),
      );
    });

    test('note markers removed', () {
      expect(items(r'sw_itemvoid:\white\Hi').single.label, 'Hi');
    });
  });

  group('colour runs', () {
    List<ChecklistItem> items(String body) =>
        p('sw_checklist:A\n$body').checklists.single.items;

    test('two markers give two runs', () {
      final item = items(r'sw_item_c:\white\FLAPS\grey\, 15|UP').single;
      expect(item.label, 'FLAPS, 15');
      expect(item.labelRuns, const [
        ColourRun('FLAPS', 'white'),
        ColourRun(', 15', 'grey'),
      ]);
    });

    test('text before the first marker has no colour', () {
      final item = items(r'sw_item_c:Flaps \red\15|UP').single;
      expect(item.labelRuns, const [
        ColourRun('Flaps '),
        ColourRun('15', 'red'),
      ]);
    });

    test('runs joined equal the label and the result', () {
      for (final line in [
        r'sw_item_c:\a\x\b\ y \c\z|\d\1\e\ 2',
        r'sw_item_c:  \a\  x  \b\ y  |  \d\  1  ',
        r'sw_itemvoid_c:\a\Gear\b\|\c\DOWN',
        r'sw_item_c:\a\\\b\c',
      ]) {
        final item = items(line).single;
        final label = stripColourMarkers(line.split(':')[1].split('|')[0]);
        expect(item.labelParts.map((r) => r.text).join(), item.label);
        expect(item.resultParts.map((r) => r.text).join(), item.result);
        expect(item.label, label.trim());
      }
    });

    test('result has its own runs and colour does not carry over', () {
      final item = items(r'sw_item_c:\white\Batteries|ON\green\ OK').single;
      expect(item.labelRuns, const [ColourRun('Batteries', 'white')]);
      expect(item.resultRuns, const [
        ColourRun('ON'),
        ColourRun(' OK', 'green'),
      ]);
    });

    test('note text has runs', () {
      final item = items(r'sw_itemvoid_c:\cyan\Gear\red\|\red\DOWN').single;
      expect(item.type, ChecklistItemType.note);
      expect(item.labelRuns, const [ColourRun('Gear', 'cyan')]);
      expect(item.resultRuns, const [ColourRun('DOWN', 'red')]);
    });

    test('sw_remark and sw_iteminfo have runs', () {
      final doc = items(
        'sw_remark:\\red\\Stop\nsw_iteminfo:\\red\\Fuel|\\blue\\OK',
      );
      expect(doc[0].labelRuns, const [ColourRun('Stop', 'red')]);
      expect(doc[1].labelRuns, const [ColourRun('Fuel', 'red')]);
      expect(doc[1].resultRuns, const [ColourRun('OK', 'blue')]);
    });

    test('item without markers has no runs', () {
      final item = items('sw_item:Parking brake|SET').single;
      expect(item.labelRuns, isEmpty);
      expect(item.resultRuns, isEmpty);
      expect(item.labelParts, const [ColourRun('Parking brake')]);
      expect(item.resultParts, const [ColourRun('SET')]);
    });

    test('a _c line with no markers has no runs', () {
      expect(items('sw_item_c:Parking brake|SET').single.labelRuns, isEmpty);
    });

    test('whitespace around runs is trimmed', () {
      final item = items(r'sw_item_c:  \a\  x \b\ y  ').single;
      expect(item.label, 'x  y');
      expect(item.labelRuns, const [
        ColourRun('x ', 'a'),
        ColourRun(' y', 'b'),
      ]);
    });

    test('a marker followed only by spaces adds no run', () {
      final item = items(r'sw_item_c:\a\X\b\   ').single;
      expect(item.labelRuns, const [ColourRun('X', 'a')]);
    });

    test('same colour twice merges into one run', () {
      final item = items(r'sw_item_c:\red\a\red\b').single;
      expect(item.labelRuns, const [ColourRun('ab', 'red')]);
    });

    test('empty runs between markers are dropped', () {
      final item = items(r'sw_item_c:\a\\b\X').single;
      expect(item.labelRuns, const [ColourRun('X', 'b')]);
    });

    test('marker-only label still counts as empty', () {
      final doc = p(
        'sw_checklist:A\nsw_item_c:\\white\\|ON\nsw_item:K|V\n$_defWhite',
      );
      expect(doc.warnings, ['Line 2: item has no label']);
    });

    test('double backslash returns to the default colour', () {
      final item = items(r'sw_item_c:\red\a\\b').single;
      expect(item.label, 'ab');
      expect(item.labelRuns, const [ColourRun('a', 'red'), ColourRun('b')]);
    });

    test('double backslash returns to the previous colour (stack)', () {
      final item = items(r'sw_item_c:\a\x\b\y\\z\\w').single;
      expect(item.label, 'xyzw');
      expect(item.labelRuns, const [
        ColourRun('x', 'a'),
        ColourRun('y', 'b'),
        ColourRun('z', 'a'),
        ColourRun('w'),
      ]);
    });

    test('double backslash with nothing to return to is harmless', () {
      final item = items(r'sw_item_c:\\a\\\\b').single;
      expect(item.label, 'ab');
      expect(item.labelRuns, isEmpty);
    });

    test('the colour stack is per field', () {
      final item = items(r'sw_item_c:\a\x|y\\z').single;
      expect(item.labelRuns, const [ColourRun('x', 'a')]);
      expect(item.resultRuns, isEmpty);
      expect(item.result, 'yz');
    });

    test('a lone backslash is literal text', () {
      final item = items(r'sw_item_c:a\b').single;
      expect(item.label, r'a\b');
    });

    test('unterminated marker stays literal text', () {
      final item = items(r'sw_item_c:\red text').single;
      expect(item.label, r'\red text');
      expect(item.labelRuns, isEmpty);
    });

    test('undefined colour name keeps the name and warns', () {
      final doc = p('sw_checklist:A\nsw_item_c:\\nosuchcolour\\X');
      expect(doc.warnings, ['Line 2: unknown colour "nosuchcolour"']);
      expect(doc.checklists.single.items.single.labelRuns, const [
        ColourRun('X', 'nosuchcolour'),
      ]);
    });

    test('a colour defined after its use is known', () {
      final doc = p('sw_checklist:A\nsw_item_c:\\white\\X\n$_defWhite');
      expect(doc.warnings, isEmpty);
    });

    test('an unknown colour warns once per line however often it repeats', () {
      final doc = p(
        'sw_checklist:A\nsw_item_c:\\nope\\a\\nope\\b|\\nope\\c\n'
        'sw_item_c:\\nope\\d',
      );
      expect(doc.warnings, [
        'Line 2: unknown colour "nope"',
        'Line 3: unknown colour "nope"',
      ]);
    });

    test('each unknown colour on a line warns', () {
      final doc = p('sw_checklist:A\nsw_item_c:\\x\\a\\y\\b');
      expect(doc.warnings, [
        'Line 2: unknown colour "x"',
        'Line 2: unknown colour "y"',
      ]);
    });

    test('markers on plain keywords are read too, and checked', () {
      final doc = p('sw_checklist:A\nsw_itemvoid:\\magenta\\About 1000');
      expect(doc.checklists.single.items.single.label, 'About 1000');
      expect(doc.warnings, ['Line 2: unknown colour "magenta"']);
    });

    test('a marker on a skipped item before any checklist does not warn', () {
      final doc = p('sw_item_c:\\nope\\X\n$_item');
      expect(doc.warnings, ['Line 1: item before any checklist']);
    });

    test('colour names are kept exactly', () {
      final item = items(r'sw_item_c:\Red\a\red\b').single;
      expect(item.labelRuns.map((r) => r.colour), ['Red', 'red']);
    });

    test('colon and pipe splitting is unaffected by markers', () {
      final item = items(r'sw_item_c:\a\Label\b\|\c\Res:dataref:1').single;
      expect(item.label, 'Label');
      expect(item.result, 'Res');
      expect(item.resultRuns, const [ColourRun('Res', 'c')]);
    });

    test('parseColourRuns on empty text gives no runs', () {
      expect(parseColourRuns(''), isEmpty);
      expect(parseColourRuns('   '), isEmpty);
    });
  });

  group('keyword variants', () {
    List<ChecklistItem> items(String body) =>
        p('sw_checklist:A\n$body').checklists.single.items;

    test('sw_item_c is a check item', () {
      expect(
        items('sw_item_c:Flaps|UP').single,
        const ChecklistItem(ChecklistItemType.check, 'Flaps', 'UP'),
      );
    });

    test('sw_itemvoid_c is a note', () {
      expect(
        items('sw_itemvoid_c:Gear|DOWN').single,
        const ChecklistItem(ChecklistItemType.note, 'Gear', 'DOWN'),
      );
    });

    test('sw_iteminfo is a note with label and result', () {
      expect(
        items('sw_iteminfo:Fuel|FULL:dataref').single,
        const ChecklistItem(ChecklistItemType.note, 'Fuel', 'FULL'),
      );
    });

    test('sw_remark is a note', () {
      expect(
        items('sw_remark:Mind the | and: this').single,
        const ChecklistItem(ChecklistItemType.note, 'Mind the | and: this'),
      );
    });

    test('sw_iteminfo with an empty label is skipped and warned', () {
      final doc = p('sw_checklist:A\nsw_iteminfo:|X\nsw_item:K|V');
      expect(doc.checklists.single.items.map((i) => i.label), ['K']);
      expect(doc.warnings, ['Line 2: item has no label']);
    });

    test('_c line with no markers parses like the plain form', () {
      expect(items('sw_item_c:A|B:x'), items('sw_item:A|B:x'));
      expect(items('sw_itemvoid_c:A|B'), items('sw_itemvoid:A|B'));
    });

    test('sw_item_c colour marker before dataref colon', () {
      expect(
        _noCondition(
          items(r'sw_item_c:APU switch\yellow\ON:XCrafts/ERJ/APU_switch:1')
              .single,
        ),
        const ChecklistItem(ChecklistItemType.check, 'APU switchON', '', [
          ColourRun('APU switch'),
          ColourRun('ON', 'yellow'),
        ]),
      );
    });
  });

  group('empty note', () {
    test('empty note skipped and warned', () {
      final doc = p('sw_checklist:A\nsw_itemvoid:\nsw_item:K|V');
      expect(doc.checklists.single.items.map((i) => i.label), ['K']);
      expect(doc.warnings, ['Line 2: empty note']);
    });

    test('empty sw_itemvoid_c and sw_remark are skipped too', () {
      final doc = p(
        'sw_checklist:A\nsw_itemvoid_c:  \nsw_remark:\nsw_item:K|V',
      );
      expect(doc.checklists.single.items.map((i) => i.label), ['K']);
      expect(doc.warnings, ['Line 2: empty note', 'Line 3: empty note']);
    });

    test('marker-only note counts as empty', () {
      final doc = p(
        'sw_checklist:A\n'
        r'sw_itemvoid:\white\'
        '\nsw_item:K|V\n$_defWhite',
      );
      expect(doc.warnings, ['Line 2: empty note']);
    });

    test('note with only a result is kept', () {
      final doc = p('sw_checklist:A\nsw_itemvoid:|DOWN');
      expect(doc.checklists.single.items.single.result, 'DOWN');
    });
  });

  group('sw_define_colour palette', () {
    test('stores a colour', () {
      final doc = p('sw_define_colour:white:1.0,1.0,1.0\n$_item');
      expect(doc.colours, {'white': const ChecklistColour('white', 1, 1, 1)});
      expect(doc.warnings, isEmpty);
    });

    test('padded values parse', () {
      final doc = p('sw_define_colour:darkyellow:  0.80, 0.80 ,0.00\n$_item');
      expect(
        doc.colours['darkyellow'],
        const ChecklistColour('darkyellow', 0.8, 0.8, 0),
      );
      expect(doc.warnings, isEmpty);
    });

    test('padding around the name and after the keyword is trimmed', () {
      final doc = p('  sw_define_colour :  red  :1,0,0\n$_item');
      expect(doc.colours.keys, ['red']);
    });

    test('the first definition of a name wins and a repeat warns', () {
      final doc = p(
        'sw_define_colour:red:1,0,0\nsw_define_colour:red:0.5,0,0\n$_item',
      );
      expect(doc.colours, {'red': const ChecklistColour('red', 1, 0, 0)});
      expect(doc.warnings, [
        'Line 2: duplicate colour "red"; first definition kept',
      ]);
    });

    test('an identical repeat also warns', () {
      final doc = p(
        'sw_define_colour:red:1,0,0\nsw_define_colour:red:1,0,0\n$_item',
      );
      expect(doc.warnings, [
        'Line 2: duplicate colour "red"; first definition kept',
      ]);
    });

    test('a component above 1 is clamped with a warning', () {
      final doc = p('sw_define_colour:white:1.5,0.5,0\n$_item');
      expect(doc.colours['white'], const ChecklistColour('white', 1, 0.5, 0));
      expect(doc.warnings, ['Line 1: colour component out of range; clamped']);
    });

    test('a negative component is clamped to 0 with a warning', () {
      final doc = p('sw_define_colour:white:-0.1,0,0\n$_item');
      expect(doc.colours['white'], const ChecklistColour('white', 0, 0, 0));
      expect(doc.warnings, ['Line 1: colour component out of range; clamped']);
    });

    test('several out-of-range components give one warning', () {
      final doc = p('sw_define_colour:white:5,-5,9\n$_item');
      expect(doc.colours['white'], const ChecklistColour('white', 1, 0, 1));
      expect(doc.warnings, ['Line 1: colour component out of range; clamped']);
    });

    test('the bounds 0 and 1 are not clamped', () {
      final doc = p('sw_define_colour:white:0,1,0.5\n$_item');
      expect(doc.warnings, isEmpty);
    });

    test('names are case sensitive', () {
      final doc = p(
        'sw_define_colour:Red:1,0,0\nsw_define_colour:red:0,1,0\n$_item',
      );
      expect(doc.colours.keys, unorderedEquals(['Red', 'red']));
    });

    test('palette is available when defined after the checklists', () {
      final doc = p('$_item\nsw_define_colour:white:1,1,1');
      expect(doc.colours.keys, ['white']);
    });

    test('palette is available when the definition is inside a checklist', () {
      final doc = p(
        'sw_checklist:A\nsw_define_colour:white:1,1,1\nsw_item:K|V',
      );
      expect(doc.colours.keys, ['white']);
      expect(doc.checklists.single.items.length, 1);
    });

    test('keyword is matched ignoring case and a leading @', () {
      final doc = p('@SW_DEFINE_COLOUR:white:1,1,1\n$_item');
      expect(doc.colours.keys, ['white']);
    });

    final bad = {
      'two numbers': 'sw_define_colour:white:1,1',
      'four numbers': 'sw_define_colour:white:1,1,1,1',
      'non-number': 'sw_define_colour:white:a,b,c',
      'empty component': 'sw_define_colour:white:1,,1',
      'nan': 'sw_define_colour:white:nan,0,0',
      'infinity': 'sw_define_colour:white:infinity,0,0',
      'no name': 'sw_define_colour::1,1,1',
      'no values': 'sw_define_colour:white',
      'no colon at all': 'sw_define_colour',
      'empty value': 'sw_define_colour:',
      'trailing text': 'sw_define_colour:white:1,1,1:extra',
    };
    bad.forEach((label, line) {
      test('$label warns and skips', () {
        final doc = p('$line\n$_item');
        expect(doc.warnings, ['Line 1: bad colour definition']);
        expect(doc.colours, isEmpty);
        expect(doc.checklists.single.items.length, 1);
      });
    });

    test('a bad redefinition keeps the earlier good one', () {
      final doc = p(
        'sw_define_colour:red:1,0,0\nsw_define_colour:red:a,b,c\n$_item',
      );
      expect(doc.colours['red'], const ChecklistColour('red', 1, 0, 0));
      expect(doc.warnings, ['Line 2: bad colour definition']);
    });

    test('no definitions gives an empty palette', () {
      expect(p(_item).colours, isEmpty);
    });
  });

  group('unknown keywords', () {
    test('unknown keyword warns with its name', () {
      final doc = p('sw_checklist:A\nbogus_keyword:whatever\nsw_item:K|V');
      expect(doc.warnings, ['Line 2: unknown keyword "bogus_keyword"']);
    });

    test('typo keywords from real files warn', () {
      final doc = p(
        'sw_checklist:A\nssw_item_c:x\nsw_itemvoid_c_c:y\nsw_item:K|V',
      );
      expect(doc.warnings, [
        'Line 2: unknown keyword "ssw_item_c"',
        'Line 3: unknown keyword "sw_itemvoid_c_c"',
      ]);
    });

    test('unknown keyword inside a checklist does not end it', () {
      final doc = p('sw_checklist:A\nbogus:x\nsw_item:B|ON');
      expect(doc.checklists.single.items.length, 1);
    });

    test('sw_rcolsize is ignored silently', () {
      final doc = p('sw_checklist:A\nsw_rcolsize:60\nsw_item:K|V');
      expect(doc.warnings, isEmpty);
    });

    test('ignored keyword without a colon is silent too', () {
      final doc = p('sw_checklist:A\nsw_rcolsize\nSW_RCOLSIZE\nsw_item:K|V');
      expect(doc.warnings, isEmpty);
    });

    test('sw_rcolsize gives no item, no link and no colour', () {
      final doc = p('sw_checklist:A\nsw_rcolsize:60\nsw_item:K|V');
      expect(doc.checklists.single.items.length, 1);
      expect(doc.checklists.single.continues, isEmpty);
      expect(doc.colours, isEmpty);
    });

    test('sw_rcolsize is the only silent-ignore entry in the parser', () {
      final source = File('lib/data/parsers/aircraft_workflow_parser.dart')
          .readAsStringSync();
      final entry = RegExp(r'const _ignoredKeywords = \{([^}]*)\};')
          .firstMatch(source)![1]!;
      expect(entry.replaceAll(RegExp(r'[\s\x27]'), ''), 'sw_rcolsize');
    });
  });

  group('sw_show is ignored like a comment', () {
    const dataref = 'sw_show:(sim/cockpit2/x:>9900)&&(sim/time/is_in_replay:0)';

    test('sw_show gives no warning', () {
      final doc = p('sw_checklist:A\n$dataref\nsw_item:K|V');
      expect(doc.warnings, isEmpty);
    });

    test('sw_show inside a checklist does not end it', () {
      final doc = p('sw_checklist:A\nsw_item:K|V\n$dataref\nsw_item:L|W');
      expect(doc.checklists.single.items.length, 2);
      expect(doc.warnings, isEmpty);
    });

    test('sw_show directly after sw_checklist, as in real files', () {
      final doc = p('sw_checklist:CRUISE:Cruise\n$dataref\nsw_item:K|V');
      expect(doc.checklists.single.title, 'Cruise');
      expect(doc.warnings, isEmpty);
    });

    test('sw_show before any checklist gives no warning', () {
      final doc = p('$dataref\nsw_checklist:A\nsw_item:K|V');
      expect(doc.warnings, isEmpty);
    });

    test('@sw_show and upper case behave the same', () {
      final doc = p(
        'sw_checklist:A\n@sw_show:(a:1)\nSW_SHOW:(b:2)\nsw_item:K|V',
      );
      expect(doc.warnings, isEmpty);
    });

    test('sw_show without a colon gives no warning', () {
      final doc = p('sw_checklist:A\nsw_show\nsw_item:K|V');
      expect(doc.warnings, isEmpty);
    });

    test('several sw_show lines give no warning', () {
      final doc = p('sw_checklist:A\n$dataref\n$dataref\nsw_item:K|V');
      expect(doc.warnings, isEmpty);
    });

    test('sw_show adds no item and no model data', () {
      final doc = p('sw_checklist:A\n$dataref\nsw_item:K|V');
      expect(doc.checklists.single.items.length, 1);
      expect(doc.colours, isEmpty);
      expect(doc.checklists.single.continues, isEmpty);
    });

    test('a bare continue followed by sw_show still links to the next', () {
      final doc = p(
        'sw_checklist:A\nsw_item:K|V\nsw_continue\n$dataref\n'
        'sw_checklist:B\nsw_item:K|V',
      );
      expect(doc.checklists.first.continues, hasLength(1));
      expect(doc.warnings, isEmpty);
    });
  });

  group('sw_continue parsing', () {
    const body = 'sw_item:K|V';
    // Checklists the links below can point to, so none is dropped as invalid.
    const targets =
        'sw_checklist:B\n$body\nsw_checklist:X\n$body\nsw_checklist:Y\n$body\n'
        'sw_checklist:Landing\n$body\nsw_checklist:ILS APPROACH I\n$body\n'
        'sw_checklist:****LANDING****\n$body';
    List<ContinueLink> links(String head) =>
        p('sw_checklist:A\n$body\n$head\n$targets').checklists.first.continues;

    test('bare sw_continue gives next', () {
      expect(links('sw_continue'), [const ContinueLink.next()]);
    });

    test('bare sw_continue with a trailing colon or spaces gives next', () {
      expect(links('sw_continue:  '), [const ContinueLink.next()]);
      expect(links('sw_continue   '), [const ContinueLink.next()]);
    });

    test('named gives the named target, trimmed', () {
      expect(links('sw_continue:  ILS APPROACH I  '), [
        const ContinueLink.named('ILS APPROACH I'),
      ]);
    });

    test('a condition after the name is kept on the link', () {
      final link = links('sw_continue:****LANDING****:sim/x:1').single;
      expect(link.target, '****LANDING****');
      expect(link.condition, isNotNull);
    });

    test('a name keeps its case', () {
      expect(links('sw_continue:Landing'), [
        const ContinueLink.named('Landing'),
      ]);
    });

    test('no checklist open warns and skips', () {
      final doc = p('sw_continue\nsw_continue:B\nsw_checklist:A\n$body');
      expect(doc.warnings, [
        'Line 1: item before any checklist',
        'Line 2: item before any checklist',
      ]);
      expect(doc.checklists.single.continues, isEmpty);
    });

    test('several in a row keep their order', () {
      expect(links('sw_continue:X\nsw_continue:Y\nsw_continue'), [
        const ContinueLink.named('X'),
        const ContinueLink.named('Y'),
        const ContinueLink.next(),
      ]);
    });

    test('items after a named continue still belong to the checklist', () {
      final doc = p(
        'sw_checklist:A\nsw_continue:B\n$body\nsw_item:L|W\n$targets',
      );
      expect(doc.checklists.first.items.length, 2);
      expect(doc.checklists.first.continues, [const ContinueLink.named('B')]);
    });

    test('@sw_continue and upper case parse', () {
      expect(links('@sw_continue:B\nSW_CONTINUE'), [
        const ContinueLink.named('B'),
        const ContinueLink.next(),
      ]);
    });

    test('comments and blank lines around it are ignored', () {
      expect(links('\n# c\nsw_continue\n# d\n'), [const ContinueLink.next()]);
    });

    test('each checklist keeps its own links', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_continue:B\n'
        'sw_checklist:B\n$body\n'
        'sw_checklist:C\n$body\nsw_continue\n'
        'sw_checklist:D\n$body',
      );
      expect(doc.checklists.map((c) => c.continues), [
        [const ContinueLink.named('B')],
        isEmpty,
        [const ContinueLink.next()],
        isEmpty,
      ]);
    });

    test('checklist without continue has an empty list', () {
      expect(p('sw_checklist:A\n$body').checklists.single.continues, isEmpty);
    });

    test('a continue does not create an item', () {
      final doc = p('sw_checklist:A\n$body\nsw_continue:B\n$targets');
      expect(doc.checklists.first.items.length, 1);
      expect(doc.warnings, isEmpty);
    });

    test('a continue in a dropped empty checklist is dropped with it', () {
      final doc = p('sw_checklist:A\nsw_continue:B\nsw_checklist:B\n$body');
      expect(doc.checklists.single.continues, isEmpty);
    });
  });

  group('sw_continue validation', () {
    const body = 'sw_item:K|V';
    const notFollowed =
        'sw_continue without a name is not followed by a checklist';

    test('bare continue followed by a checklist is kept', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_continue\nsw_checklist:B\n$body',
      );
      expect(doc.checklists.first.continues, [const ContinueLink.next()]);
      expect(doc.warnings, isEmpty);
    });

    test('blank lines and comments before the checklist are skipped', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_continue\n\n# c\n####\n\n'
        'sw_checklist:B\n$body',
      );
      expect(doc.checklists.first.continues, [const ContinueLink.next()]);
      expect(doc.warnings, isEmpty);
    });

    test('a bare continue then more continues then a checklist is kept', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_continue\nsw_continue:B\nsw_continue\n'
        'sw_checklist:B\n$body',
      );
      expect(doc.checklists.first.continues, [
        const ContinueLink.next(),
        const ContinueLink.named('B'),
        const ContinueLink.next(),
      ]);
      expect(doc.warnings, isEmpty);
    });

    test('a bare continue followed by an item is dropped with a warning', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_continue\n$body\nsw_checklist:B\n$body',
      );
      expect(doc.checklists.first.continues, isEmpty);
      expect(doc.warnings, ['Line 3: $notFollowed']);
      expect(doc.checklists.first.items.length, 2);
    });

    for (final other in [
      'sw_define_colour:red:1,0,0',
      'sw_rcolsize:60',
      'bogus_keyword:x',
      'free text',
    ]) {
      test('a bare continue followed by "$other" is dropped', () {
        final doc = p(
          'sw_checklist:A\n$body\nsw_continue\n$other\nsw_checklist:B\n$body',
        );
        expect(doc.checklists.first.continues, isEmpty);
        expect(doc.warnings, contains('Line 3: $notFollowed'));
      });
    }

    test('a bare continue at the end of the file is dropped', () {
      final doc = p('sw_checklist:A\n$body\nsw_continue\n\n# end\n');
      expect(doc.checklists.single.continues, isEmpty);
      expect(doc.warnings, ['Line 3: $notFollowed']);
    });

    test('a bare continue before a dropped checklist reports it not found', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_continue\nsw_checklist:Empty\n'
        'sw_checklist:B\n$body',
      );
      expect(doc.checklists.first.continues, isEmpty);
      expect(doc.warnings, [
        'Line 3: continue target "Empty" not found',
        'Line 4: checklist "Empty" has no items; dropped',
      ]);
    });

    test('a named continue to a later checklist is kept', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_continue:C\n'
        'sw_checklist:B\n$body\nsw_checklist:C\n$body',
      );
      expect(doc.checklists.first.continues, [const ContinueLink.named('C')]);
      expect(doc.warnings, isEmpty);
    });

    test('a named continue at the end of the file to an earlier checklist', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_checklist:B\n$body\nsw_continue:A',
      );
      expect(doc.checklists.last.continues, [const ContinueLink.named('A')]);
      expect(doc.warnings, isEmpty);
    });

    test('a named continue to itself is kept', () {
      final doc = p('sw_checklist:A\n$body\nsw_continue:A');
      expect(doc.checklists.single.continues, [const ContinueLink.named('A')]);
    });

    test(
      'a named continue with an unknown target is dropped with a warning',
      () {
        final doc = p(
          'sw_checklist:A\n$body\nsw_continue:Nope\nsw_checklist:B\n$body',
        );
        expect(doc.checklists.first.continues, isEmpty);
        expect(doc.warnings, ['Line 3: continue target "Nope" not found']);
      },
    );

    test('the target is matched on the name, not on the menu title', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_continue:Pretty title\n'
        'sw_checklist:B:Pretty title\n$body',
      );
      expect(doc.checklists.first.continues, isEmpty);
      expect(doc.warnings, [
        'Line 3: continue target "Pretty title" not found',
      ]);
    });

    test('the target match is case sensitive', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_continue:b\nsw_checklist:B\n$body',
      );
      expect(doc.warnings, ['Line 3: continue target "b" not found']);
    });

    test('a named continue to a dropped empty checklist is not found', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_continue:Empty\nsw_checklist:Empty',
      );
      expect(doc.checklists.single.continues, isEmpty);
      expect(doc.warnings, [
        'Line 3: continue target "Empty" not found',
        'Line 4: checklist "Empty" has no items; dropped',
      ]);
    });

    test('a dropped link keeps the checklist and its items', () {
      final doc = p('sw_checklist:A\n$body\nsw_item:L|W\nsw_continue:Nope');
      expect(doc.checklists.single.items.length, 2);
      expect(doc.checklists.single.continues, isEmpty);
    });

    test('only the invalid links of a run are dropped', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_continue:B\nsw_continue:Nope\n'
        'sw_checklist:B\n$body',
      );
      expect(doc.checklists.first.continues, [const ContinueLink.named('B')]);
      expect(doc.warnings, ['Line 4: continue target "Nope" not found']);
    });

    const atEnd = 'sw_continue should be at the end of its checklist';

    test('a named continue followed by an item warns; link and items stay', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_continue:B\nsw_item:L|W\n'
        'sw_checklist:B\n$body',
      );
      expect(doc.warnings, ['Line 3: $atEnd']);
      expect(doc.checklists.first.continues, [const ContinueLink.named('B')]);
      expect(doc.checklists.first.items.length, 2);
    });

    for (final line in [
      'sw_itemvoid:note',
      'sw_itemvoid_c:note',
      'sw_iteminfo:Fuel|OK',
      'sw_remark:Stop',
      'sw_item_c:K|V',
    ]) {
      test('a named continue followed by "$line" warns', () {
        final doc = p(
          'sw_checklist:A\n$body\nsw_continue:B\n$line\nsw_checklist:B\n$body',
        );
        expect(doc.warnings, ['Line 3: $atEnd']);
      });
    }

    test('a comment and blank lines then a checklist do not warn', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_continue:B\n\n# c\nsw_checklist:B\n$body',
      );
      expect(doc.warnings, isEmpty);
    });

    test('a named continue at the end of the file does not warn', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_checklist:B\n$body\nsw_continue:A',
      );
      expect(doc.warnings, isEmpty);
    });

    test('a run of continues then an item warns once per continue line', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_continue:B\nsw_continue:B\n$body\n'
        'sw_checklist:B\n$body',
      );
      expect(doc.warnings, ['Line 3: $atEnd', 'Line 4: $atEnd']);
    });

    test('a named continue followed by sw_define_colour does not warn', () {
      final doc = p(
        'sw_checklist:A\n$body\nsw_continue:B\nsw_define_colour:red:1,0,0\n'
        'sw_checklist:B\n$body',
      );
      expect(doc.warnings, isEmpty);
    });

    test('out-of-order file: the sequence follows the links', () {
      final doc = p(
        'sw_checklist:Landing\n$body\n'
        'sw_checklist:Cruise\n$body\nsw_continue:Landing\n'
        'sw_checklist:Takeoff\n$body\nsw_continue:Cruise',
      );
      expect(doc.warnings, isEmpty);
      expect(doc.checklists.map((c) => c.name), [
        'Landing',
        'Cruise',
        'Takeoff',
      ]);
      expect(ChecklistSequence(doc.checklists).ordered.map((c) => c.name), [
        'Takeoff',
        'Cruise',
        'Landing',
      ]);
    });

    test('real-file shape: branches at the end of a page', () {
      final doc = p(
        'sw_checklist:Approach\n$body\n'
        'sw_continue:Landing:sim/x:1\nsw_continue:Go around:sim/x:2\n'
        '#####\n'
        'sw_checklist:Landing\n$body\nsw_checklist:Go around\n$body',
      );
      expect(doc.checklists.first.continues.map((l) => l.target), [
        'Landing',
        'Go around',
      ]);
      expect(doc.warnings, isEmpty);
    });
  });

  group('drop empty checklists', () {
    test('empty checklist dropped with warning', () {
      final doc = p('sw_checklist:A\nsw_checklist:B\nsw_item:x');
      expect(doc.checklists.map((c) => c.name), ['B']);
      expect(doc.warnings, ['Line 1: checklist "A" has no items; dropped']);
    });

    test('checklist with only a note is kept', () {
      final doc = p('sw_checklist:A\nsw_itemvoid:Hi');
      expect(doc.checklists.single.items.length, 1);
      expect(doc.warnings, isEmpty);
    });

    test('checklist containing only a skipped bad item is dropped', () {
      final doc = p('sw_checklist:A\nsw_item:|ON');
      expect(doc.checklists, isEmpty);
      expect(doc.warnings, [
        'Line 2: item has no label',
        'Line 1: checklist "A" has no items; dropped',
        'No checklists found',
      ]);
    });
  });

  group('no checklists at all', () {
    test('garbage text gives empty doc and "No checklists found"', () {
      final doc = p('hello world');
      expect(doc.checklists, isEmpty);
      expect(doc.warnings.last, 'No checklists found');
    });

    test('other warnings are preserved alongside', () {
      final doc = p('garbage\nbogus:x\nsw_item:A|B');
      expect(doc.checklists, isEmpty);
      expect(doc.warnings, [
        'Line 1: unrecognized line',
        'Line 2: unknown keyword "bogus"',
        'Line 3: item before any checklist',
        'No checklists found',
      ]);
    });
  });

  group('warning format contract', () {
    final format = RegExp(r'^(Line \d+: .+|No checklists found)$');

    void expectWellFormed(String text) {
      for (final w in p(text).warnings) {
        expect(w, matches(format));
      }
    }

    test('every warning from messy.txt matches the format', () {
      final messy = File('testing/fixtures/messy.txt').readAsStringSync();
      expect(p(messy).warnings, isNotEmpty);
      expectWellFormed(messy);
    });

    test('every warning from hand-written bad strings matches', () {
      for (final bad in [
        'no colon here',
        ':leading colon',
        'sw_item:orphan|X\nsw_itemvoid:',
        'sw_checklist:\nsw_checklist:\nsw_checklist:A\nsw_checklist:A',
        'sw_checklist:A\nsw_item:|X\nsw_iteminfo: |Y\nbogus:z\nsw_remark:',
      ]) {
        expect(p(bad).warnings, isNotEmpty, reason: bad);
        expectWellFormed(bad);
      }
    });
  });

  group('line endings end to end', () {
    const lf = 'sw_checklist:A\nsw_item:x|1\nbogus:z\nsw_item:y|2\n';

    test('CRLF equals LF', () {
      expect(p(lf.replaceAll('\n', '\r\n')), p(lf));
    });

    test('CR equals LF', () {
      expect(p(lf.replaceAll('\n', '\r')), p(lf));
    });

    test('BOM equals no BOM', () {
      expect(p('\uFEFF$lf'), p(lf));
      expect(p('\uFEFF$lf').checklists.single.name, 'A');
    });

    test('mixed endings in one file', () {
      const mixed = 'sw_checklist:A\r\nsw_item:x|1\rbogus:z\nsw_item:y|2\r\n';
      final doc = p(mixed);
      expect(doc, p(lf));
      expect(doc.warnings, ['Line 3: unknown keyword "bogus"']);
    });
  });

  group('fixture minimal.txt', () {
    final doc = p(File('testing/fixtures/minimal.txt').readAsStringSync());

    // AC-1
    // AC-6
    test('parses to the prepare checklist with no warnings', () {
      expect(doc.warnings, isEmpty);
      expect(doc.checklists.length, 1);
      expect(doc.checklists.single.name, 'Prepare');
      expect(doc.checklists.single.title, 'Prepare for flight');
    });

    // AC-2
    // AC-6
    test('items are a note then three checks', () {
      expect(doc.checklists.single.items, const [
        ChecklistItem(ChecklistItemType.note, '----- Prepare -----'),
        ChecklistItem(ChecklistItemType.check, 'Parking brake', 'SET'),
        ChecklistItem(ChecklistItemType.check, 'Batteries', 'ON'),
        ChecklistItem(ChecklistItemType.check, 'Flight plan', 'loaded'),
      ]);
    });
  });

  group('fixture messy.txt', () {
    final doc = p(File('testing/fixtures/messy.txt').readAsStringSync());

    // AC-1
    // AC-6
    test('only Preliminary and Colours survive', () {
      expect(doc.checklists.map((c) => c.name), ['Preliminary', 'Colours']);
      expect(doc.checklists.first.title, 'Preliminary');
      expect(doc.checklists.any((c) => c.name == 'Empty'), isFalse);
    });

    test('items match the oracle', () {
      expect(doc.checklists.first.items.map(_noCondition), const [
        ChecklistItem(ChecklistItemType.check, 'Parking brake', 'SET|set'),
        ChecklistItem(ChecklistItemType.check, 'Item with no pipe'),
        ChecklistItem(ChecklistItemType.note, '----- Preliminary -----'),
        ChecklistItem(ChecklistItemType.check, 'Upper case keyword', 'OK'),
      ]);
    });

    test('the palette keeps the first red and clamps blue', () {
      expect(doc.colours, {
        'red': const ChecklistColour('red', 1, 0, 0),
        'blue': const ChecklistColour('blue', 1, 0, 0),
      });
    });

    test('colour items carry their runs', () {
      expect(doc.checklists.last.items, const [
        ChecklistItem(
          ChecklistItemType.check,
          'Red plain',
          'ON',
          [ColourRun('Red', 'red'), ColourRun(' plain')],
          [ColourRun('ON', 'blue')],
        ),
        ChecklistItem(ChecklistItemType.check, 'Ghost colour', 'OK', [
          ColourRun('Ghost colour', 'ghost'),
        ]),
      ]);
    });

    test('the continue to a missing checklist is dropped', () {
      expect(doc.checklists.last.continues, isEmpty);
    });

    test('warnings match the oracle exactly, in order', () {
      expect(doc.warnings, [
        'Line 1: item before any checklist',
        'Line 4: unrecognized line',
        'Line 11: unknown keyword "bogus_keyword"',
        'Line 16: duplicate colour "red"; first definition kept',
        'Line 17: colour component out of range; clamped',
        'Line 18: bad colour definition',
        'Line 20: unknown colour "ghost"',
        'Line 13: checklist "Empty" has no items; dropped',
        'Line 22: continue target "Nowhere" not found',
      ]);
    });
  });

  group('fixture lookalike_aircraft.txt', () {
    final doc = p(
      File('testing/fixtures/lookalike_aircraft.txt').readAsStringSync(),
    );
    List<String> names(Iterable<Checklist> list) =>
        list.map((c) => c.name).toList();

    test('the palette has the three defined colours', () {
      expect(doc.colours, {
        'white': const ChecklistColour('white', 0.9, 0.9, 0.9),
        'grey': const ChecklistColour('grey', 0.6, 0.6, 0.6),
        'amber': const ChecklistColour('amber', 1, 0.75, 0),
      });
    });

    test('every continue link is kept', () {
      expect(doc.checklists.map((c) => c.continues.length), [
        1, 1, 1, 1, 1, 0, 1, //
      ]);
      expect(doc.checklists.first.continues, [const ContinueLink.next()]);
    });

    test('the file order is not the flight order', () {
      expect(names(doc.checklists).sublist(4), [
        'BEFORE TAKEOFF',
        'LANDING',
        'CRUISE',
      ]);
      expect(names(ChecklistSequence(doc.checklists).ordered).sublist(3), [
        'ENGINE START',
        'BEFORE TAKEOFF',
        'CRUISE',
        'LANDING',
      ]);
    });

    test('the return marker gives three runs', () {
      final item = doc.checklists
          .firstWhere((c) => c.name == 'LANDING')
          .items
          .last;
      expect(item.label, 'Speed, final approach');
      expect(item.labelRuns, const [
        ColourRun('Speed', 'white'),
        ColourRun(', final', 'grey'),
        ColourRun(' approach', 'white'),
      ]);
    });

    test('the only warning is the empty note (sw_show is ignored)', () {
      expect(doc.warnings, ['Line 10: empty note']);
    });
  });

  group('fixture oracle counts and invariants', () {
    // name -> (checklists, check items, notes, warnings), from EXPECTED.md.
    const oracle = {
      'minimal': (1, 3, 1, 0),
      'messy': (2, 5, 1, 9),
      'lookalike_aircraft': (7, 33, 9, 1),
    };
    final clPattern = RegExp(r'^\s*@?sw_checklist:', multiLine: true);
    final itPattern = RegExp(r'^\s*@?sw_item(_c)?:', multiLine: true);

    String load(String path) => File(path).readAsStringSync();
    String raw(String name) =>
        load('testing/fixtures/$name.txt')
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n');

    for (final entry in oracle.entries) {
      final (checklists, checks, notes, warnings) = entry.value;

      // AC-1
      // AC-2
      // AC-6
      test('${entry.key} matches the oracle counts', () {
        final doc = p(raw(entry.key));
        final items = doc.checklists.expand((c) => c.items);
        expect(doc.checklists.length, checklists);
        expect(
          items.where((i) => i.type == ChecklistItemType.check).length,
          checks,
        );
        expect(
          items.where((i) => i.type == ChecklistItemType.note).length,
          notes,
        );
        expect(doc.warnings.length, warnings);
      });
    }

    for (final name in ['lookalike_aircraft']) {
      // AC-6
      test('$name counts equal the independent regex counts', () {
        final text = raw(name);
        final doc = p(text);
        expect(doc.checklists.length, clPattern.allMatches(text).length);
        final checks = doc.checklists
            .expand((c) => c.items)
            .where((i) => i.type == ChecklistItemType.check);
        expect(checks.length, itPattern.allMatches(text).length);
      });
    }

    final inputs = {
      for (final name in oracle.keys) name: raw(name),
      'sample asset': load('testing/fixtures/sample_checklist.txt'),
    };

    inputs.forEach((name, text) {
      test('$name satisfies the parser invariants', () {
        expectParserInvariants(p(text));
      });
    });
  });

  group('very long input', () {
    test('long label preserved fully', () {
      final label = 'x' * 10000;
      final doc = p('sw_checklist:A\nsw_item:$label|OK');
      expect(doc.checklists.single.items.single.label, label);
      expect(doc.warnings, isEmpty);
    });

    test('5000-line file parses in under 1 second', () {
      final text = [
        'sw_checklist:A',
        for (var n = 1; n < 5000; n++) 'sw_item:Item $n|OK',
      ].join('\n');
      final watch = Stopwatch()..start();
      final doc = p(text);
      watch.stop();
      expect(doc.checklists.single.items.length, 4999);
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });
  });

  group('golden snapshot', () {
    test('parse matches golden', () {
      final doc = p(
        File('testing/fixtures/lookalike_aircraft.txt').readAsStringSync(),
      );
      final golden = jsonDecode(
        File('test/data/parsers/golden/lookalike_aircraft.json')
            .readAsStringSync(),
      );
      expect(jsonDecode(jsonEncode(documentToJson(doc))), golden);
    });
  });
}
