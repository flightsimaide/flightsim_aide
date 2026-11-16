import 'package:equatable/equatable.dart';

import 'checklist.dart';
import 'checklist_colour.dart';
import 'lookup_table.dart';

/// The result of parsing one checklist file: its checklists and any warnings.
class ChecklistDocument extends Equatable {
  /// Creates a document; the lists and the palette are copied into
  /// unmodifiable collections.
  ChecklistDocument({
    required List<Checklist> checklists,
    required List<String> warnings,
    Map<String, ChecklistColour> colours = const {},
    Map<String, LookupTable> tables = const {},
    this.sourceName = '',
  }) : checklists = List.unmodifiable(checklists),
       warnings = List.unmodifiable(warnings),
       colours = Map.unmodifiable(colours),
       tables = Map.unmodifiable(tables);

  /// The parsed checklists, in file order.
  final List<Checklist> checklists;

  /// Parse warnings, each starting with `Line N: ` unless file-level.
  final List<String> warnings;

  /// Colours defined by `sw_define_colour`, keyed by name.
  final Map<String, ChecklistColour> colours;

  /// Lookup tables defined by `sw_table`, keyed by name; never shown.
  final Map<String, LookupTable> tables;

  /// File name shown to the user, empty if unknown.
  final String sourceName;

  /// Returns a copy with [sourceName] replaced.
  ChecklistDocument copyWith({String? sourceName}) => ChecklistDocument(
    checklists: checklists,
    warnings: warnings,
    colours: colours,
    tables: tables,
    sourceName: sourceName ?? this.sourceName,
  );

  @override
  List<Object?> get props => [
    checklists,
    warnings,
    colours,
    tables,
    sourceName,
  ];
}
