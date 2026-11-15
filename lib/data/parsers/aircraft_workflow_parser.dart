import '../../domain/models/checklist/checklist.dart';
import '../../domain/models/checklist/checklist_colour.dart';
import '../../domain/models/checklist/checklist_document.dart';
import '../../domain/models/checklist/checklist_item.dart';
import '../../domain/models/checklist/colour_run.dart';
import '../../domain/models/checklist/continue_link.dart';
import '../../domain/models/flight_sim/item_condition.dart';
import 'condition_expression_parser.dart';

/// Parses an aircraft's workflow text (the X-Plane XChecklist plugin's syntax) into
/// a [ChecklistDocument]. Pure, does no I/O.
class AircraftWorkflowParser {
  /// Creates a parser.
  const AircraftWorkflowParser();

  /// Parses [text]; never throws and never returns null.
  ChecklistDocument parse(String text) {
    final lines = preprocessLines(normalizeLineEndingsAndBom(text));
    final warnings = <String>[];
    final checklists = <Checklist>[];
    final itemLists = <List<ChecklistItem>>[];
    final headerLines = <int>[];
    List<ChecklistItem>? currentItems;
    final usedNames = <String>{};
    final colours = <String, ChecklistColour>{};
    final markerUses = <({int line, String name})>[];
    final continueLists = <List<_PendingContinue>>[];
    List<_PendingContinue>? currentContinues;
    var untitledCount = 0;
    // The switch row of the open `sw_enable_start` block, if any (section 5b).
    int? openGate;
    int openGateLine = 0;

    // `sw_continue` belongs to the open checklist (`GRAMMAR.md` F1, F2). The
    // name is the text before the next `:`; a condition after it is dropped.
    // The link is validated once the whole file is read (see below).
    void addContinue(int index, String value) {
      final number = lines[index].number;
      final open = currentContinues;
      if (open == null) {
        warnings.add('Line $number: item before any checklist');
        return;
      }
      final colon = value.indexOf(':');
      final target = (colon < 0 ? value : value.substring(0, colon)).trim();
      final parsed = _conditions.parse(
        colon < 0 ? '' : value.substring(colon + 1),
      );
      final follow = _lookAhead(lines, index);
      final pending = _PendingContinue(
        target.isEmpty
            ? ContinueLink.next(condition: parsed.condition)
            : ContinueLink.named(target, condition: parsed.condition),
        number,
        follow.kind,
        follow.headerLine,
      );
      if (parsed.failed) {
        // A link whose condition cannot be read is not followed (J6).
        warnings.add('Line $number: condition not supported: ${parsed.reason}');
        pending.dropped = true;
      }
      open.add(pending);
    }

    // An `sw_enable_start` block ends at `sw_enable_end`; one still open when
    // its checklist or the file ends is closed there, with a warning (G5).
    void closeOpenGate() {
      if (openGate != null) {
        warnings.add(
          'Line $openGateLine: sw_enable_start has no sw_enable_end; '
          'closed at the end of the checklist',
        );
        openGate = null;
      }
    }

    void startGate(int number, String value) {
      final items = currentItems;
      if (items == null) {
        warnings.add('Line $number: item before any checklist');
        return;
      }
      if (openGate != null) {
        warnings.add(
          'Line $number: sw_enable_start inside another block; ignored',
        );
        return;
      }
      for (final name in colourNamesIn(value)) {
        markerUses.add((line: number, name: name));
      }
      final colon = value.indexOf(':');
      if (colon >= 0 || value.contains('|')) {
        warnings.add(
          'Line $number: sw_enable_start takes a label only; the rest is '
          'ignored',
        );
      }
      final bar = value.indexOf('|');
      final cut = [
        colon,
        bar,
      ].where((i) => i >= 0).fold<int>(value.length, (a, b) => a < b ? a : b);
      final item = _buildItem(
        ChecklistItemType.option,
        value.substring(0, cut),
        '',
      );
      if (item.label.isEmpty) {
        warnings.add('Line $number: sw_enable_start has no label; ignored');
        return;
      }
      openGate = items.length;
      openGateLine = number;
      items.add(item);
    }

    void endGate(int number) {
      if (currentItems == null) {
        warnings.add('Line $number: item before any checklist');
      } else if (openGate == null) {
        warnings.add('Line $number: sw_enable_end without sw_enable_start');
      } else {
        openGate = null;
      }
    }

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final kv = splitKeywordValue(line.text);
      if (kv == null) {
        final bare = line.text.toLowerCase();
        if (bare == 'sw_define_colour') {
          warnings.add('Line ${line.number}: bad colour definition');
        } else if (bare == 'sw_continue') {
          addContinue(index, '');
        } else if (bare == 'sw_show') {
          // sw_show is ignored like a comment (D-70).
        } else if (bare == 'sw_enable_end') {
          endGate(line.number);
        } else if (bare == 'sw_enable_start') {
          startGate(line.number, '');
        } else if (!_ignoredKeywords.contains(bare)) {
          // Ignored keywords may appear bare, e.g. `sw_rcolsize` (K3).
          warnings.add('Line ${line.number}: unrecognized line');
        }
      } else if (kv.keyword == 'sw_show') {
        // Conditional display is not supported; the line is ignored like a
        // comment, with no warning and no effect (K6, D-70).
      } else if (kv.keyword == 'sw_continue') {
        addContinue(index, kv.value);
      } else if (kv.keyword == 'sw_enable_start') {
        startGate(line.number, kv.value);
      } else if (kv.keyword == 'sw_enable_end') {
        endGate(line.number);
      } else if (kv.keyword == 'sw_define_colour') {
        final definition = parseColourDefinition(kv.value);
        if (definition == null) {
          warnings.add('Line ${line.number}: bad colour definition');
        } else {
          final colour = definition.colour;
          if (definition.clamped) {
            warnings.add(
              'Line ${line.number}: colour component out of range; clamped',
            );
          }
          if (colours.containsKey(colour.name)) {
            warnings.add(
              'Line ${line.number}: duplicate colour "${colour.name}"; '
              'first definition kept',
            );
          } else {
            colours[colour.name] = colour;
          }
        }
      } else if (kv.keyword == 'sw_checklist') {
        closeOpenGate();
        var checklist = _parseChecklistHeader(kv.value);
        if (checklist.name.isEmpty) {
          untitledCount++;
          final name = 'Untitled checklist $untitledCount';
          warnings.add('Line ${line.number}: checklist has no name');
          checklist = Checklist(
            name: name,
            title: checklist.title.isEmpty ? name : checklist.title,
            items: const [],
          );
        }
        final unique = _uniqueName(checklist.name, usedNames);
        if (unique != checklist.name) {
          warnings.add(
            'Line ${line.number}: duplicate checklist name '
            '"${checklist.name}"; renamed to "$unique"',
          );
          checklist = Checklist(
            name: unique,
            title: checklist.title == checklist.name ? unique : checklist.title,
            items: const [],
          );
        }
        usedNames.add(unique);
        checklists.add(checklist);
        currentItems = [];
        itemLists.add(currentItems);
        currentContinues = [];
        continueLists.add(currentContinues);
        headerLines.add(line.number);
      } else if (_itemKeywords.contains(kv.keyword)) {
        if (currentItems == null) {
          warnings.add('Line ${line.number}: item before any checklist');
        } else {
          final value = kv.value;
          for (final name in colourNamesIn(value)) {
            markerUses.add((line: line.number, name: name));
          }
          var item = switch (kv.keyword) {
            'sw_item' || 'sw_item_c' => _parseCheckItem(value),
            'sw_iteminfo' => _parseCheckItem(value, ChecklistItemType.note),
            'sw_item_details' || 'sw_item_details_c' => _buildItem(
              ChecklistItemType.details,
              value,
              '',
            ),
            'sw_item_heading' || 'sw_item_heading_c' => _parseHeading(value),
            'sw_remark' => _buildItem(ChecklistItemType.note, value, ''),
            _ => _parseNote(value),
          };
          if (_conditionKeywords.contains(kv.keyword)) {
            // An info line's condition is checked for errors but not used (W5).
            final parsed = _conditions.parse(_itemConditionText(value));
            if (parsed.failed) {
              warnings.add(
                'Line ${line.number}: condition not supported: '
                '${parsed.reason}',
              );
            } else if (parsed.condition != null &&
                item.type == ChecklistItemType.check) {
              item = _withCondition(item, parsed.condition!);
            }
          }
          if (_labelledKeywords.contains(kv.keyword) && item.label.isEmpty) {
            warnings.add('Line ${line.number}: item has no label');
          } else if ((item.type == ChecklistItemType.heading ||
                  item.type == ChecklistItemType.details) &&
              item.label.isEmpty) {
            final kind = item.type == ChecklistItemType.heading
                ? 'heading'
                : 'details';
            warnings.add('Line ${line.number}: $kind has no text');
          } else if (item.type == ChecklistItemType.note &&
              !_labelledKeywords.contains(kv.keyword) &&
              item.label.isEmpty &&
              item.result.isEmpty) {
            warnings.add('Line ${line.number}: empty note');
          } else {
            final gate = openGate;
            currentItems.add(gate == null ? item : _withGate(item, gate));
          }
        }
      } else if (!_ignoredKeywords.contains(kv.keyword)) {
        warnings.add('Line ${line.number}: unknown keyword "${kv.keyword}"');
      }
    }
    closeOpenGate();
    for (final use in markerUses) {
      if (!colours.containsKey(use.name)) {
        warnings.add('Line ${use.line}: unknown colour "${use.name}"');
      }
    }
    final keptNames = <String>{};
    final headerLineKept = <int, bool>{};
    for (var i = 0; i < checklists.length; i++) {
      headerLineKept[headerLines[i]] = itemLists[i].isNotEmpty;
      if (itemLists[i].isNotEmpty) keptNames.add(checklists[i].name);
    }
    final headerName = {
      for (var i = 0; i < checklists.length; i++)
        headerLines[i]: checklists[i].name,
    };
    final kept = <Checklist>[];
    for (var i = 0; i < checklists.length; i++) {
      final c = checklists[i];
      if (itemLists[i].isEmpty) {
        warnings.add(
          'Line ${headerLines[i]}: checklist "${c.name}" has no items; '
          'dropped',
        );
      } else {
        final links = <ContinueLink>[];
        for (final pending in continueLists[i]) {
          final warning = _validateContinue(
            pending,
            keptNames,
            headerLineKept,
            headerName,
          );
          if (warning != null) warnings.add(warning);
          if (!pending.dropped) links.add(pending.link);
        }
        kept.add(
          Checklist(
            name: c.name,
            title: c.title,
            items: itemLists[i],
            continues: links,
          ),
        );
      }
    }
    if (kept.isEmpty) warnings.add('No checklists found');
    return ChecklistDocument(
      checklists: kept,
      warnings: warnings,
      colours: colours,
    );
  }

  static const _conditions = ConditionExpressionParser();

  ChecklistItem _withCondition(ChecklistItem item, ItemCondition condition) =>
      ChecklistItem(
        item.type,
        item.label,
        item.result,
        item.labelRuns,
        item.resultRuns,
        condition,
        item.justify,
        item.gate,
      );

  ChecklistItem _withGate(ChecklistItem item, int gate) => ChecklistItem(
    item.type,
    item.label,
    item.result,
    item.labelRuns,
    item.resultRuns,
    item.condition,
    item.justify,
    gate,
  );

  /// The condition text of a check or info line: after the first `:` that
  /// follows the label and the optional `|result` (`GRAMMAR.md` W1).
  String _itemConditionText(String value) {
    final colon = value.indexOf(':');
    if (colon < 0) return '';
    final bar = value.indexOf('|');
    if (bar >= 0 && bar < colon) {
      final rest = value.substring(bar + 1);
      final second = rest.indexOf(':');
      return second < 0 ? '' : rest.substring(second + 1);
    }
    return value.substring(colon + 1);
  }

  String _uniqueName(String name, Set<String> used) {
    if (!used.contains(name)) return name;
    var n = 2;
    while (used.contains('$name ($n)')) {
      n++;
    }
    return '$name ($n)';
  }

  /// Builds an item from raw label and result text that may hold colour
  /// markers. Runs are kept only for a field that has a coloured run.
  ChecklistItem _buildItem(
    ChecklistItemType type,
    String label,
    String result, {
    ChecklistJustify justify = ChecklistJustify.center,
  }) {
    final labelRuns = parseColourRuns(label);
    final resultRuns = parseColourRuns(result);
    return ChecklistItem(
      type,
      _joinRuns(labelRuns),
      _joinRuns(resultRuns),
      _keepRuns(labelRuns),
      _keepRuns(resultRuns),
      null,
      justify,
    );
  }

  String _joinRuns(List<ColourRun> runs) => runs.map((r) => r.text).join();

  List<ColourRun> _keepRuns(List<ColourRun> runs) =>
      runs.any((r) => r.colour != null) ? List.unmodifiable(runs) : const [];

  /// `sw_item_heading:Text|j`: `j` is `left`, `center` or `right` (any case).
  /// Without a valid `j` the whole value is the text, centred.
  ChecklistItem _parseHeading(String value) {
    var text = value;
    var justify = ChecklistJustify.center;
    final bar = value.lastIndexOf('|');
    if (bar >= 0) {
      final parsed =
          _justifyNames[value.substring(bar + 1).trim().toLowerCase()];
      if (parsed != null) {
        text = value.substring(0, bar);
        justify = parsed;
      }
    }
    return _buildItem(ChecklistItemType.heading, text, '', justify: justify);
  }

  ChecklistItem _parseNote(String value) {
    final pipe = value.indexOf('|');
    if (pipe < 0) return _buildItem(ChecklistItemType.note, value, '');
    return _buildItem(
      ChecklistItemType.note,
      value.substring(0, pipe),
      value.substring(pipe + 1),
    );
  }

  ChecklistItem _parseCheckItem(
    String value, [
    ChecklistItemType type = ChecklistItemType.check,
  ]) {
    final pipe = value.indexOf('|');
    final colon = value.indexOf(':');
    // A colon before any pipe starts the dataref part (see 3.10).
    if (pipe < 0 || (colon >= 0 && colon < pipe)) {
      final label = colon < 0 ? value : value.substring(0, colon);
      return _buildItem(type, label, '');
    }
    final rest = value.substring(pipe + 1);
    final resultEnd = rest.indexOf(':');
    final result = resultEnd < 0 ? rest : rest.substring(0, resultEnd);
    return _buildItem(type, value.substring(0, pipe), result);
  }

  Checklist _parseChecklistHeader(String value) {
    final colon = value.indexOf(':');
    final name = (colon < 0 ? value : value.substring(0, colon)).trim();
    final menu = colon < 0 ? '' : value.substring(colon + 1).trim();
    return Checklist(
      name: name,
      title: menu.isNotEmpty ? menu : name,
      items: const [],
    );
  }
}

