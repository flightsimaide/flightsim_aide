import 'package:equatable/equatable.dart';

/// What the pilot said, read against the item the voice is waiting on
/// (`GRAMMAR.md` section 5d, D-84).
sealed class SpokenInput extends Equatable {
  /// Creates a spoken input.
  const SpokenInput();

  @override
  List<Object?> get props => [];
}

/// An accepted answer for the item: `check`, `set`, `on`, `off`, `closed` or
/// the item's own result text. [word] is the normalized text that matched.
class SpokenAnswer extends SpokenInput {
  /// Creates an answer that matched [word].
  const SpokenAnswer(this.word);

  /// The normalized text that matched.
  final String word;

  @override
  List<Object?> get props => [word];
}

/// `skip`: skip the item.
class SpokenSkip extends SpokenInput {
  /// Creates the input.
  const SpokenSkip();
}

/// `pause checklist` (or `hold` or `stop` before `checklist`).
class SpokenPause extends SpokenInput {
  /// Creates the input.
  const SpokenPause();
}

/// `resume checklist`, `continue checklist` and similar.
class SpokenResume extends SpokenInput {
  /// Creates the input.
  const SpokenResume();
}

/// `yes`, the reply to a "Did you mean" question.
class SpokenYes extends SpokenInput {
  /// Creates the input.
  const SpokenYes();
}

/// `no`, the reply to a "Did you mean" question.
class SpokenNo extends SpokenInput {
  /// Creates the input.
  const SpokenNo();
}

/// Close to, but not exactly, something that is understood: the voice asks
/// "Did you mean [phrase]?" and acts on [meant] when the pilot says yes.
class SpokenCloseMatch extends SpokenInput {
  /// Creates a close match to [phrase] that means [meant].
  const SpokenCloseMatch(this.phrase, this.meant);

  /// The words to read back to the pilot.
  final String phrase;

  /// What the pilot would have said had the words been exact.
  final SpokenInput meant;

  @override
  List<Object?> get props => [phrase, meant];
}

/// Nothing that is understood.
class SpokenUnknown extends SpokenInput {
  /// Creates the input.
  const SpokenUnknown();
}
