import 'package:equatable/equatable.dart';

import '../../../domain/models/checklist/checklist_colour.dart';
import '../../../domain/models/checklist/checklist_item.dart';
import '../../../domain/models/checklist/checklist_progress.dart';

/// One line of a checklist as shown on the detail screen.
class ChecklistDetailRow extends Equatable {
  /// Creates a row; [index] is the item's position in its checklist, notes
  /// included, and is what the progress repository is keyed by.
  const ChecklistDetailRow({
    required this.index,
    required this.item,
    required this.checked,
    this.autoChecked = false,
    this.disagreed = false,
    this.skipped = false,
    this.enabled = true,
    this.optionOn = false,
  });

  /// Position of [item] in the checklist.
  final int index;

  /// The checklist line.
  final ChecklistItem item;

  /// Whether the user has checked it; always false for notes.
  final bool checked;

  /// Whether the app checked it from a sim value, not the user. Implies
  /// [checked].
  final bool autoChecked;

  /// Whether the user ticked it by hand while the sim said its condition was
  /// false (D-71). Implies [checked]; shown with a red marker.
  final bool disagreed;

  /// Whether the user skipped it (amber marker). Never also [checked].
  final bool skipped;

  /// Whether the item is enabled: it is in no switch block, or its switch is
  /// on (D-82). A disabled row is greyed out and cannot be ticked.
  final bool enabled;

  /// For a switch row: whether the switch is on. False for every other row.
  final bool optionOn;

  @override
  List<Object?> get props => [
    index,
    item,
    checked,
    autoChecked,
    disagreed,
    skipped,
    enabled,
    optionOn,
  ];
}

/// The user ticked an item the sim says is not set (D-71). The screen shows
/// a red dialog; the tick stands unless the user cancels (the cubit's
/// `cancelTick`), and Acknowledge keeps it.
class TickWarning extends Equatable {
  /// Creates the warning for item [index], whose label is [label]; [before]
  /// is the progress from just before the tick, for backing out.
  const TickWarning({
    required this.index,
    required this.label,
    required this.before,
    this.result = '',
  });

  /// The progress just before the tick.
  final ChecklistProgress before;

  /// Position of the item in its checklist.
  final int index;

  /// The item's label, for the dialog text.
  final String label;

  /// The item's expected result (empty when it has none).
  final String result;

  /// The dialog text: `The simulation value for label result is false.`,
  /// without the result part when the item has none.
  String get message => result.isEmpty
      ? 'The simulation value for $label is false.'
      : 'The simulation value for $label ${result.toLowerCase()} is false.';

  @override
  List<Object?> get props => [index, label, result, before];
}

/// A checklist that follows the current one (from its `sw_continue` links).
class NextChecklist extends Equatable {
  /// Creates a link to the checklist called [name].
  const NextChecklist({required this.name, required this.title});

  /// Name used for the detail route.
  final String name;

  /// Display title.
  final String title;

  @override
  List<Object?> get props => [name, title];
}

/// State of the checklist detail screen.
sealed class ChecklistDetailState extends Equatable {
  const ChecklistDetailState();

  @override
  List<Object?> get props => const [];
}

/// Waiting for the first load.
final class ChecklistDetailLoading extends ChecklistDetailState {
  /// Creates the loading state.
  const ChecklistDetailLoading();
}

/// The checklist with the user's progress.
final class ChecklistDetailLoaded extends ChecklistDetailState {
  /// Creates the loaded state.
  ///
  /// [colours] is the document palette; [next] lists where to go after this
  /// checklist.
  const ChecklistDetailLoaded({
    required this.title,
    required this.rows,
    required this.done,
    required this.total,
    required this.isComplete,
    this.colours = const {},
    this.next = const [],
    this.continueTo,
    this.stayManual = 0,
    this.auto = true,
    this.resets = 0,
    this.pointer,
    this.skipped = 0,
    this.disagreedCount = 0,
    this.canSkip = false,
    this.name = '',
    this.checklists = const [],
    this.nextInFile,
  });

  /// Name of this checklist, as found in the document.
  final String name;

  /// Every checklist of the document in file order, for the button row at the
  /// end of the list (task 0.30).
  final List<NextChecklist> checklists;

  /// The checklist that follows this one in the file, or null for the last.
  /// Continue is hidden when it leads here, because the row is one tap away.
  final NextChecklist? nextInFile;

  /// Number of check items that are neither checked nor skipped.
  int get unchecked => total - done - skipped;

  /// Whether Continue is shown: a link matched and it does not lead to the
  /// next checklist in the file.
  bool get showContinue =>
      continueTo != null && continueTo!.name != nextInFile?.name;

  /// Display title.
  final String title;

  /// Every line, in order, notes included.
  final List<ChecklistDetailRow> rows;

  /// Number of checked check items.
  final int done;

  /// Number of skipped check items.
  final int skipped;

  /// Number of checked items the user ticked against the sim.
  final int disagreedCount;

  /// Whether the Skip button has an item to skip (an open item is left).
  final bool canSkip;

  /// Number of check items.
  final int total;

  /// Whether every check item is checked or skipped (and there is at least
  /// one).
  final bool isComplete;

  /// The document's colour palette, keyed by name.
  final Map<String, ChecklistColour> colours;

  /// Checklists that follow this one, in link order.
  final List<NextChecklist> next;

  /// The checklist to go to now: this one is complete and a `sw_continue`
  /// link matched (D-53). Null when none did or the checklist is not
  /// complete.
  final NextChecklist? continueTo;

  /// How many items cannot be checked by the app because the sim cannot give
  /// the value their condition needs (unknown name or over the limit). They
  /// stay manual.
  final int stayManual;

  /// Whether auto-check is on for this checklist. Reset turns it off.
  final bool auto;

  /// How many times the checklist was reset while open; the screen scrolls to
  /// the top when it changes.
  final int resets;

  /// The row of the item the Check button would tick (the first unchecked
  /// check item at or after the cursor), or null when there is none.
  final int? pointer;

  @override
  List<Object?> get props => [
    title,
    rows,
    done,
    total,
    isComplete,
    colours,
    next,
    continueTo,
    stayManual,
    auto,
    resets,
    pointer,
    skipped,
    disagreedCount,
    canSkip,
    name,
    checklists,
    nextInFile,
  ];
}

/// The checklist cannot be shown.
final class ChecklistDetailFailure extends ChecklistDetailState {
  /// Creates a failure described by [message].
  const ChecklistDetailFailure(this.message);

  /// What went wrong, as shown to the user.
  final String message;

  @override
  List<Object?> get props => [message];
}