/// What follows a `sw_continue` line, ignoring blanks, comments and other
/// `sw_continue` lines.
enum _Follow { checklist, item, other, end }

/// A `sw_continue` link waiting for the whole file to be read, so that its
/// target can be checked against every checklist (`GRAMMAR.md` F2a, F2b, F3).
class _PendingContinue {
  _PendingContinue(this.link, this.line, this.follow, this.headerLine);

  final ContinueLink link;
  final int line;
  final _Follow follow;

  /// Line of the `sw_checklist` that follows, when [follow] is `checklist`.
  final int? headerLine;

  /// Set when the link is invalid and must not be kept.
  bool dropped = false;
}

bool _isContinueLine(String text) {
  if (text.toLowerCase() == 'sw_continue') return true;
  return splitKeywordValue(text)?.keyword == 'sw_continue';
}

bool _isShowLine(String text) {
  if (text.toLowerCase() == 'sw_show') return true;
  return splitKeywordValue(text)?.keyword == 'sw_show';
}

({_Follow kind, int? headerLine}) _lookAhead(List<NumberedLine> lines, int at) {
  var next = at + 1;
  while (next < lines.length &&
      (_isContinueLine(lines[next].text) || _isShowLine(lines[next].text))) {
    next++;
  }
  if (next >= lines.length) return (kind: _Follow.end, headerLine: null);
  final kv = splitKeywordValue(lines[next].text);
  if (kv?.keyword == 'sw_checklist') {
    return (kind: _Follow.checklist, headerLine: lines[next].number);
  }
  if (kv != null &&
      (_itemKeywords.contains(kv.keyword) || kv.keyword == 'sw_enable_start')) {
    return (kind: _Follow.item, headerLine: null);
  }
  return (kind: _Follow.other, headerLine: null);
}

