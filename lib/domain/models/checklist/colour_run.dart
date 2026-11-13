import 'package:equatable/equatable.dart';

/// A piece of item text drawn in one colour.
class ColourRun extends Equatable {
  /// Creates a run; [colour] is null for the default colour.
  const ColourRun(this.text, [this.colour]);

  /// The text of this run, never empty when produced by the parser.
  final String text;

  /// The name from a `\name\` marker, null for the default colour.
  ///
  /// Resolve it with the document's palette; an undefined name means the
  /// default colour.
  final String? colour;

  @override
  List<Object?> get props => [text, colour];
}
