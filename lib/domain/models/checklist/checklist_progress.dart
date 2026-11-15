import 'package:equatable/equatable.dart';

import 'checklist.dart';
import 'checklist_item.dart';

/// Which item indexes are checked, per checklist name, and how they got that
/// way. Immutable.
///
/// A check item is open, checked or skipped (task 0.24): [skipped] marks the
/// items the user passed over; they count towards completion but not towards
/// the checked count.
///
/// Further marks support auto-check (D-52, D-71): [autoChecked] marks
/// items the app checked from a sim value (a subset of [checked]); [disagreed]
/// marks items the user ticked by hand while the sim said the condition was
/// false (shown as overridden); and [cursor] is where auto-check looks next,
/// following the pilot's own ticks. An untick is not remembered (D-78): it
/// backs the cursor up and, in auto mode, switches the checklist to manual.
/// (The former `manuallyUnchecked` set is gone; older saved files that have it
/// still read, the field is ignored.)
///
/// A switch row (`sw_enable_start`, D-82) is on or off: [enabled] holds the
/// switch rows that are on. An item with a `gate` counts, can be checked and
/// is passed over by the pointer only while its switch is on.
class ChecklistProgress extends Equatable {
  /// Creates progress from [checked]; the maps and their sets are copied.
  ///
  /// Checklists with no marks are dropped, so equal progress is always equal
  /// regardless of how it was reached.
  ChecklistProgress([Map<String, Set<int>> checked = const {}])
    : this.marks(checked: checked);

  /// Creates progress with all the marks.
  ///
  /// A [disagreed] mark is kept only for an item that is checked. A [cursor]
  /// at the top (0, or below) is the same as none.
  ChecklistProgress.marks({
    Map<String, Set<int>> checked = const {},
    Map<String, Set<int>> autoChecked = const {},
    Map<String, Set<int>> disagreed = const {},
    Map<String, int> cursor = const {},
    Map<String, Set<int>> skipped = const {},
    Map<String, Set<int>> enabled = const {},
  }) : checked = _frozen(checked),
       enabled = _frozen(enabled),
       autoChecked = _frozen(autoChecked),
       disagreed = _frozen(_onlyChecked(disagreed, checked)),
       skipped = _frozen(_notChecked(skipped, checked)),
       cursor = Map.unmodifiable({
         for (final entry in cursor.entries)
           if (entry.value > 0) entry.key: entry.value,
       });

  static Map<String, Set<int>> _onlyChecked(
    Map<String, Set<int>> marks,
    Map<String, Set<int>> checked,
  ) => {
    for (final entry in marks.entries)
      entry.key: entry.value.intersection(checked[entry.key] ?? const <int>{}),
  };

  static Map<String, Set<int>> _notChecked(
    Map<String, Set<int>> marks,
    Map<String, Set<int>> checked,
  ) => {
    for (final entry in marks.entries)
      entry.key: entry.value.difference(checked[entry.key] ?? const <int>{}),
  };

  static Map<String, Set<int>> _frozen(Map<String, Set<int>> marks) =>
      Map.unmodifiable({
        for (final entry in marks.entries)
          if (entry.value.isNotEmpty)
            entry.key: Set<int>.unmodifiable(entry.value),
      });

  /// Read-only view of the checked indexes per checklist name.
  final Map<String, Set<int>> checked;

  /// The checked indexes the app set from a sim value (always also in
  /// [checked]).
  final Map<String, Set<int>> autoChecked;

  /// The indexes the user ticked by hand while the sim said the condition was
  /// false (always also in [checked]).
  final Map<String, Set<int>> disagreed;

  /// The indexes the user skipped (never also in [checked]).
  final Map<String, Set<int>> skipped;

  /// The switch rows that are on, per checklist name (D-82). A switch is off
  /// unless it is in here, so a new run starts with every block disabled.
  final Map<String, Set<int>> enabled;

  /// Where auto-check looks next, per checklist name. A missing entry is the
  /// top. The user's ticks move it, forward or back; auto-check only moves it
  /// forward (D-71).
  final Map<String, int> cursor;

  /// The cursor of checklist [name]: 0, the top, when none was set.
  int cursorOf(String name) => cursor[name] ?? 0;

  /// Whether the user ticked item [index] of [name] against the sim.
  bool isDisagreed(String name, int index) =>
      disagreed[name]?.contains(index) ?? false;

  /// Whether item [index] of [name] was checked by the app, not by hand.
  bool isAutoChecked(String name, int index) =>
      autoChecked[name]?.contains(index) ?? false;

