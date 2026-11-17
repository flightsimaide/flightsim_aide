import '../../models/checklist/checklist.dart';
import '../../models/checklist/checklist_item.dart';
import '../../models/checklist/checklist_progress.dart';
import '../../models/voice/voice_prompt.dart';
import '../../models/voice/voice_settings.dart';

/// Works out what the voice says after a step, and what it waits for (D-84,
/// `GRAMMAR.md` section 5d). Pure Dart.
///
/// A step is a tick by the pilot, a spoken answer, or one pass of auto-check
/// that ticked some items. The voice then:
///
/// - for the challenge rows auto-check just ticked: with one or two, says each
///   one as a challenge, a pause, then the response; with more than two, says
///   how many are verified;
/// - for the flow rows ticked in the step (the pilot did the action): says the
///   result as the confirmation, or with more than one the label and result of
///   each, or how many are done when there are more than two;
/// - reads the next unticked row as its label only: a challenge row waits for
///   the pilot's answer, a flow row for the pilot to do it, and the result is
///   said after the action;
/// - says "Checklist complete" when there is none left.
///
/// A kind of row the voice is off for is not spoken and not waited on.
class BuildVoicePromptUseCase {
  /// Creates the use case.
  const BuildVoicePromptUseCase();

  /// The silence between a challenge and its response.
  static const challengePause = Duration(milliseconds: 700);

  /// Above this many challenge rows ticked in one step the voice only counts
  /// them.
  static const spokenRunLimit = 2;

  /// What to say after a step on [checklist]. [progress] is the state after
  /// it; [autoChecked] are the item indexes auto-check ticked in the step.
  VoicePrompt afterStep({
    required Checklist checklist,
    required ChecklistProgress progress,
    required VoiceSettings settings,
    List<int> autoChecked = const [],
    List<int> ticked = const [],
  }) {
    if (!settings.any) return VoicePrompt.silent;
    final utterances = <VoiceUtterance>[];

    final verified = [
      for (final index in autoChecked)
        if (index >= 0 &&
            index < checklist.items.length &&
            checklist.items[index].challenge &&
            settings.challenges)
          checklist.items[index],
    ];
    if (verified.length > spokenRunLimit) {
      utterances.add(VoiceUtterance('${verified.length} verified'));
    } else {
      for (final item in verified) {
        utterances.add(
          VoiceUtterance(_say(item.label), pauseAfter: challengePause),
        );
        if (item.result.isNotEmpty) {
          utterances.add(VoiceUtterance(_say(item.result)));
        }
      }
    }

    final done = [
      for (final index in ticked)
        if (index >= 0 &&
            index < checklist.items.length &&
            !checklist.items[index].challenge &&
            settings.flows)
          checklist.items[index],
    ];
    if (done.length > spokenRunLimit) {
      utterances.add(VoiceUtterance('${done.length} done'));
    } else if (done.length == 1) {
      if (done.single.result.isNotEmpty) {
        utterances.add(VoiceUtterance(_say(done.single.result)));
      }
    } else {
      for (final item in done) {
        final words = item.result.isEmpty
            ? _say(item.label)
            : '${_say(item.label)}, ${_say(item.result)}';
        utterances.add(VoiceUtterance(words));
      }
    }

    final next = _pointer(checklist, progress);
    if (next == null) {
      if (_isComplete(checklist, progress)) {
        utterances.add(const VoiceUtterance('Checklist complete'));
        return VoicePrompt(utterances: utterances, complete: true);
      }
      return VoicePrompt(utterances: utterances);
    }
    final item = checklist.items[next];
    if (!settings.speaksFor(challenge: item.challenge)) {
      return VoicePrompt(utterances: utterances);
    }
    utterances.add(VoiceUtterance(_say(item.label)));
    return VoicePrompt(
      utterances: utterances,
      waitingFor: next,
      waitingForChallenge: item.challenge,
    );
  }

  /// The title as it is spoken: the word "challenge" is dropped, all-capital
  /// words are read as words, and it ends with "checklist" (`CHALLENGE BEFORE
  /// START` is "before start checklist").
  static String spokenTitle(Checklist checklist) {
    var title = checklist.title.isEmpty ? checklist.name : checklist.title;
    title = title
        .replaceAll(RegExp(r'\bchallenge\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    if (title.isEmpty) return 'checklist';
    return title.endsWith('checklist') ? title : '$title checklist';
  }

  /// "Ready for <title>?", asked when a challenge checklist is opened in auto
  /// mode; the pilot answers yes to start.
  VoicePrompt ready(Checklist checklist) => VoicePrompt(
    utterances: [VoiceUtterance('Ready for ${spokenTitle(checklist)}?')],
  );

  /// Whether the next row to do on [checklist] is a challenge row, so the
  /// voice asks if the pilot is ready before it starts.
  bool startsWithChallenge(Checklist checklist, ChecklistProgress progress) {
    final next = _pointer(checklist, progress);
    return next != null && checklist.items[next].challenge;
  }

  /// What to say when the pilot's tick or answer disagrees with the sim.
  VoicePrompt doubleCheck(ChecklistItem item) => VoicePrompt(
    utterances: [VoiceUtterance('Double check ${_say(item.label)}')],
  );

  /// The question after a close match.
  VoicePrompt didYouMean(String phrase) =>
      VoicePrompt(utterances: [VoiceUtterance('Did you mean $phrase?')]);

  /// The first enabled, unticked, unskipped check item at or after the cursor.
  int? _pointer(Checklist checklist, ChecklistProgress progress) {
    for (
      var i = progress.cursorOf(checklist.name);
      i < checklist.items.length;
      i++
    ) {
      if (checklist.items[i].isCheckable &&
          progress.isEnabled(checklist, i) &&
          !progress.isChecked(checklist.name, i) &&
          !progress.isSkipped(checklist.name, i)) {
        return i;
      }
    }
    return null;
  }

  /// Whether every enabled check item is ticked or skipped.
  bool _isComplete(Checklist checklist, ChecklistProgress progress) {
    var total = 0;
    var done = 0;
    for (var i = 0; i < checklist.items.length; i++) {
      if (!checklist.items[i].isCheckable ||
          !progress.isEnabled(checklist, i)) {
        continue;
      }
      total++;
      if (progress.isChecked(checklist.name, i) ||
          progress.isSkipped(checklist.name, i)) {
        done++;
      }
    }
    return total > 0 && done == total;
  }

  /// Text for speech: an all-capital word of four or more letters is lower
  /// case, so the voice reads it as a word and does not spell it. Shorter
  /// ones (`ENG`, `OAT`) stay as they are.
  static String _say(String text) => text.replaceAllMapped(
    RegExp(r'\b[A-Z]{4,}\b'),
    (m) => m.group(0)!.toLowerCase(),
  );
}
