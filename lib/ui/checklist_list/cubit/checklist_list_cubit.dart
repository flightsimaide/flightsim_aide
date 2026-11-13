import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/checklist/checklist_progress_repository.dart';
import '../../../data/repositories/checklist/checklist_repository.dart';
import '../../../domain/models/checklist/checklist.dart';
import '../../../domain/models/checklist/checklist_document.dart';
import '../../../domain/models/checklist/checklist_progress.dart';
import '../../../domain/models/checklist/checklist_sequence.dart';
import 'checklist_list_state.dart';

/// Lists the current document's checklists with live progress counts.
class ChecklistListCubit extends Cubit<ChecklistListState> {
  /// Creates the cubit over the given repositories.
  ChecklistListCubit({
    required this._checklistRepository,
    required this._progressRepository,
  }) : super(const ChecklistListLoading());

  static const _noDocument = ChecklistListFailure('No checklist loaded');

  final ChecklistRepository _checklistRepository;
  final ChecklistProgressRepository _progressRepository;
  StreamSubscription<ChecklistProgress>? _progressSubscription;
  StreamSubscription<ChecklistDocument?>? _documentSubscription;
  ChecklistDocument? _document;
  bool _warningsDismissed = false;

  /// Shows the repository's current document and follows later changes.
  ///
  /// Never reopens the picker: it only reads [ChecklistRepository.current].
  void load() {
    _progressSubscription ??= _progressRepository.progress.listen(
      (_) => _emitLoaded(),
    );
    _documentSubscription ??= _checklistRepository.changes.listen(_setDocument);
    _setDocument(_checklistRepository.current);
  }

  /// Hides the warnings banner for the current document.
  void dismissWarnings() {
    _warningsDismissed = true;
    final current = state;
    if (current is ChecklistListLoaded) {
      emit(current.copyWith(warningsDismissed: true));
    }
  }

  void _setDocument(ChecklistDocument? document) {
    _document = document;
    _warningsDismissed = false;
    _emitLoaded();
  }

  void _emitLoaded() {
    final document = _document;
    if (document == null) {
      emit(_noDocument);
      return;
    }
    final progress = _progressRepository.current;
    emit(
      ChecklistListLoaded(
        items: [
          for (final checklist in ChecklistSequence(
            document.checklists,
          ).ordered)
            _summarise(checklist, progress),
        ],
        warnings: document.warnings,
        sourceName: document.sourceName,
        warningsDismissed: _warningsDismissed,
      ),
    );
  }

  ChecklistSummary _summarise(Checklist checklist, ChecklistProgress progress) {
    final counts = progress.countsFor(checklist);
    return ChecklistSummary(
      name: checklist.name,
      title: checklist.title,
      done: counts.done,
      total: counts.total,
      isComplete: progress.isComplete(checklist),
      skipped: counts.skipped,
      overridden: progress.disagreedCount(checklist),
    );
  }

  @override
  Future<void> close() async {
    await _progressSubscription?.cancel();
    await _documentSubscription?.cancel();
    return super.close();
  }
}
