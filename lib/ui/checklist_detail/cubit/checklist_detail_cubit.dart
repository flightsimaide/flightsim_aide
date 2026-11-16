import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/checklist/checklist_progress_repository.dart';
import '../../../data/repositories/checklist/checklist_repository.dart';
import '../../../data/repositories/flight_sim/dataref_watch.dart';
import '../../../data/repositories/flight_sim/flight_sim_repository.dart';
import '../../../data/repositories/settings/settings_repository.dart';
import '../../../domain/models/checklist/calculated_value.dart';
import '../../../domain/models/checklist/checklist.dart';
import '../../../domain/models/checklist/checklist_document.dart';
import '../../../domain/models/checklist/checklist_item.dart';
import '../../../domain/models/checklist/checklist_progress.dart';
import '../../../domain/models/checklist/checklist_sequence.dart';
import '../../../domain/models/flight_sim/connection_status.dart';
import '../../../domain/models/flight_sim/dataref.dart';
import '../../../domain/models/settings/user_options.dart';
import '../../../domain/use_cases/autocheck/condition_evaluator.dart';
import '../../../domain/use_cases/autocheck/evaluate_item_conditions_use_case.dart';
import '../../../domain/use_cases/autocheck/signals_for.dart';
import '../../../domain/use_cases/calculate/calculate_line_value_use_case.dart';
import 'checklist_detail_state.dart';

/// Shows one checklist of the current document and edits its progress.
///
/// With a [FlightSimRepository] it also watches the sim values the checklist's
/// conditions need and checks items whose condition is met (D-52). It never
/// sees sockets, subscription ids or the stream rate.
class ChecklistDetailCubit extends Cubit<ChecklistDetailState> {
  /// Creates the cubit for the checklist called [checklistName].
  ///
  /// Without [flightSim] nothing is watched and nothing is auto-checked. The
  /// auto-continue option is read from [settings] when a checklist completes.
  ChecklistDetailCubit({
    required this._checklistName,
    required this._checklistRepository,
    required this._progressRepository,
    this._flightSim,
    this._settings,
    EvaluateItemConditionsUseCase? autoCheck,
    CalculateLineValueUseCase? calculate,
  }) : _autoCheck = autoCheck ?? EvaluateItemConditionsUseCase(),
       _calculate = calculate ?? const CalculateLineValueUseCase(),
       super(const ChecklistDetailLoading());

  static const _notFound = ChecklistDetailFailure('Checklist not found');

  final String _checklistName;
  final ChecklistRepository _checklistRepository;
  final ChecklistProgressRepository _progressRepository;
  final FlightSimRepository? _flightSim;
  final SettingsRepository? _settings;
  final EvaluateItemConditionsUseCase _autoCheck;
  final CalculateLineValueUseCase _calculate;
  final _tickWarnings = StreamController<TickWarning>.broadcast();
  final _manualNotices = StreamController<void>.broadcast();
  final _watchSubscriptions = <StreamSubscription<Object?>>[];
  DatarefWatch? _watch;
  String? _continueTo;
  bool _evaluating = false;

  /// True from a tick against the sim until the user answers the warning.
  /// Auto-check is held while it is set, so nothing below the ticked item is
  /// ticked before the user has decided to keep or cancel that tick.
  bool _warningOpen = false;

  /// Whether auto-check is on for this checklist: the user's own choice (kept
  /// in the settings) unless Reset put this checklist in manual for the
  /// session.
  bool get _auto =>
      !_progressRepository.isManual(_checklistName) &&
      (_settings?.options.autoMode ?? _localAuto);

  /// The user's choice when there are no settings to keep it in.
  bool _localAuto = true;
  int _resets = 0;

  /// Whether a first frame of values arrived. The change and crossing forms
  /// take their baseline from the first evaluation (D-58), so nothing is
  /// evaluated before then, except to find the continue result of a checklist
  /// that is already complete (it has no unchecked item to give a baseline to).
  bool _hadBatch = false;
  StreamSubscription<ChecklistProgress>? _progressSubscription;
  StreamSubscription<ChecklistDocument?>? _documentSubscription;
  ChecklistDocument? _document;

  /// Shows the checklist from the current document and follows later changes.
  /// Opening an existing checklist records it as the last viewed.
  void load() {
    _progressSubscription ??= _progressRepository.progress.listen((_) {
      _emitState();
      // A manual tick can complete the checklist: find where to continue.
      _evaluate();
    });
    _documentSubscription ??= _checklistRepository.changes.listen(_setDocument);
    _setDocument(_checklistRepository.current);
    if (_find() != null) _progressRepository.setLastViewed(_checklistName);
    _startWatching();
  }

