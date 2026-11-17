import '../../models/voice/spoken_input.dart';

/// Reads a recognised phrase against the item the voice is waiting on.
///
/// Pure Dart. The accepted answers are the fixed words `check`, `set`, `on`,
/// `off` and `closed` and the item's own result text; the commands are
/// `skip`, `pause checklist` and `resume checklist` (D-84). A phrase that is
/// not exact but is within a small edit distance of one of them gives a
/// [SpokenCloseMatch], so the voice can ask "Did you mean ...?". The distance
/// allowed is 1 for a word of up to five letters and 2 for a longer one, and a
/// word of under three letters (`on`, `no`) must be exact, because one slip
/// there turns it into another word.
class MatchSpokenResponseUseCase {
  /// Creates the use case.
  const MatchSpokenResponseUseCase();

  /// The fixed answer words every item accepts.
  static const fixedAnswers = ['check', 'set', 'on', 'off', 'closed'];

  static const _yes = {
    'yes',
    'yeah',
    'yep',
    'correct',
    'affirmative',
    'affirm',
    'ready',
    'okay',
    'ok',
    'roger',
    'proceed',
    'go ahead',
  };
  static const _no = {'no', 'nope', 'negative'};
  static const _pauseWords = ['pause', 'hold', 'stop'];
  static const _resumeWords = ['resume', 'continue', 'unpause', 'start'];

  /// Lower case, letters and digits only, single spaces.
  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r' +'), ' ');

  /// What [heard] means for an item whose result text is [itemResult] (empty
  /// when it has none).
  SpokenInput match(String heard, {String itemResult = ''}) {
    final said = normalize(heard);
    if (said.isEmpty) return const SpokenUnknown();

    final targets = <String, SpokenInput>{
      'skip': const SpokenSkip(),
      for (final word in _pauseWords) '$word checklist': const SpokenPause(),
      for (final word in _resumeWords) '$word checklist': const SpokenResume(),
      for (final word in fixedAnswers) word: SpokenAnswer(word),
    };
    final result = normalize(itemResult);
    if (result.isNotEmpty) targets[result] = SpokenAnswer(result);

    final exact = targets[said];
    if (exact != null) return exact;
    if (_yes.contains(said)) return const SpokenYes();
    if (_no.contains(said)) return const SpokenNo();

    if (said.length < 3) return const SpokenUnknown();
    String? best;
    var bestDistance = 1 << 30;
    for (final phrase in targets.keys) {
      if (phrase.length < 3) continue;
      final allowed = phrase.length <= 5 ? 1 : 2;
      final distance = _distance(said, phrase);
      if (distance <= allowed && distance < bestDistance) {
        best = phrase;
        bestDistance = distance;
      }
    }
    if (best == null) return const SpokenUnknown();
    return SpokenCloseMatch(best, targets[best]!);
  }

  /// Levenshtein distance between [a] and [b].
  static int _distance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        current[j] = [
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }
}
