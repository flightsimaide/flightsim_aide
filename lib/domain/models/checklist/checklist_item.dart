import 'package:equatable/equatable.dart';

import '../flight_sim/item_condition.dart';
import 'colour_run.dart';

/// Kind of line in a checklist.
enum ChecklistItemType {
  /// An item the pilot checks off.
  check,

  /// Informational text that is not checked off.
  note,

  /// A section heading (`sw_item_heading`), aligned by
  /// [ChecklistItem.justify]. Last, so the fingerprint indexes of the older
  /// kinds do not change.
  heading,

  /// A line of text under the item above it (`sw_item_details`): indented,
  /// on a darker band, not checkable.
  details,

  /// A switch row (`sw_enable_start`): the pilot turns the items of its block
  /// on or off (`GRAMMAR.md` section 5b). Last, so the fingerprint indexes of
  /// the older kinds do not change. It is checked off, skipped and counted
  /// like a manual item (auto-check stops at it until the pilot ticks it), and
  /// it also holds the switch.
  option,
}

/// How a heading's text is aligned.
enum ChecklistJustify {
  /// Against the start edge.
  left,

  /// In the middle (the default).
  center,

  /// Against the end edge.
  right,
}

/// One immutable line of a checklist.
class ChecklistItem extends Equatable {
  /// Creates an item; [result] is the expected response, empty if none.
  ///
  /// [labelRuns] and [resultRuns] are empty unless the text had colour
  /// markers.
  const ChecklistItem(
    this.type,
    this.label, [
    this.result = '',
    this.labelRuns = const [],
    this.resultRuns = const [],
    this.condition,
    this.justify = ChecklistJustify.center,
    this.gate,
  ]);

  /// Whether this is a check item or a note.
  final ChecklistItemType type;

  /// The challenge text, without colour markers.
  final String label;

  /// The expected response, without colour markers, empty if none.
  final String result;

  /// The label split into coloured runs; joined they equal [label].
  ///
  /// Empty when the label had no colour markers (the whole label uses the
  /// default colour). Use [labelParts] to get runs in every case.
  final List<ColourRun> labelRuns;

  /// The result split into coloured runs; joined they equal [result].
  ///
  /// Empty when the result had no colour markers. Use [resultParts].
  final List<ColourRun> resultRuns;

  /// The condition that ticks this item by itself when it holds, or null for
  /// a manual item (`GRAMMAR.md` section 8). Only check items carry one.
  final ItemCondition? condition;

  /// The text alignment of a heading; centre for every other kind (unused).
  final ChecklistJustify justify;

  /// The index, in the checklist's items, of the switch row
  /// (`sw_enable_start`) whose block holds this item, or null for an item in
  /// no block. The item counts only while that switch is on. Worked out by the
  /// parser; it is not part of the file syntax.
  final int? gate;

  /// Whether the pilot can tick or skip this line and it is counted: a check
  /// item or a switch row.
  bool get isCheckable =>
      type == ChecklistItemType.check || type == ChecklistItemType.option;

  /// [labelRuns], or one default-colour run holding [label] if there are none.
  List<ColourRun> get labelParts => _parts(label, labelRuns);

  /// [resultRuns], or one default-colour run holding [result] if there are none.
  List<ColourRun> get resultParts => _parts(result, resultRuns);

  static List<ColourRun> _parts(String text, List<ColourRun> runs) {
    if (runs.isNotEmpty) return runs;
    return text.isEmpty ? const [] : [ColourRun(text)];
  }

  @override
  List<Object?> get props => [
    type,
    label,
    result,
    labelRuns,
    resultRuns,
    condition,
    justify,
    gate,
  ];
}
