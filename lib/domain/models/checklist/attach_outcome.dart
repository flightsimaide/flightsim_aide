import 'package:equatable/equatable.dart';

/// What happened to the marks when a checklist was attached to an aircraft or
/// the connection came back.
sealed class AttachOutcome extends Equatable {
  const AttachOutcome();

  @override
  List<Object?> get props => const [];
}

/// Nothing was saved, or no aircraft is known: the marks start clean.
final class AttachClean extends AttachOutcome {
  /// Creates the outcome.
  const AttachClean();
}

/// Saved marks were loaded silently. [lastViewed] is the checklist that was
/// open last, if it is known.
final class AttachRestored extends AttachOutcome {
  /// Creates the outcome.
  const AttachRestored(this.lastViewed);

  /// Name of the checklist to reopen.
  final String? lastViewed;

  @override
  List<Object?> get props => [lastViewed];
}

/// Saved marks were discarded silently.
final class AttachReset extends AttachOutcome {
  /// Creates the outcome.
  const AttachReset();
}

/// The user must choose between the saved marks and a clean start.
final class AttachNeedsPrompt extends AttachOutcome {
  /// Creates the outcome.
  const AttachNeedsPrompt();
}

/// The connection came back and the marks stay as they are.
final class AttachKeep extends AttachOutcome {
  /// Creates the outcome.
  const AttachKeep();
}