/// Checks [pending] against the kept checklists; returns a warning or null.
///
/// An invalid link is marked dropped. A named link is valid if a kept
/// checklist has that name. A bare link is valid only if a kept checklist
/// follows it directly.
String? _validateContinue(
  _PendingContinue pending,
  Set<String> keptNames,
  Map<int, bool> headerLineKept,
  Map<int, String> headerName,
) {
  final target = pending.link.target;
  if (target != null) {
    if (!keptNames.contains(target)) {
      pending.dropped = true;
      return 'Line ${pending.line}: continue target "$target" not found';
    }
    if (pending.follow == _Follow.item) {
      return 'Line ${pending.line}: sw_continue should be at the end of '
          'its checklist';
    }
    return null;
  }
  if (pending.follow != _Follow.checklist) {
    pending.dropped = true;
    return 'Line ${pending.line}: sw_continue without a name is not followed '
        'by a checklist';
  }
  if (headerLineKept[pending.headerLine] != true) {
    pending.dropped = true;
    final name = headerName[pending.headerLine] ?? '';
    return 'Line ${pending.line}: continue target "$name" not found';
  }
  return null;
}

const _itemKeywords = {
  'sw_item',
  'sw_item_c',
  'sw_item_details',
  'sw_item_details_c',
  'sw_item_heading',
  'sw_item_heading_c',
  'sw_itemvoid',
  'sw_itemvoid_c',
  'sw_iteminfo',
  'sw_remark',
};

