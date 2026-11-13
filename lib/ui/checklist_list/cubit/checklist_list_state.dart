import 'package:equatable/equatable.dart';

/// One row of the checklist list: a checklist and how far along it is.
class ChecklistSummary extends Equatable {
  /// Creates a summary; [done] and [total] count check items only.
  const ChecklistSummary({
    required this.name,
    required this.title,
    required this.done,
    required this.total,
    required this.isComplete,
    this.skipped = 0,
    this.overridden = 0,
  });

  /// Identifying name, used for the detail route.
  final String name;

  /// Display title.
  final String title;

  /// Number of check items that are checked.
  final int done;

  /// Number of check items.
  final int total;

  /// Whether every check item is checked (and there is at least one).
  final bool isComplete;

  /// Number of check items the user skipped.
  final int skipped;

  /// Number of check items ticked while the aircraft said they were not set.
  final int overridden;

  @override
  List<Object?> get props => [
    name,
    title,
    done,
    total,
    isComplete,
    skipped,
    overridden,
  ];
}

/// State of the checklist list screen.
sealed class ChecklistListState extends Equatable {
  const ChecklistListState();

  @override
  List<Object?> get props => const [];
}

/// Waiting for the first load.
final class ChecklistListLoading extends ChecklistListState {
  /// Creates the loading state.
  const ChecklistListLoading();
}

/// The current document's checklists, in flight order.
final class ChecklistListLoaded extends ChecklistListState {
  /// Creates the loaded state.
  const ChecklistListLoaded({
    required this.items,
    required this.warnings,
    required this.sourceName,
    this.warningsDismissed = false,
  });

  /// One summary per checklist.
  final List<ChecklistSummary> items;

  /// Parse warnings of the document.
  final List<String> warnings;

  /// File name shown in the app bar.
  final String sourceName;

  /// Whether the user hid the warnings banner.
  final bool warningsDismissed;

  /// Returns a copy with [warningsDismissed] replaced.
  ChecklistListLoaded copyWith({bool? warningsDismissed}) =>
      ChecklistListLoaded(
        items: items,
        warnings: warnings,
        sourceName: sourceName,
        warningsDismissed: warningsDismissed ?? this.warningsDismissed,
      );

  @override
  List<Object?> get props => [items, warnings, sourceName, warningsDismissed];
}

/// There is nothing to list.
final class ChecklistListFailure extends ChecklistListState {
  /// Creates a failure described by [message].
  const ChecklistListFailure(this.message);

  /// What went wrong, as shown to the user.
  final String message;

  @override
  List<Object?> get props => [message];
}
