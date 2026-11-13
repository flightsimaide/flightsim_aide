import 'package:equatable/equatable.dart';

/// A named colour from a `sw_define_colour` line; components are 0 to 1.
class ChecklistColour extends Equatable {
  /// Creates a colour; [red], [green] and [blue] are each 0 to 1.
  const ChecklistColour(this.name, this.red, this.green, this.blue);

  /// The name used in `\name\` markers, matched exactly.
  final String name;

  /// Red component, 0 to 1.
  final double red;

  /// Green component, 0 to 1.
  final double green;

  /// Blue component, 0 to 1.
  final double blue;

  @override
  List<Object?> get props => [name, red, green, blue];
}