/// Valid keywords that are skipped without a warning (`GRAMMAR.md` K3).
const _ignoredKeywords = {'sw_rcolsize'};

/// Keywords whose lines are items and so need a label (`GRAMMAR.md` I6).
const _labelledKeywords = {'sw_item', 'sw_item_c', 'sw_iteminfo'};

/// Keywords whose lines can end in a dataref condition.
const _conditionKeywords = {'sw_item', 'sw_item_c', 'sw_iteminfo'};

/// The justify texts of `sw_item_heading`, lower case.
const _justifyNames = {
  'left': ChecklistJustify.left,
  'center': ChecklistJustify.center,
  'centre': ChecklistJustify.center,
  'right': ChecklistJustify.right,
};

/// A line split at its first `:`; [keyword] is lower-cased, both are trimmed.
typedef KeywordValue = ({String keyword, String value});

/// Splits [line] on its first `:`; null if there is no `:` or no keyword.
KeywordValue? splitKeywordValue(String line) {
  final colon = line.indexOf(':');
  if (colon <= 0) return null;
  final keyword = line.substring(0, colon).trim().toLowerCase();
  if (keyword.isEmpty) return null;
  return (keyword: keyword, value: line.substring(colon + 1).trim());
}

/// Parses the value of `sw_define_colour`, `name:r,g,b` (`GRAMMAR.md` C5).
///
/// Returns null unless the name is non-empty and there are exactly three
/// finite numbers. Padding around every part is trimmed. Components outside 0
/// to 1 are clamped, as the real plugin does, and [clamped] says so.
({ChecklistColour colour, bool clamped})? parseColourDefinition(String value) {
  final colon = value.indexOf(':');
  if (colon < 0) return null;
  final name = value.substring(0, colon).trim();
  if (name.isEmpty) return null;
  final parts = value.substring(colon + 1).split(',');
  if (parts.length != 3) return null;
  final components = <double>[];
  var clamped = false;
  for (final part in parts) {
    final number = double.tryParse(part.trim());
    if (number == null || !number.isFinite) return null;
    if (number < 0 || number > 1) clamped = true;
    components.add(number.clamp(0.0, 1.0));
  }
  return (
    colour: ChecklistColour(name, components[0], components[1], components[2]),
    clamped: clamped,
  );
}

