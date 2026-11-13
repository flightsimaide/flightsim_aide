import '../../../domain/models/checklist/checklist_document.dart';
import '../../../utils/result.dart';

/// Source of the loaded checklist document for the UI.
abstract class ChecklistRepository {
  /// Latest loaded document, or null before the first load.
  ChecklistDocument? get current;

  /// Emits each successfully loaded document.
  Stream<ChecklistDocument?> get changes;

  /// Fetches from the configured source, parses, caches, and publishes.
  ///
  /// Never throws; failures come back as [Error].
  Future<Result<ChecklistDocument>> load();
}
