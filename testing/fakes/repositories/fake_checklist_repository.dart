import 'dart:async';

import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flightsim_aide/utils/result.dart';

/// Scriptable [ChecklistRepository] for UI tests.
class FakeChecklistRepository implements ChecklistRepository {
  /// Creates a fake with an optional preset [current] and scripted results.
  ///
  /// Each [load] pops the next of [loadResults]; the last one repeats.
  FakeChecklistRepository({
    this.current,
    List<Result<ChecklistDocument>> loadResults = const [],
  }) : _results = [...loadResults];

  final List<Result<ChecklistDocument>> _results;
  final _controller = StreamController<ChecklistDocument?>.broadcast();

  @override
  ChecklistDocument? current;

  /// Number of times [load] has been called.
  int loadCount = 0;

  @override
  Stream<ChecklistDocument?> get changes => _controller.stream;

  /// Emits [doc] on [changes] and makes it [current].
  void emit(ChecklistDocument? doc) {
    current = doc;
    _controller.add(doc);
  }

  /// When set, [load] waits for it to complete before returning its result.
  Future<void>? loadGate;

  @override
  Future<Result<ChecklistDocument>> load() async {
    loadCount++;
    await loadGate;
    final result = _results.length > 1
        ? _results.removeAt(0)
        : _results.isEmpty
        ? Error<ChecklistDocument>(ParseFailure('no scripted result'))
        : _results.first;
    if (result is Ok<ChecklistDocument>) emit(result.value);
    return result;
  }

  /// Closes [changes].
  Future<void> dispose() => _controller.close();
}