/// Converts `\r\n` and lone `\r` to `\n` and strips a leading BOM (`﻿`).
String normalizeLineEndingsAndBom(String text) {
  final withoutBom = text.startsWith('﻿') ? text.substring(1) : text;
  return withoutBom.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

/// One non-empty, non-comment line with its 1-based physical line number.
typedef NumberedLine = ({int number, String text});

/// Numbers, trims and filters the lines of [text] (already normalized).
///
/// Trims each line, strips one leading `@` and trims again, then drops empty
/// lines and lines starting with `#`. Numbers count skipped lines too.
List<NumberedLine> preprocessLines(String text) {
  final result = <NumberedLine>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    if (line.startsWith('@')) line = line.substring(1).trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    result.add((number: i + 1, text: line));
  }
  return result;
}

final _markerPattern = RegExp(r'\\\\|\\[^\\:|]+\\');

/// Removes `\NAME\` colour markers and `\\` return markers.
String stripColourMarkers(String text) => text.replaceAll(_markerPattern, '');

/// The names of the `\NAME\` markers in [raw], without repeats, in order.
List<String> colourNamesIn(String raw) => {
  for (final m in _markerPattern.allMatches(raw))
    if (m[0] != r'\\') m[0]!.substring(1, m[0]!.length - 1),
}.toList();

