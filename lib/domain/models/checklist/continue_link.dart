import 'package:equatable/equatable.dart';

import '../flight_sim/item_condition.dart';

/// Where a `sw_continue` line sends the pilot after its checklist.
class ContinueLink extends Equatable {
  /// A bare `sw_continue`: the next checklist in the file.
  const ContinueLink.next({this.condition}) : target = null;

  /// `sw_continue:Name`: the checklist whose name is [target].
  const ContinueLink.named(String this.target, {this.condition});

  /// The target checklist name, null for the next checklist.
  final String? target;

  /// The condition that must hold to follow this link once the checklist is
  /// finished, or null for an unconditional link.
  final ItemCondition? condition;

  /// True for a bare `sw_continue`.
  bool get isNext => target == null;

  @override
  List<Object?> get props => [target, condition];
}