  /// Emitted when the user ticks an item whose condition the sim says is not
  /// met. The tick stands and the item is marked; the screen asks the user to
  /// acknowledge (D-71).
  Stream<TickWarning> get tickWarnings => _tickWarnings.stream;

  /// Emitted when an untick in auto mode switched this checklist to manual
  /// (D-78), so the screen can tell the user.
  Stream<void> get manualNotices => _manualNotices.stream;

  void _startWatching() {
    final flightSim = _flightSim;
    final checklist = _find();
    if (flightSim == null || checklist == null || _watch != null) return;
    final watch = flightSim.watch(
      signalsFor(checklist, tables: _document?.tables ?? const {}),
    );
    _watch = watch;
    _watchSubscriptions
      ..add(
        watch.batches.listen((_) {
          _hadBatch = true;
          _evaluate();
          _refreshCalculations();
        }),
      )
      ..add(watch.unavailableChanges.listen((_) => _emitState()))
      ..add(
        flightSim.connectionStatus.listen((_) {
          _evaluate();
          _refreshCalculations();
        }),
      );
    _emitState(); // the watch may already know unavailable names
    _evaluate();
  }

  /// Shows the new values of the `sw_calculate` lines. The state is emitted
  /// again only when a (rounded) value changed, as equal states are dropped.
  void _refreshCalculations() {
    final checklist = _find();
    if (checklist != null &&
        checklist.items.any((i) => i.calculations.isNotEmpty)) {
      _emitState();
    }
  }

  /// The values the `sw_calculate` lines read, or null while there are none
  /// to read: no sim, no watch or a link that is down or stale.
  ValueLookup? _liveValues() {
    final flightSim = _flightSim;
    final watch = _watch;
    if (flightSim == null ||
        watch == null ||
        flightSim.current is! ConnectionConnected) {
      return null;
    }
    return MapValues({
      for (final e in watch.current.entries) e.key.wireName: e.value.number,
    });
  }

  List<CalculatedValue> _calculatedFor(
    ChecklistItem item,
    ChecklistDocument document,
    ValueLookup? values,
  ) {
    if (item.calculations.isEmpty) return const [];
    return [
      for (final line in item.calculations)
        switch (document.tables[line.table]) {
          final table? when values != null => _calculate.calculate(
            table,
            line,
            values,
          ),
          _ => const CalculatedValue.unavailable(),
        },
    ];
  }

  /// Checks what the current sim values say and decides the continue result.
  void _evaluate() {
    final flightSim = _flightSim;
    final watch = _watch;
    final checklist = _find();
    final document = _document;
    if (flightSim == null ||
        watch == null ||
        checklist == null ||
        document == null ||
        _evaluating ||
        _warningOpen) {
      return;
    }
    _evaluating = true;
    try {
      // While the link is down or stale the values are unknown: nothing is
      // applied, marks stay, and the next evaluation starts from what is
      // current then (AC-36).
      if (flightSim.current is! ConnectionConnected) return;
      final progress = _progressRepository.current;
      if (!_hadBatch && !progress.isComplete(checklist)) return;
      final result = _autoCheck.evaluate(
        checklist: checklist,
        values: MapValues({
          for (final e in watch.current.entries) e.key.wireName: e.value.number,
        }),
        progress: progress,
        checklists: document.checklists,
      );
      // The repository ignores a step that changes nothing and moves the
      // cursor only forward. In manual mode nothing is ticked.
      if (_auto) {
        _progressRepository.autoCheck(
          _checklistName,
          result.toCheck,
          cursor: result.cursor,
        );
      }
      _setContinue(result.continueTo, checklist);
    } finally {
      _evaluating = false;
    }
  }

  void _setContinue(String? target, Checklist checklist) {
    final complete = _progressRepository.current.isComplete(checklist);
    final next = complete ? target : null;
    final changed = next != _continueTo;
    _continueTo = next;
    if (changed) _emitState();
  }

  /// Flips check item [index]; notes and out-of-range indexes are ignored.
  ///
  /// A tick moves the auto-check pointer to that item. If the sim says the
  /// item's condition is not met, the tick stands, the item is marked and a
  /// [TickWarning] is emitted (D-71). An unknown value, an item with no
  /// condition, an untick and a lost link give no warning.
  void toggle(int index) {
    final checklist = _find();
    if (checklist == null || index < 0 || index >= checklist.items.length) {
      return;
    }
    if (!checklist.items[index].isCheckable) return;
    // An item of a switch that is off cannot be ticked (D-82).
    if (!_progressRepository.current.isEnabled(checklist, index)) return;
    final ticking = !_progressRepository.current.isChecked(
      _checklistName,
      index,
    );
    if (!ticking && _auto) {
      // An untick in auto mode would be undone at once by the sim value, so
      // it switches this checklist to manual for the session, as Reset does.
      _progressRepository.setManual(_checklistName, manual: true);
      _manualNotices.add(null);
    }
    final disagrees = ticking && _sayswrong(checklist, index);
    final before = _progressRepository.current;
    if (disagrees) _warningOpen = true;
    _progressRepository.toggle(_checklistName, index, disagrees: disagrees);
    if (disagrees) {
      _tickWarnings.add(
        TickWarning(
          index: index,
          label: checklist.items[index].label,
          result: checklist.items[index].result,
          before: before,
        ),
      );
    }
  }

