import 'package:equatable/equatable.dart';

/// Which kinds of row the voice speaks for (D-84). Both are off by default.
class VoiceSettings extends Equatable {
  /// Creates settings; the voice is silent unless a kind is turned on.
  const VoiceSettings({this.flows = false, this.challenges = false});

  /// Voice for flow rows (rows outside `sw_challenge`): reads the next item
  /// and waits for the pilot to do it.
  final bool flows;

  /// Voice for challenge rows: plays the reading crew member.
  final bool challenges;

  /// Whether the voice speaks for a row of the given kind.
  bool speaksFor({required bool challenge}) => challenge ? challenges : flows;

  /// Whether the voice is on for any kind.
  bool get any => flows || challenges;

  @override
  List<Object?> get props => [flows, challenges];
}
