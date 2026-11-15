import '../../models/checklist/checklist.dart';
import '../../models/checklist/checklist_item.dart';
import '../../models/checklist/checklist_progress.dart';
import 'condition_evaluator.dart';

/// What one evaluation of an open checklist found.
class AutoCheckResult {
  /// Creates a result.
  const AutoCheckResult({
    this.itemResults = const {},
    this.toCheck = const {},
    this.cursor = 0,
    this.continueTo,
  });

  /// The result of each item auto looked at in this step, by item index: the
  /// ones it checks and the one it stopped at. Items behind the cursor and
  /// items after the stop are not evaluated (D-71).
  final Map<int, Tri> itemResults;

  /// The item indexes to check now, in order. Never an uncheck (D-50).
  final Set<int> toCheck;

  /// Where auto is waiting after this step: the index of the item it stopped
  /// at, or the item count when it ran off the end. The caller stores it as
  /// the checklist's cursor, which only moves forward.
  final int cursor;

  /// The name of the checklist to go to, when the checklist is complete and a
  /// `sw_continue` link matched (`GRAMMAR.md` J2); null otherwise.
  final String? continueTo;
}

/// The one-way auto-check of an open checklist, one step ahead of the pilot
/// (decisions D-50, D-56, D-71).
///
/// Auto looks at one item, the *pointer item*: the first unchecked check item
/// at or after the checklist's cursor. A met condition checks it and auto goes
/// on to the next one; anything else (not met, unknown, no condition, an item
/// the pilot unchecked) stops it, and it waits for the pilot. It never looks
/// behind the cursor and never unchecks.
///
/// Holds the memory of the change and crossing conditions per item. An item's
/// memory starts the first time it becomes the pointer item, which is the
/// baseline rule of D-58 as amended by D-71. One instance belongs to one
/// open checklist run. Use [reset] when the checklist is opened again or reset.
class EvaluateItemConditionsUseCase {
  /// Creates the use case.
  EvaluateItemConditionsUseCase([this._evaluator = const ConditionEvaluator()]);

  final ConditionEvaluator _evaluator;
  final Map<String, ConditionState> _states = {};

  /// Forgets every baseline and crossing, for all checklists.
  void reset() => _states.clear();

  /// Forgets the memory of one checklist.
  void resetChecklist(String name) =>
      _states.removeWhere((key, _) => key.startsWith('$name\u0000'));

  /// Forgets the memory of the items [indexes] of checklist [name]: their
  /// baselines start again when they next become the pointer item. Used when
  /// a switch block is turned off or on (D-82).
  void resetItems(String name, Iterable<int> indexes) {
    for (final index in indexes) {
      _states.remove('$name\u0000$index');
    }
  }

  String _key(Checklist checklist, int index) =>
      '${checklist.name}\u0000$index';

  /// Evaluates [checklist] against [values], from the cursor in [progress].
  ///
  /// [checklists] is the document in file order, needed to resolve a bare
  /// `sw_continue` to the next checklist.
  AutoCheckResult evaluate({
    required Checklist checklist,
    required ValueLookup values,
    required ChecklistProgress progress,
    List<Checklist> checklists = const [],
  }) {
    final results = <int, Tri>{};
    final toCheck = <int>{};
    var i = progress.cursorOf(checklist.name);
    if (i < 0) i = 0;
    while (i < checklist.items.length) {
      final ChecklistItem item = checklist.items[i];
      if (item.type != ChecklistItemType.check ||
          !progress.isEnabled(checklist, i) ||
          progress.isChecked(checklist.name, i) ||
          progress.isSkipped(checklist.name, i)) {
        i++;
        continue;
      }
      final condition = item.condition;
      // A manual item: auto waits for the pilot.
      if (condition == null) break;
      final state = _states.putIfAbsent(_key(checklist, i), ConditionState.new);
      final tri = _evaluator.evaluate(condition, values, state);
      results[i] = tri;
      if (tri != Tri.met) break;
      toCheck.add(i);
      i++;
    }

    // The checklist counts as complete when this step's checks are in.
    final checked = {...?progress.checked[checklist.name], ...toCheck};
    var total = 0;
    var done = 0;
    for (var k = 0; k < checklist.items.length; k++) {
      if (checklist.items[k].type != ChecklistItemType.check ||
          !progress.isEnabled(checklist, k)) {
        continue;
      }
      total++;
      if (checked.contains(k) || progress.isSkipped(checklist.name, k)) done++;
    }
    final complete = total > 0 && done == total;

    return AutoCheckResult(
      itemResults: results,
      toCheck: toCheck,
      cursor: i,
      continueTo: complete
          ? _continueTarget(checklist, values, checklists)
          : null,
    );
  }

  /// What the sim says about item [index] of [checklist] right now, for a tick
  /// by the pilot: [Tri.notMet] means the tick contradicts the aircraft.
  ///
  /// Gives [Tri.unknown] for a note, an item with no condition, a bad index, a
  /// missing value, and for a change or crossing condition that has not had a
  /// baseline yet (it cannot be judged from one value). Never creates a
  /// baseline, so asking does not change what [evaluate] later does.
  Tri conditionOf({
    required Checklist checklist,
    required int index,
    required ValueLookup values,
  }) {
    if (index < 0 || index >= checklist.items.length) return Tri.unknown;
    final item = checklist.items[index];
    final condition = item.condition;
    if (item.type != ChecklistItemType.check || condition == null) {
      return Tri.unknown;
    }
    final state = _states[_key(checklist, index)];
    if (state == null) {
      if (condition.needsMemory) return Tri.unknown;
      return _evaluator.evaluate(condition, values, ConditionState());
    }
    return _evaluator.evaluate(condition, values, state);
  }

  /// The first link, top to bottom, with no condition or a met one. Each
  /// condition starts from an empty state, so the change and crossing forms
  /// can never hold (J3). A link whose condition is unknown is not followed.
  String? _continueTarget(
    Checklist checklist,
    ValueLookup values,
    List<Checklist> checklists,
  ) {
    for (final link in checklist.continues) {
      final condition = link.condition;
      if (condition != null &&
          _evaluator.evaluate(condition, values, ConditionState()) != Tri.met) {
        continue;
      }
      if (!link.isNext) return link.target;
      final index = checklists.indexWhere((c) => c.name == checklist.name);
      if (index >= 0 && index + 1 < checklists.length) {
        return checklists[index + 1].name;
      }
    }
    return null;
  }
}
