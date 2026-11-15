import 'package:equatable/equatable.dart';

/// A switch the pilot can turn on or off (`sw_switch`, `GRAMMAR.md` section
/// 5b): an [id] shared by the whole file and the position it starts in.
class SwitchDef extends Equatable {
  /// Creates a switch definition.
  const SwitchDef(this.id, {this.defaultOn = false});

  /// The switch's id, lower case; every block that names it follows it.
  final String id;

  /// Whether the switch starts on (a new flight, or no saved position).
  final bool defaultOn;

  @override
  List<Object?> get props => [id, defaultOn];
}

/// The branch of a switch an item belongs to: it is shown, counted and checked
/// only while the switch is [whenOn] (`true` for the ON branch, `false` for
/// the OFF branch).
class SwitchGate extends Equatable {
  /// Creates a gate on [switchDef].
  const SwitchGate(this.switchDef, {required this.whenOn});

  /// The switch the branch depends on.
  final SwitchDef switchDef;

  /// The position of the switch in which the item is shown.
  final bool whenOn;

  /// The id of the switch.
  String get id => switchDef.id;

  @override
  List<Object?> get props => [switchDef, whenOn];
}
