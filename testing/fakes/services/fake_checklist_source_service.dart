import 'package:flightsim_aide/data/services/checklist/checklist_source_service.dart';
import 'package:flightsim_aide/data/services/checklist/model/raw_checklist_document.dart';
import 'package:flightsim_aide/utils/result.dart';

/// Scriptable [ChecklistSourceService] for tests.
class FakeChecklistSourceService implements ChecklistSourceService {
  /// Creates a fake that returns [result] from every [load].
  FakeChecklistSourceService(this.result, {this.delay});

  /// Result returned by [load]; may be changed between calls.
  Result<RawChecklistDocument> result;

  /// If set, [load] completes after this delay.
  Duration? delay;

  /// Number of times [load] has been called.
  int callCount = 0;

  @override
  Future<Result<RawChecklistDocument>> load() async {
    callCount++;
    final d = delay;
    if (d != null) await Future<void>.delayed(d);
    return result;
  }
}
