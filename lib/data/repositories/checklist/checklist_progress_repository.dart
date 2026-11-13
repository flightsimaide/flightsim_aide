import '../../../domain/models/aircraft/aircraft_identity.dart';
import '../../../domain/models/checklist/attach_outcome.dart';
import '../../../domain/models/checklist/checklist_document.dart';
import '../../../domain/models/checklist/checklist_progress.dart';
import '../../../utils/app_exception.dart';

/// Holds which items the user has checked, per checklist name.
abstract class ChecklistProgressRepository {
  /// Emits the new progress after every change.
  Stream<ChecklistProgress> get progress;

  /// Current progress; already updated when [progress] emits.
  ChecklistProgress get current;

  /// Flips item [itemIndex] of checklist [checklistName] by the user. A tick
  /// moves the auto-check cursor to that item; [disagrees] marks a tick the
  /// sim contradicts (D-71).
  void toggle(String checklistName, int itemIndex, {bool disagrees = false});

  /// Takes back the tick of item [itemIndex] of [checklistName] that the user
  /// just made and backed out of; [before] is [current] from just before that
  /// tick. See [ChecklistProgress.tickCancelled].
  void cancelTick(
    String checklistName,
    int itemIndex,
    ChecklistProgress before,
  );

  /// Marks item [itemIndex] of [checklistName] as skipped (task 0.24). The
  /// cursor moves on past it. A checked item is left alone.
  void skip(String checklistName, int itemIndex);

  /// Checks [itemIndexes] of [checklistName] because the sim agrees and moves
  /// the cursor forward to [cursor]. It skips items already checked and items
  /// the user unchecked, never unchecks and never moves the cursor back.
  void autoCheck(
    String checklistName,
    Iterable<int> itemIndexes, {
    int? cursor,
  });

  /// Clears checklist [checklistName].
  void reset(String checklistName);

  /// Whether checklist [checklistName] is in manual mode: auto-check is off
  /// for it because Reset put it there. This is a session-only override of
  /// the user's own choice (kept in the settings): it is never saved, and it
  /// ends when the user presses Auto/Manual, when another aircraft is loaded,
  /// when the saved-progress question is asked, and when the app restarts.
  bool isManual(String checklistName);

  /// Puts checklist [checklistName] in the session-only manual mode (Reset)
  /// or ends it. Nothing is saved.
  void setManual(String checklistName, {required bool manual});

  /// Clears every checklist.
  void resetAll();

  /// Failures to save progress. Saving never loses the in-memory marks.
  Stream<AppException> get persistenceErrors;

  /// Ties the marks to [document] for [aircraft] and applies the restore rule
  /// to what was saved for that aircraft (D-35). [runId] is the plugin's
  /// run id, or null when unknown. Without an [aircraft] the marks are cleared
  /// and nothing is saved (D-28). Attaching to the aircraft already
  /// attached changes no marks.
  Future<AttachOutcome> attach(
    ChecklistDocument document, {
    AircraftIdentity? aircraft,
    String? runId,
  });

  /// Applies the reconnect rule after the connection came back with the same
  /// aircraft: [AttachKeep] when [runId] is the one seen before, else
  /// [AttachNeedsPrompt] if there are marks to keep.
  Future<AttachOutcome> reconnected({String? runId});

  /// Answers a [AttachNeedsPrompt]: keep the saved marks or start clean.
  Future<void> resolvePrompt({required bool useSaved});

  /// Remembers that checklist [checklistName] was opened last.
  void setLastViewed(String checklistName);

  /// The checklist opened last for the attached aircraft, or null.
  String? get lastViewed;
}
