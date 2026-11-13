import '../../../utils/result.dart';
import 'model/raw_checklist_document.dart';

/// Supplies the raw checklist file from wherever it lives (picker, asset, network).
abstract class ChecklistSourceService {
  /// Loads the checklist file.
  ///
  /// Takes no UI parameters: any choice (which file, which URL) is made inside
  /// the implementation, so callers never depend on how the source works.
  Future<Result<RawChecklistDocument>> load();
}
