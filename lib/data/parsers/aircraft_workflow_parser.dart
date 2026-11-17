import '../../domain/models/checklist/calculate_line.dart';
import '../../domain/models/checklist/checklist.dart';
import '../../domain/models/checklist/checklist_colour.dart';
import '../../domain/models/checklist/checklist_document.dart';
import '../../domain/models/checklist/checklist_item.dart';
import '../../domain/models/checklist/colour_run.dart';
import '../../domain/models/checklist/continue_link.dart';
import '../../domain/models/checklist/lookup_table.dart';
import '../../domain/models/checklist/switch_gate.dart';
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
    // The open switch block, if any (section 5b): its switch, the position in
    // which the branch before `sw_else` is shown, and whether `sw_else` was
    // seen. [ignoredBlocks] counts blocks that were started but ignored, so
    // their `sw_else` and `sw_end` do not touch the open one.
    SwitchDef? openSwitch;
    var openFirstWhen = true;
    var openInElse = false;
    var openKeyword = '';
    var openLine = 0;
    var ignoredBlocks = 0;
    // The open challenge block, if any (section 5d): its line, and the serial
    // of the switch block it opened inside (0 for none). [challengeCut] is set
    // when a switch boundary closed it, so the `sw_challenge: OFF` that follows
    // is taken without a second warning.
    var challengeOpen = false;
    var challengeLine = 0;
    var challengeSerial = 0;
    var challengeCut = false;
    var blockSerial = 0;
    final switchDefs = <String, SwitchDef>{};
    final ifUses = <({int line, String id})>[];

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

    // A block ends at `sw_end`; one still open when its checklist or the file
    // ends is closed there, with a warning (G5).
    void closeOpenBlock() {
      if (challengeOpen) {
        warnings.add(
          'Line $challengeLine: sw_challenge: ON has no OFF; '
          'closed at the end of the checklist',
        );
        challengeOpen = false;
      }
      challengeCut = false;
      if (openSwitch != null) {
        warnings.add(
          'Line $openLine: $openKeyword has no sw_end; '
          'closed at the end of the checklist',
        );
        openSwitch = null;
      }
      ignoredBlocks = 0;
    }

    // Reads the on/off word of a block start; [fallback] when it is bad.
    bool readState(int number, String keyword, String? word, bool fallback) {
      if (word == null || word.isEmpty) return fallback;
      switch (word.toLowerCase()) {
        case 'on':
          return true;
        case 'off':
          return false;
      }
      warnings.add(
        'Line $number: $keyword state must be ON or OFF; '
        '${fallback ? 'ON' : 'OFF'} assumed',
      );
      return fallback;
    }

    // Starts a block of [keyword] on [switchDef]; the branch before `sw_else`
    // is shown while the switch is [firstWhen].
    void openBlock(
      int number,
      String keyword,
      SwitchDef switchDef,
      bool firstWhen,
    ) {
      blockSerial++;
      openSwitch = switchDef;
      openFirstWhen = firstWhen;
      openInElse = false;
      openKeyword = keyword;
      openLine = number;
    }

    // `sw_switch:Label|id|ON` and `sw_if|id|ON`.
    void startBlock(int number, String keyword, String value) {
      final items = currentItems;
      if (items == null) {
        warnings.add('Line $number: item before any checklist');
        return;
      }
      if (openSwitch != null || ignoredBlocks > 0) {
        warnings.add('Line $number: $keyword inside another block; ignored');
        ignoredBlocks++;
        return;
      }
      final parts = value.split('|');
      final isSwitch = keyword == 'sw_switch';
      final labelText = isSwitch ? parts.first : '';
      final idIndex = isSwitch ? 1 : 0;
      final id = parts.length > idIndex ? parts[idIndex].trim() : '';
      final stateWord = parts.length > idIndex + 1
          ? parts[idIndex + 1].trim()
          : null;
      if (parts.length > idIndex + 2) {
        warnings.add('Line $number: $keyword has extra parts; ignored');
      }
      if (isSwitch) {
        for (final name in colourNamesIn(labelText)) {
          markerUses.add((line: number, name: name));
        }
      }
      final row = isSwitch
          ? _buildItem(ChecklistItemType.option, labelText, '')
          : null;
      if (row != null && row.label.isEmpty) {
        warnings.add('Line $number: sw_switch has no label; ignored');
        ignoredBlocks++;
        return;
      }
      if (id.isEmpty) {
        warnings.add('Line $number: $keyword has no switch id; ignored');
        ignoredBlocks++;
        return;
      }
      final key = id.toLowerCase();
      if (row == null) {
        final first = readState(number, keyword, stateWord, true);
        ifUses.add((line: number, id: key));
        openBlock(number, keyword, SwitchDef(key), first);
        return;
      }
      final known = switchDefs[key];
      if (known != null) {
        warnings.add(
          'Line $number: duplicate switch "$key"; first definition kept, '
          'no switch row',
        );
        openBlock(number, keyword, known, true);
        return;
      }
      final def = SwitchDef(
        key,
        defaultOn: readState(number, keyword, stateWord, false),
      );
      switchDefs[key] = def;
      items.add(
        challengeOpen
            ? _asChallenge(_withSwitch(row, def))
            : _withSwitch(row, def),
      );
      openBlock(number, keyword, def, true);
    }

    // A challenge block that opened inside the switch block now ending, or
    // changing branch, stops there (C5).
    void cutChallengeAtBoundary(int number) {
      if (challengeOpen && challengeSerial == blockSerial) {
        warnings.add(
          'Line $number: sw_challenge crosses a switch block; '
          'closed at the block boundary',
        );
        challengeOpen = false;
        challengeCut = true;
      }
    }

    // `sw_challenge: ON` and `sw_challenge: OFF`.
    void challengeLineFor(int number, String value) {
      if (currentItems == null) {
        warnings.add('Line $number: item before any checklist');
        return;
      }
      switch (value.trim().toLowerCase()) {
        case 'on':
          if (challengeOpen) {
            warnings.add(
              'Line $number: sw_challenge: ON inside a challenge block; '
              'ignored',
            );
          } else {
            challengeOpen = true;
            challengeCut = false;
            challengeLine = number;
            challengeSerial = openSwitch == null ? 0 : blockSerial;
          }
        case 'off':
          if (challengeOpen) {
            if (openSwitch != null && challengeSerial != blockSerial) {
              warnings.add(
                'Line $number: sw_challenge crosses a switch block; '
                'closed at the block boundary',
              );
            }
            challengeOpen = false;
          } else if (challengeCut) {
            challengeCut = false;
          } else {
            warnings.add('Line $number: sw_challenge: OFF without ON');
          }
        default:
          warnings.add('Line $number: sw_challenge needs ON or OFF; ignored');
      }
    }

    void elseBlock(int number) {
      if (currentItems == null) {
        warnings.add('Line $number: item before any checklist');
      } else if (ignoredBlocks > 0) {
        // The ignored block was already reported.
      } else if (openSwitch == null) {
        warnings.add('Line $number: sw_else without sw_if or sw_switch');
      } else if (openInElse) {
        warnings.add('Line $number: second sw_else in a block; ignored');
      } else {
        cutChallengeAtBoundary(number);
        openInElse = true;
      }
    }

    void endBlock(int number) {
      if (currentItems == null) {
        warnings.add('Line $number: item before any checklist');
      } else if (ignoredBlocks > 0) {
        ignoredBlocks--;
      } else if (openSwitch == null) {
        warnings.add('Line $number: sw_end without sw_if or sw_switch');
      } else {
        cutChallengeAtBoundary(number);
        openSwitch = null;
      }
    }

    // The branch an item read now belongs to, or null outside a block.
    SwitchGate? currentGate() {
      final open = openSwitch;
      if (open == null) return null;
      return SwitchGate(
        open,
        whenOn: openInElse ? !openFirstWhen : openFirstWhen,
      );
    }

    // Lookup tables (section 5c): the open `sw_table` block being read, whether
    // a rejected block is being skipped, and the `sw_calculate` lines waiting
    // for the tables, which are defined anywhere in the file.
    _TableBuilder? openTable;
    var skippingTable = false;
    final tables = <String, LookupTable>{};
    final pendingCalcs = <_PendingCalc>[];

    void finishTable(_TableBuilder table) {
      final problem = LookupTable.problem(table.inputs.length, table.rows);
      if (problem != null) {
        warnings.add(
          'Line ${table.line}: sw_table "${table.name}" $problem; ignored',
        );
        return;
      }
      tables[table.name] = LookupTable(
        name: table.name,
        inputs: table.inputs,
        outputs: table.outputs,
        rows: table.rows,
      );
    }

    // A table still open when another line comes, or at the end of the file,
    // is closed there (G5's rule for tables, L5).
    void closeOpenTable() {
      final table = openTable;
      if (table == null) return;
      openTable = null;
      warnings.add(
        'Line ${table.line}: sw_table "${table.name}" has no sw_table_end; '
        'closed there',
      );
      finishTable(table);
    }

    // `sw_table:name|col=source,col=source|out,out`.
    void startTable(int number, String value) {
      closeOpenTable();
      skippingTable = false;
      final parts = value.split('|');
      if (parts.length != 3) {
        warnings.add(
          'Line $number: sw_table needs name|inputs|outputs; ignored',
        );
        skippingTable = true;
        return;
      }
      final name = parts[0].trim().toLowerCase();
      if (!_tableName.hasMatch(name)) {
        warnings.add('Line $number: sw_table has a bad name "$name"; ignored');
        skippingTable = true;
        return;
      }
      if (tables.containsKey(name)) {
        warnings.add(
          'Line $number: duplicate table "$name"; first definition kept',
        );
        skippingTable = true;
        return;
      }
      final used = <String>{};
      final inputs = <TableInput>[];
      for (final text in _splitTopLevel(parts[1], ',')) {
        final equals = text.indexOf('=');
        // `name`, or `name(Label, unit)`.
        final spec = equals < 0
            ? null
            : _inputSpec.firstMatch(text.substring(0, equals).trim());
        final column = spec?.group(1)?.toLowerCase() ?? '';
        if (spec == null || !_tableName.hasMatch(column) || !used.add(column)) {
          warnings.add(
            'Line $number: sw_table "$name" has a bad or repeated input '
            'column "${equals < 0 ? text.trim() : text.substring(0, equals).trim()}"; ignored',
          );
          skippingTable = true;
          return;
        }
        final shown = (spec.group(2) ?? '').split(',');
        final label = shown.first.trim();
        final unit = shown.skip(1).join(',').trim();
        final source = _conditions.parseValue(text.substring(equals + 1));
        if (source.failed) {
          warnings.add(
            'Line $number: sw_table "$name" input "$column": '
            '${source.reason}; ignored',
          );
          skippingTable = true;
          return;
        }
        inputs.add(TableInput(column, source.value!, label: label, unit: unit));
      }
      final outputs = <String>[];
      for (final text in parts[2].split(',')) {
        final column = text.trim().toLowerCase();
        if (!_tableName.hasMatch(column) || !used.add(column)) {
          warnings.add(
            'Line $number: sw_table "$name" has a bad or repeated output '
            'column "${text.trim()}"; ignored',
          );
          skippingTable = true;
          return;
        }
        outputs.add(column);
      }
      if (inputs.isEmpty || inputs.length > LookupTable.maxInputs) {
        warnings.add(
          'Line $number: sw_table "$name" needs 1 to '
          '${LookupTable.maxInputs} input columns; ignored',
        );
        skippingTable = true;
        return;
      }
      openTable = _TableBuilder(name, number, inputs, outputs);
    }

    // `sw_row:in,in|out,out`.
    void addRow(int number, String value) {
      final table = openTable;
      if (table == null) {
        if (!skippingTable) {
          warnings.add('Line $number: sw_row outside sw_table; ignored');
        }
        return;
      }
      final parts = value.split('|');
      final inputs = parts.length == 2 ? _numbers(parts[0]) : null;
      final outputs = parts.length == 2 ? _numbers(parts[1]) : null;
      if (inputs == null || outputs == null) {
        warnings.add(
          'Line $number: sw_row needs numbers as in,in|out,out; row skipped',
        );
      } else if (inputs.length != table.inputs.length ||
          outputs.length != table.outputs.length) {
        warnings.add(
          'Line $number: sw_row has ${inputs.length} input and '
          '${outputs.length} output values; table "${table.name}" needs '
          '${table.inputs.length} and ${table.outputs.length}; row skipped',
        );
      } else {
        table.rows.add(TableRow(inputs, outputs));
      }
    }

    void endTable(int number) {
      final table = openTable;
      if (table != null) {
        openTable = null;
        finishTable(table);
      } else if (skippingTable) {
        skippingTable = false;
      } else {
        warnings.add('Line $number: sw_table_end without sw_table');
      }
    }

    // `sw_calculate:table|column|Label|unit|step`: shown under the check item
    // above it (details lines may sit between).
    void addCalculate(int number, String value) {
      final items = currentItems;
      if (items == null) {
        warnings.add('Line $number: item before any checklist');
        return;
      }
      final parts = value.split('|');
      final tableName = parts[0].trim().toLowerCase();
      final column = parts.length > 1 ? parts[1].trim().toLowerCase() : '';
      if (tableName.isEmpty || column.isEmpty) {
        warnings.add('Line $number: sw_calculate needs table|column; ignored');
        return;
      }
      if (parts.length > 5) {
        warnings.add('Line $number: sw_calculate has extra parts; ignored');
      }
      var step = 1.0;
      if (parts.length > 4 && parts[4].trim().isNotEmpty) {
        final parsed = double.tryParse(parts[4].trim());
        if (parsed == null || parsed <= 0 || !parsed.isFinite) {
          warnings.add(
            'Line $number: sw_calculate rounding must be a number above 0; '
            '1 assumed',
          );
        } else {
          step = parsed;
        }
      }
      var target = items.length - 1;
      while (target >= 0 && items[target].type == ChecklistItemType.details) {
        target--;
      }
      if (target < 0 ||
          (items[target].type != ChecklistItemType.check &&
              items[target].type != ChecklistItemType.heading)) {
        warnings.add(
          'Line $number: sw_calculate is not under a check item or heading; '
          'ignored',
        );
        return;
      }
      final label = parts.length > 2 ? parts[2].trim() : '';
      pendingCalcs.add(
        _PendingCalc(
          items,
          target,
          number,
          CalculateLine(
            table: tableName,
            column: column,
            label: label.isEmpty ? column : label,
            unit: parts.length > 3 ? parts[3].trim() : '',
            step: step,
          ),
        ),
      );
    }

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final kv = splitKeywordValue(line.text);
      // Only `sw_row` and `sw_table_end` belong inside a table; any other line
      // ends it (a rejected table's rows are skipped only up to there too).
      final isRow = kv != null && kv.keyword == 'sw_row';
      final isTableEnd =
          line.text.toLowerCase() == 'sw_table_end' ||
          (kv != null && kv.keyword == 'sw_table_end');
      if (!isRow && !isTableEnd) {
        closeOpenTable();
        skippingTable = false;
      }
      if (kv != null && kv.keyword == 'sw_table') {
        startTable(line.number, kv.value);
      } else if (isRow) {
        addRow(line.number, kv.value);
      } else if (isTableEnd) {
        endTable(line.number);
      } else if (kv != null && kv.keyword == 'sw_calculate') {
        addCalculate(line.number, kv.value);
      } else if (kv == null && _isIfLine(line.text)) {
        startBlock(line.number, 'sw_if', _ifValue(line.text));
      } else if (kv == null) {
        final bare = line.text.toLowerCase();
        if (bare == 'sw_define_colour') {
          warnings.add('Line ${line.number}: bad colour definition');
        } else if (bare == 'sw_continue') {
          addContinue(index, '');
        } else if (bare == 'sw_show') {
          // sw_show is ignored like a comment (D-70).
        } else if (bare == 'sw_challenge') {
          challengeLineFor(line.number, '');
        } else if (bare == 'sw_end') {
          endBlock(line.number);
        } else if (bare == 'sw_else') {
          elseBlock(line.number);
        } else if (bare == 'sw_switch') {
          startBlock(line.number, 'sw_switch', '');
        } else if (!_ignoredKeywords.contains(bare)) {
          // Ignored keywords may appear bare, e.g. `sw_rcolsize` (K3).
          warnings.add('Line ${line.number}: unrecognized line');
        }
      } else if (kv.keyword == 'sw_show') {
        // Conditional display is not supported; the line is ignored like a
        // comment, with no warning and no effect (K6, D-70).
      } else if (kv.keyword == 'sw_continue') {
        addContinue(index, kv.value);
      } else if (kv.keyword == 'sw_challenge') {
        challengeLineFor(line.number, kv.value);
      } else if (kv.keyword == 'sw_switch') {
        startBlock(line.number, 'sw_switch', kv.value);
      } else if (kv.keyword == 'sw_end') {
        endBlock(line.number);
      } else if (kv.keyword == 'sw_else') {
        elseBlock(line.number);
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
        closeOpenBlock();
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
            final gate = currentGate();
            if (challengeOpen) item = _asChallenge(item);
            currentItems.add(gate == null ? item : _withGate(item, gate));
          }
        }
      } else if (!_ignoredKeywords.contains(kv.keyword)) {
        warnings.add('Line ${line.number}: unknown keyword "${kv.keyword}"');
      }
    }
    closeOpenBlock();
    closeOpenTable();
    _attachCalculations(pendingCalcs, tables, warnings);
    // A gate takes the default of its switch, defined anywhere in the file; a
    // block that names a switch nobody defines is shown always.
    final unknown = <String>{};
    for (final use in ifUses) {
      if (!switchDefs.containsKey(use.id)) {
        warnings.add(
          'Line ${use.line}: sw_if names the unknown switch "${use.id}"; '
          'its items are always shown',
        );
        unknown.add(use.id);
      }
    }
    for (final list in itemLists) {
      for (var i = 0; i < list.length; i++) {
        final gate = list[i].gate;
        if (gate == null) continue;
        final def = switchDefs[gate.id];
        list[i] = def == null
            ? _withoutGate(list[i])
            : _withGate(list[i], SwitchGate(def, whenOn: gate.whenOn));
      }
    }
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
      tables: tables,
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
        item.switchDef,
        item.calculations,
        item.challenge,
      );

  ChecklistItem _asChallenge(ChecklistItem item) => ChecklistItem(
    item.type,
    item.label,
    item.result,
    item.labelRuns,
    item.resultRuns,
    item.condition,
    item.justify,
    item.gate,
    item.switchDef,
    item.calculations,
    true,
  );

  ChecklistItem _withGate(ChecklistItem item, SwitchGate gate) => ChecklistItem(
    item.type,
    item.label,
    item.result,
    item.labelRuns,
    item.resultRuns,
    item.condition,
    item.justify,
    gate,
    item.switchDef,
    item.calculations,
    item.challenge,
  );

  ChecklistItem _withoutGate(ChecklistItem item) => ChecklistItem(
    item.type,
    item.label,
    item.result,
    item.labelRuns,
    item.resultRuns,
    item.condition,
    item.justify,
    null,
    item.switchDef,
    item.calculations,
    item.challenge,
  );

  ChecklistItem _withSwitch(ChecklistItem item, SwitchDef def) => ChecklistItem(
    item.type,
    item.label,
    item.result,
    item.labelRuns,
    item.resultRuns,
    item.condition,
    item.justify,
    item.gate,
    def,
    item.calculations,
    item.challenge,
  );

  ChecklistItem _withCalculations(
    ChecklistItem item,
    List<CalculateLine> calculations,
  ) => ChecklistItem(
    item.type,
    item.label,
    item.result,
    item.labelRuns,
    item.resultRuns,
    item.condition,
    item.justify,
    item.gate,
    item.switchDef,
    calculations,
    item.challenge,
  );

  /// Gives each item its `sw_calculate` lines once every table is known; a
  /// line that names a missing table or column is dropped with a warning (L6).
  void _attachCalculations(
    List<_PendingCalc> pending,
    Map<String, LookupTable> tables,
    List<String> warnings,
  ) {
    for (final entry in pending) {
      final table = tables[entry.line.table];
      if (table == null) {
        warnings.add(
          'Line ${entry.number}: sw_calculate names the unknown table '
          '"${entry.line.table}"; ignored',
        );
      } else if (!table.hasOutput(entry.line.column)) {
        warnings.add(
          'Line ${entry.number}: table "${table.name}" has no output column '
          '"${entry.line.column}"; sw_calculate ignored',
        );
      } else {
        final item = entry.items[entry.index];
        entry.items[entry.index] = _withCalculations(item, [
          ...item.calculations,
          entry.line,
        ]);
      }
    }
  }

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