  /// Whether the switch row [index] of [name] is on.
  bool isOptionOn(String name, int index) =>
      enabled[name]?.contains(index) ?? false;

  /// Whether item [index] of [checklist] is enabled: it is in no switch block,
  /// or the switch of its block is on. A disabled item is not counted and is
  /// passed over by auto-check, the pointer, Check and Skip.
  bool isEnabled(Checklist checklist, int index) {
    final gate = checklist.items[index].gate;
    return gate == null || isOptionOn(checklist.name, gate);
  }

  /// Returns a new progress with the switch row [index] of [checklist] turned
  /// [on] or off (D-82). Turning it off clears the checks, auto marks, red
  /// marks and skips of its items. Either way the cursor goes back to the
  /// switch row if it was past it, so the items of the block are not behind
  /// the cursor when they are enabled again. Nothing changes when [index] is
  /// not a switch row or already has that position.
  ChecklistProgress optionSet(
    Checklist checklist,
    int index, {
    required bool on,
  }) {
    final name = checklist.name;
    if (index < 0 ||
        index >= checklist.items.length ||
        checklist.items[index].type != ChecklistItemType.option ||
        isOptionOn(name, index) == on) {
      return this;
    }
    final inBlock = <int>{
      for (var i = 0; i < checklist.items.length; i++)
        if (checklist.items[i].gate == index) i,
    };
    final next = on
        ? {...?enabled[name], index}
        : ({...?enabled[name]}..remove(index));
    return ChecklistProgress.marks(
      checked: {
        ...checked,
        name: {...?checked[name]}..removeAll(on ? const {} : inBlock),
      },
      autoChecked: {
        ...autoChecked,
        name: {...?autoChecked[name]}..removeAll(on ? const {} : inBlock),
      },
      disagreed: {
        ...disagreed,
        name: {...?disagreed[name]}..removeAll(on ? const {} : inBlock),
      },
      skipped: {
        ...skipped,
        name: {...?skipped[name]}..removeAll(on ? const {} : inBlock),
      },
      enabled: {...enabled, name: next},
      cursor: {
        ...cursor,
        name: cursorOf(name) > index ? index : cursorOf(name),
      },
    );
  }

  /// Whether item [index] of [name] was skipped.
  bool isSkipped(String name, int index) =>
      skipped[name]?.contains(index) ?? false;

  /// Whether item [index] of checklist [name] is checked.
  bool isChecked(String name, int index) =>
      checked[name]?.contains(index) ?? false;

  /// Returns a new progress with item [index] of [name] flipped by the user.
  ///
  /// Unchecking (an auto-checked item too) clears any disagreed mark and backs
  /// the cursor up to just below the nearest checked or skipped item above
  /// [index], or to the top when there is none (D-78); nothing remembers
  /// the untick. Checking by hand moves the cursor to [index] (forward or
  /// back, D-71), is never auto-checked, and is marked as disagreed when
  /// [disagrees] says the sim contradicts it.
  ChecklistProgress toggled(String name, int index, {bool disagrees = false}) {
    final isOn = isChecked(name, index);
    final marks = {...?disagreed[name]};
    if (isOn || !disagrees) {
      marks.remove(index);
    } else {
      marks.add(index);
    }
    return _with(
      name,
      checked: isOn
          ? ({...?checked[name]}..remove(index))
          : {...?checked[name], index},
      auto: {...?autoChecked[name]}..remove(index),
      disagreed: marks,
      skipped: {...?skipped[name]}..remove(index),
      cursor: isOn ? _backedUp(name, index) : index,
    );
  }

  /// The cursor after item [index] is unchecked: just below the nearest
  /// checked or skipped item above it, or the top.
  int _backedUp(String name, int index) {
    for (var i = index - 1; i >= 0; i--) {
      if (isChecked(name, i) || isSkipped(name, i)) return i + 1;
    }
    return 0;
  }

  /// Returns a new progress with item [index] of [name] skipped. The cursor
  /// moves on past it (never back), so auto-check carries on after the item.
  /// An item that is already checked is left alone.
  ChecklistProgress skipping(String name, int index) {
    if (isChecked(name, index) || isSkipped(name, index)) return this;
    return _with(
      name,
      checked: {...?checked[name]},
      auto: {...?autoChecked[name]},
      disagreed: {...?disagreed[name]},
      skipped: {...?skipped[name], index},
      cursor: index + 1 > cursorOf(name) ? index + 1 : cursorOf(name),
    );
  }

