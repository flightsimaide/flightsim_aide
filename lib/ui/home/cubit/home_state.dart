import 'package:equatable/equatable.dart';

import '../../../domain/models/aircraft/aircraft_identity.dart';
import '../../../domain/models/checklist/checklist_document.dart';

/// State of the home screen.
sealed class HomeState extends Equatable {
  const HomeState();

  @override
  List<Object?> get props => const [];
}

/// Nothing loaded yet, or the last attempt was cancelled or dismissed.
final class HomeInitial extends HomeState {
  /// Creates the initial state.
  const HomeInitial();
}

/// A checklist file is being picked and parsed.
final class HomeLoading extends HomeState {
  /// Creates the loading state.
  const HomeLoading();
}

/// A document was loaded. The home screen stays where it is; only an answer
/// "Use saved progress" to the restore question opens the list ([openList]).
final class HomeLoaded extends HomeState {
  /// Creates the loaded state holding [document], loaded for [aircraft]
  /// (null for the file and sample sources).
  const HomeLoaded(
    this.document, {
    this.aircraft,
    this.openLast,
    this.openList = false,
  });

  /// The document that was loaded.
  final ChecklistDocument document;

  /// The simulator's aircraft the document was loaded for, if any.
  final AircraftIdentity? aircraft;

  /// Name of the checklist to open after the list, when saved progress was
  /// used and it has a last viewed checklist.
  final String? openLast;

  /// Whether the home screen should open the list now (and [openLast]): true
  /// only right after the user chose to use the saved progress.
  final bool openList;

  @override
  List<Object?> get props => [document, aircraft, openLast, openList];
}

/// Saved progress exists and the user must choose between it and a clean
/// start. The document is loaded; nothing is marked until the answer.
final class HomePromptRestore extends HomeState {
  /// Creates the state.
  const HomePromptRestore(this.document, {this.aircraft});

  /// The document that was loaded.
  final ChecklistDocument document;

  /// The simulator's aircraft the document was loaded for.
  final AircraftIdentity? aircraft;

  @override
  List<Object?> get props => [document, aircraft];
}

/// The connection came back after a long gap and the user must choose
/// between keeping the marks and starting clean. The checklist stays shown.
final class HomeReconnectPrompt extends HomeState {
  /// Creates the state.
  const HomeReconnectPrompt(this.document, {this.aircraft});

  /// The document on screen.
  final ChecklistDocument document;

  /// The aircraft it belongs to.
  final AircraftIdentity? aircraft;

  @override
  List<Object?> get props => [document, aircraft];
}

/// The simulator changed aircraft while the checklist was loading; the result
/// was discarded (D-32).
final class HomeAircraftChanged extends HomeState {
  /// Creates the state.
  const HomeAircraftChanged();
}

/// Loading failed with a user-presentable [message].
final class HomeFailure extends HomeState {
  /// Creates a failure described by [message].
  const HomeFailure(this.message);

  /// What went wrong, as shown to the user.
  final String message;

  @override
  List<Object?> get props => [message];
}
