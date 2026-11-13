import 'package:equatable/equatable.dart';

/// The saved marks of one checklist: the checked item indexes (sorted), the
/// ones among them the app checked, the ones the user ticked against the sim,
/// the ones skipped, the cursor auto-check had reached, and the
/// fingerprint of the checklist they belong to.
class StoredChecklistProgress extends Equatable {
  /// Creates an entry.
  const StoredChecklistProgress({
    required this.checked,
    required this.fingerprint,
    this.autoChecked = const [],
    this.disagreed = const [],
    this.skipped = const [],
    this.cursor = 0,
  });

  /// Checked item indexes, sorted ascending.
  final List<int> checked;

  /// Fingerprint of the checklist when the marks were saved.
  final String fingerprint;

  /// The checked indexes the app set from a sim value, sorted ascending.
  final List<int> autoChecked;

  /// The checked indexes the user ticked while the sim said the condition was
  /// false, sorted ascending.
  final List<int> disagreed;

  /// The item indexes the user skipped, sorted ascending.
  final List<int> skipped;

  /// Where auto-check looks next (0 is the top).
  final int cursor;

  @override
  List<Object?> get props => [
    checked,
    fingerprint,
    autoChecked,
    disagreed,
    skipped,
    cursor,
  ];
}

/// Everything saved for one aircraft, as raw values.
class StoredProgress extends Equatable {
  /// Creates the record.
  const StoredProgress({
    this.lastViewed,
    this.runId,
    this.checklists = const {},
  });

  /// Name of the checklist the user had open last.
  final String? lastViewed;

  /// The plugin's run id when the marks were saved; a different one later
  /// means X-Plane was restarted.
  final String? runId;

  /// Marks per checklist name.
  final Map<String, StoredChecklistProgress> checklists;

  @override
  List<Object?> get props => [lastViewed, runId, checklists];
}
