import 'package:equatable/equatable.dart';

import '../voice/voice_settings.dart';

/// One user option: a key, a default and the rule that turns any value into a
/// valid one. Adding an option needs only an [OptionDef] (decision D-51,
/// AC-40).
sealed class OptionDef<T extends Object> {
  const OptionDef(this.key, this.defaultValue);

  /// The storage key.
  final String key;

  /// The value used when nothing valid is stored.
  final T defaultValue;

  /// [value] forced into the valid range.
  T sanitize(T value);

  /// Reads the stored text; null when it is not a valid value.
  T? decode(String text);

  /// The text to store for [value].
  String encode(T value) => '$value';
}

/// A whole-number option kept between [min] and [max].
final class IntOption extends OptionDef<int> {
  /// Creates the definition.
  const IntOption(super.key, super.defaultValue, this.min, this.max);

  /// The smallest valid value.
  final int min;

  /// The largest valid value.
  final int max;

  @override
  int sanitize(int value) => value < min ? min : (value > max ? max : value);

  /// A stored value outside the range is damaged, so it gives the default
  /// (null here), not the nearest end.
  @override
  int? decode(String text) {
    final v = int.tryParse(text.trim());
    return v != null && v >= min && v <= max ? v : null;
  }
}

/// A yes/no option.
final class BoolOption extends OptionDef<bool> {
  /// Creates the definition.
  const BoolOption(super.key, super.defaultValue);

  @override
  bool sanitize(bool value) => value;

  @override
  bool? decode(String text) => switch (text.trim()) {
    'true' => true,
    'false' => false,
    _ => null,
  };
}

/// The options a user can change, with their defaults. Immutable.
///
/// Values live in a map keyed by [OptionDef], so an option added later (here
/// or in a test) needs no change to this class.
class UserOptions extends Equatable {
  const UserOptions._(this._values);

  /// Every option at its default.
  static const defaults = UserOptions._({});

  /// How often the sim values reach the app, per second (1 to 60). A
  /// checklist is not an instrument, so the default is 5.
  static const streamRateHzOption = IntOption('stream_rate_hz', 5, 1, 60);

  /// Whether auto-check is on (true) or the user ticks every item (false).
  /// The user's own choice, kept until the user changes it.
  static const autoModeOption = BoolOption('auto_mode', true);

  /// Whether the voice speaks for flow rows (D-84). Off until the user turns
  /// it on: speech that starts by itself in a cockpit would surprise people.
  static const voiceFlowsOption = BoolOption('voice_flows', false);

  /// Whether the voice speaks for challenge rows (D-84). Off by default.
  static const voiceChallengesOption = BoolOption('voice_challenges', false);

  /// The options the app ships.
  static const List<OptionDef<Object>> definitions = [
    streamRateHzOption,
    autoModeOption,
    voiceFlowsOption,
    voiceChallengesOption,
  ];

  final Map<OptionDef<Object>, Object> _values;

  /// The value of [option], or its default.
  T get<T extends Object>(OptionDef<T> option) =>
      (_values[option] as T?) ?? option.defaultValue;

  /// A copy with [option] set to [value], forced into its valid range. Setting
  /// the default removes the entry so equal options are always equal.
  UserOptions set<T extends Object>(OptionDef<T> option, T value) {
    final next = {..._values};
    final clean = option.sanitize(value);
    if (clean == option.defaultValue) {
      next.remove(option);
    } else {
      next[option] = clean;
    }
    return UserOptions._(Map.unmodifiable(next));
  }

  /// Stream rate in values per second.
  int get streamRateHz => get(streamRateHzOption);

  /// Whether auto-check is on, as the user last chose it.
  bool get autoMode => get(autoModeOption);

  /// Which kinds of row the voice speaks for.
  VoiceSettings get voice => VoiceSettings(
    flows: get(voiceFlowsOption),
    challenges: get(voiceChallengesOption),
  );

  @override
  List<Object?> get props => [
    for (final e in _values.entries) (e.key.key, e.value),
  ];
}
