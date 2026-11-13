import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/checklist/attach_outcome.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';

/// [ChecklistProgressRepositoryImpl] that also records the calls it receives.
class FakeChecklistProgressRepository extends ChecklistProgressRepositoryImpl {
  /// Creates the fake; [storage] is passed on.
  FakeChecklistProgressRepository({super.storage});

  /// `(name, index)` of every [toggle] call, in order.
  final toggleCalls = <(String, int)>[];

  /// Name of every [reset] call, in order.
  final resetCalls = <String>[];

  /// Number of [resetAll] calls.
  int resetAllCount = 0;

  /// `(document, aircraft, runId)` of every [attach] call, in order.
  final attachCalls = <(ChecklistDocument, AircraftIdentity?, String?)>[];

  /// When set, [attach] returns this instead of the real outcome.
  AttachOutcome? forcedOutcome;

  /// `runId` of every [reconnected] call, in order.
  final reconnectCalls = <String?>[];

  /// When set, [reconnected] returns this instead of the real outcome.
  AttachOutcome? forcedReconnect;

  @override
  Future<AttachOutcome> reconnected({String? runId}) async {
    reconnectCalls.add(runId);
    final outcome = await super.reconnected(runId: runId);
    return forcedReconnect ?? outcome;
  }

  /// Answers given to [resolvePrompt], in order.
  final promptAnswers = <bool>[];

  @override
  Future<AttachOutcome> attach(
    ChecklistDocument document, {
    AircraftIdentity? aircraft,
    String? runId,
  }) async {
    attachCalls.add((document, aircraft, runId));
    final outcome = await super.attach(
      document,
      aircraft: aircraft,
      runId: runId,
    );
    return forcedOutcome ?? outcome;
  }

  @override
  Future<void> resolvePrompt({required bool useSaved}) {
    promptAnswers.add(useSaved);
    return super.resolvePrompt(useSaved: useSaved);
  }

  @override
  void toggle(String checklistName, int itemIndex, {bool disagrees = false}) {
    toggleCalls.add((checklistName, itemIndex));
    super.toggle(checklistName, itemIndex, disagrees: disagrees);
  }

  @override
  void reset(String checklistName) {
    resetCalls.add(checklistName);
    super.reset(checklistName);
  }

  @override
  void resetAll() {
    resetAllCount++;
    super.resetAll();
  }
}
