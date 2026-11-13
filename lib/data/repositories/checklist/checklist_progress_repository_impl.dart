import 'dart:async';

import '../../../domain/models/aircraft/aircraft_identity.dart';
import '../../../domain/models/checklist/attach_outcome.dart';
import '../../../domain/models/checklist/checklist_document.dart';
import '../../../domain/models/checklist/checklist_fingerprint.dart';
import '../../../domain/models/checklist/checklist_item.dart';
import '../../../domain/models/checklist/checklist_progress.dart';
import '../../../domain/models/checklist/progress_restore_policy.dart';
import '../../../utils/app_exception.dart';
import '../../../utils/result.dart';
import '../../services/local/model/stored_progress.dart';
import '../../services/local/progress_storage_service.dart';
import 'checklist_progress_repository.dart';

/// [ChecklistProgressRepository] that keeps the marks in memory and, once
/// attached to an aircraft, saves them through a [ProgressStorageService].
class ChecklistProgressRepositoryImpl implements ChecklistProgressRepository {
  /// Creates the repository. Without a [storage] nothing is saved.
  ChecklistProgressRepositoryImpl({this._storage});

  final ProgressStorageService? _storage;

  final _controller = StreamController<ChecklistProgress>.broadcast();
  final _errors = StreamController<AppException>.broadcast();
  ChecklistProgress _current = ChecklistProgress();
  final _manual = <String>{};

  ChecklistDocument? _document;
  String? _aircraftPath;
  String? _lastViewed;
  String? _runId;
  _Pending? _pending;
  Future<void> _writes = Future.value();

  @override
  Stream<ChecklistProgress> get progress => _controller.stream;

  @override
  ChecklistProgress get current => _current;

  @override
  Stream<AppException> get persistenceErrors => _errors.stream;

  @override
  String? get lastViewed => _lastViewed;

  @override
  void toggle(String checklistName, int itemIndex, {bool disagrees = false}) {
    _set(_current.toggled(checklistName, itemIndex, disagrees: disagrees));
    _persist();
  }

  @override
  void cancelTick(
    String checklistName,
    int itemIndex,
    ChecklistProgress before,
  ) {
    final next = _current.tickCancelled(checklistName, itemIndex, before);
    if (identical(next, _current)) return;
    _set(next);
    _persist();
  }

  @override
  void skip(String checklistName, int itemIndex) {
    final next = _current.skipping(checklistName, itemIndex);
    if (identical(next, _current)) return;
    _set(next);
    _persist();
  }

  @override
  void autoCheck(
    String checklistName,
    Iterable<int> itemIndexes, {
    int? cursor,
  }) {
    final next = _current.autoChecking(
      checklistName,
      itemIndexes,
      cursor: cursor,
    );
    if (identical(next, _current)) return;
    _set(next);
    _persist();
  }

  @override
  void reset(String checklistName) {
    _set(_current.reset(checklistName));
    _persist();
  }

  @override
  bool isManual(String checklistName) => _manual.contains(checklistName);

  @override
  void setManual(String checklistName, {required bool manual}) {
    if (manual) {
      _manual.add(checklistName);
    } else {
      _manual.remove(checklistName);
    }
  }

  @override
  void resetAll() {
    _set(_current.resetAll());
    _persist();
  }

  @override
  void setLastViewed(String checklistName) {
    _lastViewed = checklistName;
    _persist();
  }

  @override
  Future<AttachOutcome> attach(
    ChecklistDocument document, {
    AircraftIdentity? aircraft,
    String? runId,
  }) async {
    _document = document;
    if (aircraft == null) {
      _manual.clear();
      _aircraftPath = null;
      _lastViewed = null;
      _pending = null;
      _set(ChecklistProgress());
      return const AttachClean();
    }
    if (aircraft.aircraftPath == _aircraftPath) return const AttachClean();

    // Loading another aircraft starts a new flight, so the aircraft left
    // behind keeps no saved ticks. Otherwise loading it again within the same
    // X-Plane run (same run id) would restore ticks from the earlier flight.
    // Queued after any pending write so nothing recreates the record.
    final previous = _aircraftPath;
    final storage = _storage;
    if (previous != null && storage != null) {
      _writes = _writes.then((_) => storage.delete(previous));
    }

    _manual.clear();
    _aircraftPath = aircraft.aircraftPath;
    _pending = null;
    _lastViewed = null;
    _set(ChecklistProgress());
    final saved = await _storage?.read(aircraft.aircraftPath);
    if (_aircraftPath != aircraft.aircraftPath) return const AttachClean();

    final restorable = saved == null
        ? ChecklistProgress()
        : _restorable(saved, document);
    final action = ProgressRestorePolicy.decide(
      hasSaved: restorable.checked.isNotEmpty || restorable.skipped.isNotEmpty,
      savedRunId: saved?.runId,
      runId: runId,
    );

    switch (action) {
      case RestoreAction.nothing:
        _runId = runId;
        _persist();
        return const AttachClean();
      case RestoreAction.restore:
        _runId = runId;
        _set(restorable);
        _lastViewed = saved?.lastViewed;
        _persist();
        return AttachRestored(_lastViewed);
      case RestoreAction.prompt:
        _manual.clear();
        _pending = _Pending(restorable, saved?.lastViewed, runId: runId);
        return const AttachNeedsPrompt();
    }
  }