  /// Flips the switch of the row [index] (`sw_switch`, D-82). The items of the
  /// branch that is hidden lose their marks; the auto-check memory of the
  /// items of its blocks starts again, and auto-check looks at the items that
  /// are shown at once. Anything but a switch row is ignored.
  void toggleOption(int index) {
    final checklist = _find();
    if (checklist == null || index < 0 || index >= checklist.items.length) {
      return;
    }
    final def = checklist.items[index].switchDef;
    final document = _document;
    if (def == null || document == null) return;
    final on = !_progressRepository.current.isSwitchOn(def);
    _autoCheck.resetItems(_checklistName, [
      for (var i = 0; i < checklist.items.length; i++)
        if (checklist.items[i].gate?.id == def.id) i,
    ]);
    _progressRepository.setSwitch(document.checklists, def, on: on);
    if (_auto) _evaluate();
  }

  /// Backs out of the tick that gave [warning]: the item is open again, as if
  /// it had not been ticked, so auto may still check it once the sim agrees.
  void cancelTick(TickWarning warning) {
    _warningOpen = false;
    _progressRepository.cancelTick(
      _checklistName,
      warning.index,
      warning.before,
    );
    _evaluate();
  }

  /// The user acknowledged the warning: the tick and the red mark stay, and
  /// auto-check carries on below the ticked item.
  void acknowledgeTick() {
    if (!_warningOpen) return;
    _warningOpen = false;
    _evaluate();
  }

  /// Ticks the pointer item, the one auto-check waits on: the same as tapping
  /// its row, so the cursor moves to it, a sim that disagrees gives the red
  /// warning and the result is saved. It works in manual mode too, because
  /// the pointer follows the cursor and the pilot's ticks, not the mode. It
  /// does nothing when no item is left at or after the cursor.
  void checkNext() {
    final checklist = _find();
    if (checklist == null) return;
    final index = _pointer(checklist, _progressRepository.current);
    if (index != null) toggle(index);
  }

  /// Skips the pointer item, the one Check would tick: the first check item
  /// that is neither checked nor skipped at or after the cursor. Notes are
  /// never skipped. Does nothing when none is left.
  void skipNext() {
    final checklist = _find();
    if (checklist == null) return;
    final index = _pointer(checklist, _progressRepository.current);
    if (index != null) _progressRepository.skip(_checklistName, index);
  }

  bool _canSkip(Checklist checklist, ChecklistProgress progress) =>
      _pointer(checklist, progress) != null;

  /// The first check item that is not checked at or after the cursor
  /// (D-71), or null.
  int? _pointer(Checklist checklist, ChecklistProgress progress) {
    for (
      var i = progress.cursorOf(_checklistName);
      i < checklist.items.length;
      i++
    ) {
      if (checklist.items[i].isCheckable &&
          progress.isEnabled(checklist, i) &&
          !progress.isChecked(_checklistName, i) &&
          !progress.isSkipped(_checklistName, i)) {
        return i;
      }
    }
    return null;
  }

  /// Whether the sim, now, says item [index] is not set.
  bool _sayswrong(Checklist checklist, int index) {
    final flightSim = _flightSim;
    final watch = _watch;
    if (flightSim == null ||
        watch == null ||
        flightSim.current is! ConnectionConnected) {
      return false;
    }
    return _autoCheck.conditionOf(
          checklist: checklist,
          index: index,
          values: MapValues({
            for (final e in watch.current.entries)
              e.key.wireName: e.value.number,
          }),
        ) ==
        Tri.notMet;
  }

  /// Clears every check in this checklist and starts the conditions over: the
  /// change baselines are taken again and the continue result is dropped.
  ///
  /// It also puts this checklist in manual mode for the session only, so the
  /// values already met in the sim do not tick the items again. The user's own
  /// choice in the settings is not changed; [toggleAuto] turns auto-check back
  /// on.
  void reset() {
    _autoCheck.resetChecklist(_checklistName);
    _continueTo = null;
    _progressRepository.setManual(_checklistName, manual: true);
    _resets++;
    _progressRepository.reset(_checklistName);
    _emitState();
  }