/// Whether [text] is a `sw_if|id|state` line: the keyword, then `|` or the end.
bool _isIfLine(String text) {
  final bar = text.indexOf('|');
  final head = (bar < 0 ? text : text.substring(0, bar)).trim().toLowerCase();
  return head == 'sw_if';
}

/// The part of a `sw_if` line after the keyword.
String _ifValue(String text) {
  final bar = text.indexOf('|');
  return bar < 0 ? '' : text.substring(bar + 1);
}

bool _isContinueLine(String text) {
  if (text.toLowerCase() == 'sw_continue') return true;
  return splitKeywordValue(text)?.keyword == 'sw_continue';
}

bool _isChallengeLine(String text) {
  if (text.toLowerCase() == 'sw_challenge') return true;
  return splitKeywordValue(text)?.keyword == 'sw_challenge';
}

bool _isShowLine(String text) {
  if (text.toLowerCase() == 'sw_show') return true;
  return splitKeywordValue(text)?.keyword == 'sw_show';
}

({_Follow kind, int? headerLine}) _lookAhead(List<NumberedLine> lines, int at) {
  var next = at + 1;
  while (next < lines.length &&
      (_isContinueLine(lines[next].text) ||
          _isShowLine(lines[next].text) ||
          _isChallengeLine(lines[next].text))) {
    next++;
  }
  if (next >= lines.length) return (kind: _Follow.end, headerLine: null);
  final kv = splitKeywordValue(lines[next].text);
  if (kv?.keyword == 'sw_checklist') {
    return (kind: _Follow.checklist, headerLine: lines[next].number);
  }
  if (kv != null &&
      (_itemKeywords.contains(kv.keyword) || kv.keyword == 'sw_switch')) {
    return (kind: _Follow.item, headerLine: null);
  }
  if (kv == null && _isIfLine(lines[next].text)) {
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

/// An input column of `sw_table`: a name, and optionally `(Label, unit)`.
final _inputSpec = RegExp(r'^([A-Za-z0-9_]+)\s*(?:\((.*)\))?$', dotAll: true);

/// A name in `sw_table`: a table or a column.
final _tableName = RegExp(r'^[a-z0-9_]+$');

/// Splits [text] at each [separator] that is not inside brackets.
List<String> _splitTopLevel(String text, String separator) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if ('({['.contains(c)) {
      depth++;
    } else if (')}]'.contains(c)) {
      depth--;
    } else if (c == separator && depth <= 0) {
      parts.add(text.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(text.substring(start));
  return parts;
}

/// Reads a comma-separated list of numbers; null when any is not a number.
List<double>? _numbers(String text) {
  final values = <double>[];
  for (final part in text.split(',')) {
    final value = double.tryParse(part.trim());
    if (value == null || !value.isFinite) return null;
    values.add(value);
  }
  return values;
}

/// A `sw_table` block while its rows are being read.
class _TableBuilder {
  _TableBuilder(this.name, this.line, this.inputs, this.outputs);

  final String name;
  final int line;
  final List<TableInput> inputs;
  final List<String> outputs;
  final List<TableRow> rows = [];
}

/// A `sw_calculate` line waiting for its table.
class _PendingCalc {
  _PendingCalc(this.items, this.index, this.number, this.line);

  /// The item list of the checklist it stands in, and the item it belongs to.
  final List<ChecklistItem> items;
  final int index;
  final int number;
  final CalculateLine line;
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