  @override
  Future<AttachOutcome> reconnected({String? runId}) async {
    if (_aircraftPath == null) return const AttachKeep();
    if (_current.checked.isEmpty ||
        ProgressRestorePolicy.decideReconnect(
              lastRunId: _runId,
              runId: runId,
            ) ==
            ReconnectAction.keep) {
      if (_runId != runId) {
        _runId = runId;
        _persist();
      }
      return const AttachKeep();
    }
    _manual.clear();
    _pending = _Pending(_current, _lastViewed, runId: runId);
    return const AttachNeedsPrompt();
  }

  @override
  Future<void> resolvePrompt({required bool useSaved}) async {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    _runId = pending.runId;
    if (useSaved) {
      _set(pending.progress);
      _lastViewed = pending.lastViewed;
    } else {
      _set(ChecklistProgress());
      _lastViewed = null;
    }
    _persist();
  }

  /// Closes the streams; later changes still update [current] but emit
  /// nothing.
  Future<void> dispose() {
    unawaited(_errors.close());
    return _controller.close();
  }

  ChecklistProgress _restorable(
    StoredProgress saved,
    ChecklistDocument document,
  ) {
    final marks = <String, Set<int>>{};
    final auto = <String, Set<int>>{};
    final disagreed = <String, Set<int>>{};
    final skipped = <String, Set<int>>{};
    final cursor = <String, int>{};
    for (final checklist in document.checklists) {
      final entry = saved.checklists[checklist.name];
      if (entry == null || entry.fingerprint != fingerprintOf(checklist)) {
        continue;
      }
      Set<int> valid(Iterable<int> indexes) => {
        for (final i in indexes)
          if (i >= 0 &&
              i < checklist.items.length &&
              checklist.items[i].type == ChecklistItemType.check)
            i,
      };
      final checked = valid(entry.checked);
      marks[checklist.name] = checked;
      // An auto mark only means something on an item that is checked.
      auto[checklist.name] = valid(entry.autoChecked).intersection(checked);
      disagreed[checklist.name] = valid(entry.disagreed).intersection(checked);
      skipped[checklist.name] = valid(entry.skipped).difference(checked);
      cursor[checklist.name] = entry.cursor.clamp(0, checklist.items.length);
    }
    return ChecklistProgress.marks(
      checked: marks,
      autoChecked: auto,
      disagreed: disagreed,
      skipped: skipped,
      cursor: cursor,
    );
  }

  StoredProgress _snapshot() {
    final document = _document;
    final marks = <String, StoredChecklistProgress>{};
    if (document != null) {
      for (final checklist in document.checklists) {
        final checked = _current.checked[checklist.name] ?? const <int>{};
        final auto = _current.autoChecked[checklist.name] ?? const <int>{};
        final disagreed = _current.disagreed[checklist.name] ?? const <int>{};
        final skipped = _current.skipped[checklist.name] ?? const <int>{};
        final cursor = _current.cursorOf(checklist.name);
        if (checked.isEmpty && skipped.isEmpty && cursor == 0) {
          continue;
        }
        marks[checklist.name] = StoredChecklistProgress(
          checked: ([...checked]..sort()),
          autoChecked: ([...auto]..sort()),
          disagreed: ([...disagreed]..sort()),
          skipped: ([...skipped]..sort()),
          cursor: cursor,
          fingerprint: fingerprintOf(checklist),
        );
      }
    }
    return StoredProgress(
      lastViewed: _lastViewed,
      runId: _runId,
      checklists: marks,
    );
  }

  /// Saves the current marks, stamped with the run id (D-35). Writes run one after
  /// another so the last change is the one on disk.
  void _persist() {
    final storage = _storage;
    final path = _aircraftPath;
    if (storage == null || path == null) return;
    final snapshot = _snapshot();
    _writes = _writes.then((_) async {
      final result = await storage.write(path, snapshot);
      _report(result);
    });
  }

  void _report(Result<void> result) {
    if (result case Error(:final error) when !_errors.isClosed) {
      _errors.add(error);
    }
  }

  void _set(ChecklistProgress next) {
    _current = next;
    if (!_controller.isClosed) _controller.add(next);
  }
}

class _Pending {
  const _Pending(this.progress, this.lastViewed, {required this.runId});

  final ChecklistProgress progress;
  final String? lastViewed;
  final String? runId;
}