  /// Returns a new progress with the tick of item [index] of [name] taken
  /// back, as if it had not happened: [before] is the progress from just
  /// before the tick. The item is unchecked and loses its disagreed mark, so
  /// auto may still check it later; the cursor goes back to where it was. Auto may
  /// have moved the cursor on after the tick, and items it checked since stay
  /// checked, which the pointer passes over. The cursor goes back to where it
  /// was, but never past the item: if the item lies above the old cursor the
  /// cursor stops at it, so auto waits on the open item instead of walking on
  /// below it. Nothing changes when the item is not checked.
  ChecklistProgress tickCancelled(
    String name,
    int index,
    ChecklistProgress before,
  ) {
    if (!isChecked(name, index)) return this;
    return _with(
      name,
      checked: {...?checked[name]}..remove(index),
      auto: {...?autoChecked[name]}..remove(index),
      disagreed: {...?disagreed[name]}..remove(index),
      skipped: before.isSkipped(name, index)
          ? {...?skipped[name], index}
          : {...?skipped[name]},
      cursor: before.cursorOf(name) < index ? before.cursorOf(name) : index,
    );
  }

  /// Returns a new progress with [indexes] of [name] checked by the app.
  ///
  /// Items already checked or skipped are left as they are; nothing is ever
  /// unchecked here. With [cursor] the cursor moves forward to
  /// it, never back (D-71).
  ChecklistProgress autoChecking(
    String name,
    Iterable<int> indexes, {
    int? cursor,
  }) {
    final fresh = [
      for (final i in indexes)
        if (!isChecked(name, i) && !isSkipped(name, i)) i,
    ];
    final now = cursorOf(name);
    final next = cursor != null && cursor > now ? cursor : now;
    if (fresh.isEmpty && next == now) return this;
    return _with(
      name,
      checked: {...?checked[name], ...fresh},
      auto: {...?autoChecked[name], ...fresh},
      disagreed: {...?disagreed[name]},
      skipped: {...?skipped[name]},
      cursor: next,
    );
  }

  ChecklistProgress _with(
    String name, {
    required Set<int> checked,
    required Set<int> auto,
    required Set<int> disagreed,
    required Set<int> skipped,
    required int cursor,
  }) => ChecklistProgress.marks(
    checked: {...this.checked, name: checked},
    autoChecked: {...autoChecked, name: auto},
    disagreed: {...this.disagreed, name: disagreed},
    skipped: {...this.skipped, name: skipped},
    enabled: enabled,
    cursor: {...this.cursor, name: cursor},
  );

  /// Returns a new progress with checklist [name] cleared: its marks, its
  /// auto-checked items, its disagreed marks and its cursor (back to the top).
  /// The switch positions stay (D-82): they are a choice about the flight.
  ChecklistProgress reset(String name) => ChecklistProgress.marks(
    checked: {...checked}..remove(name),
    autoChecked: {...autoChecked}..remove(name),
    disagreed: {...disagreed}..remove(name),
    skipped: {...skipped}..remove(name),
    enabled: enabled,
    cursor: {...cursor}..remove(name),
  );

  /// Returns a new progress with every checklist cleared, switches included.
  ChecklistProgress resetAll() => ChecklistProgress();

  /// Checked, skipped and total counts for [checklist]; check items and switch
  /// rows count, notes and disabled items do not.
  ({int done, int total, int skipped}) countsFor(Checklist checklist) {
    final items = checklist.items;
    final marked = checked[checklist.name] ?? const <int>{};
    final passed = skipped[checklist.name] ?? const <int>{};
    var done = 0;
    var skippedCount = 0;
    var total = 0;
    for (var i = 0; i < items.length; i++) {
      if (!items[i].isCheckable || !isEnabled(checklist, i)) continue;
      total++;
      if (marked.contains(i)) {
        done++;
      } else if (passed.contains(i)) {
        skippedCount++;
      }
    }
    return (done: done, total: total, skipped: skippedCount);
  }

  /// How many checked items of [checklist] the user ticked against the sim.
  int disagreedCount(Checklist checklist) {
    final items = checklist.items;
    var count = 0;
    for (var i = 0; i < items.length; i++) {
      if (items[i].type == ChecklistItemType.check &&
          isEnabled(checklist, i) &&
          isChecked(checklist.name, i) &&
          isDisagreed(checklist.name, i)) {
        count++;
      }
    }
    return count;
  }

  /// Whether [checklist] has at least one check item and every one is checked
  /// or skipped.
  bool isComplete(Checklist checklist) {
    final counts = countsFor(checklist);
    return counts.total > 0 && counts.done + counts.skipped == counts.total;
  }

  @override
  List<Object?> get props => [
    checked,
    autoChecked,
    disagreed,
    skipped,
    enabled,
    cursor,
  ];
}