/// Splits [raw] text with `\NAME\` markers into trimmed colour runs.
///
/// A marker colours the text after it until the next marker; text before the
/// first marker has no colour. As in the real plugin, markers form a stack:
/// `\\` returns to the colour before the last marker, or the default colour if
/// there is none (`GRAMMAR.md` C1 to C3). Adjacent runs of one colour are
/// merged and empty runs are dropped. Joined, the runs equal
/// `stripColourMarkers(raw).trim()`.
List<ColourRun> parseColourRuns(String raw) {
  final stack = <String>[];
  final runs = <ColourRun>[];
  final text = StringBuffer();
  String? colour;
  void flush() {
    if (text.isEmpty) return;
    if (runs.isNotEmpty && runs.last.colour == colour) {
      runs[runs.length - 1] = ColourRun(
        runs.last.text + text.toString(),
        colour,
      );
    } else {
      runs.add(ColourRun(text.toString(), colour));
    }
    text.clear();
  }

  var position = 0;
  for (final m in _markerPattern.allMatches(raw)) {
    text.write(raw.substring(position, m.start));
    position = m.end;
    flush();
    if (m[0] == r'\\') {
      if (stack.isNotEmpty) stack.removeLast();
    } else {
      stack.add(m[0]!.substring(1, m[0]!.length - 1));
    }
    colour = stack.isEmpty ? null : stack.last;
  }
  text.write(raw.substring(position));
  flush();
  return _trimRuns(runs);
}

List<ColourRun> _trimRuns(List<ColourRun> runs) {
  final trimmed = [...runs];
  while (trimmed.isNotEmpty && trimmed.first.text.trimLeft().isEmpty) {
    trimmed.removeAt(0);
  }
  while (trimmed.isNotEmpty && trimmed.last.text.trimRight().isEmpty) {
    trimmed.removeLast();
  }
  if (trimmed.isEmpty) return trimmed;
  trimmed[0] = ColourRun(trimmed.first.text.trimLeft(), trimmed.first.colour);
  final last = trimmed.length - 1;
  trimmed[last] = ColourRun(trimmed.last.text.trimRight(), trimmed.last.colour);
  return trimmed;
}