  /// Switches between auto and manual mode: the user's choice, saved in the
  /// settings and kept until the user changes it. It also ends the session-only
  /// manual mode that Reset set for this checklist. Turning auto on checks at
  /// once what the sim already says is met.
  Future<void> toggleAuto() async {
    final auto = !_auto;
    _progressRepository.setManual(_checklistName, manual: false);
    _localAuto = auto;
    await _settings?.update((o) => o.set(UserOptions.autoModeOption, auto));
    if (isClosed) return;
    _emitState();
    if (_auto) _evaluate();
  }

  Checklist? _find() {
    for (final checklist in _document?.checklists ?? const <Checklist>[]) {
      if (checklist.name == _checklistName) return checklist;
    }
    return null;
  }

  void _setDocument(ChecklistDocument? document) {
    _document = document;
    _emitState();
  }

  void _emitState() {
    final document = _document;
    final checklist = _find();
    if (document == null || checklist == null) {
      emit(_notFound);
      return;
    }
    final progress = _progressRepository.current;
    final counts = progress.countsFor(checklist);
    final unavailable = _watch?.unavailable ?? const <Dataref>{};
    final continueTo = _continueTo;
    final values = checklist.items.any((i) => i.calculations.isNotEmpty)
        ? _liveValues()
        : null;
    emit(
      ChecklistDetailLoaded(
        title: checklist.title,
        rows: [
          for (var i = 0; i < checklist.items.length; i++)
            ChecklistDetailRow(
              index: i,
              item: checklist.items[i],
              checked:
                  checklist.items[i].isCheckable &&
                  progress.isChecked(_checklistName, i),
              autoChecked:
                  checklist.items[i].isCheckable &&
                  progress.isAutoChecked(_checklistName, i),
              disagreed:
                  checklist.items[i].isCheckable &&
                  progress.isDisagreed(_checklistName, i),
              skipped:
                  checklist.items[i].isCheckable &&
                  progress.isSkipped(_checklistName, i),
              enabled: progress.isEnabled(checklist, i),
              optionOn: switch (checklist.items[i].switchDef) {
                final def? => progress.isSwitchOn(def),
                null => false,
              },
              calculated: _calculatedFor(checklist.items[i], document, values),
            ),
        ],
        done: counts.done,
        skipped: counts.skipped,
        disagreedCount: progress.disagreedCount(checklist),
        canSkip: _canSkip(checklist, progress),
        total: counts.total,
        isComplete: progress.isComplete(checklist),
        colours: document.colours,
        next: [
          for (final target in ChecklistSequence(
            document.checklists,
          ).successors(checklist))
            NextChecklist(name: target.name, title: target.title),
        ],
        continueTo: continueTo == null
            ? null
            : _nextChecklist(document, continueTo),
        stayManual: _stayManual(checklist, unavailable, progress),
        auto: _auto,
        resets: _resets,
        pointer: _pointer(checklist, progress),
        name: checklist.name,
        checklists: [
          for (final c in document.checklists)
            NextChecklist(name: c.name, title: c.title),
        ],
        nextInFile: _nextInFile(document, checklist),
      ),
    );
  }

  NextChecklist? _nextInFile(ChecklistDocument document, Checklist checklist) {
    final all = document.checklists;
    final at = all.indexWhere((c) => c.name == checklist.name);
    if (at < 0 || at + 1 >= all.length) return null;
    return NextChecklist(name: all[at + 1].name, title: all[at + 1].title);
  }

  NextChecklist? _nextChecklist(ChecklistDocument document, String name) {
    for (final c in document.checklists) {
      if (c.name == name) return NextChecklist(name: c.name, title: c.title);
    }
    return null;
  }

  /// Enabled check items with a condition that needs a value the sim cannot
  /// give.
  int _stayManual(
    Checklist checklist,
    Set<Dataref> unavailable,
    ChecklistProgress progress,
  ) {
    if (unavailable.isEmpty) return 0;
    var count = 0;
    for (var i = 0; i < checklist.items.length; i++) {
      final item = checklist.items[i];
      final needs = item.condition?.signals ?? const <Dataref>[];
      if (item.type == ChecklistItemType.check &&
          progress.isEnabled(checklist, i) &&
          needs.any(unavailable.contains)) {
        count++;
      }
    }
    return count;
  }

  @override
  Future<void> close() async {
    for (final s in _watchSubscriptions) {
      await s.cancel();
    }
    _watch?.release();
    await _tickWarnings.close();
    await _manualNotices.close();
    await _progressSubscription?.cancel();
    await _documentSubscription?.cancel();
    // Manual mode set by Reset or an untick lasts only while the page is open.
    _progressRepository.setManual(_checklistName, manual: false);
    return super.close();
  }
}
