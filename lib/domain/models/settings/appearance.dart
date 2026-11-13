import 'package:equatable/equatable.dart';

/// Which theme the app uses.
enum AppearanceMode {
  /// Follow the device.
  system,

  /// Always the light theme.
  light,

  /// Always the dark theme.
  dark,
}

/// The user's Appearance choices: the mode and every colour they changed.
///
/// [colors] holds only the changed colours, as ARGB integers under keys such
/// as `dark.background` or `light.status.error`; a colour that is absent has
/// its default (task 0.06).
class Appearance extends Equatable {
  /// Creates the choices.
  const Appearance({this.mode = AppearanceMode.system, this.colors = const {}});

  /// The defaults: follow the system, no changed colour.
  static const defaults = Appearance();

  /// Dark, light or follow the system.
  final AppearanceMode mode;

  /// The changed colours, by key.
  final Map<String, int> colors;

  /// A copy with [mode] replaced.
  Appearance withMode(AppearanceMode mode) =>
      Appearance(mode: mode, colors: colors);

  /// A copy with the colour under [key] set to [argb].
  Appearance withColor(String key, int argb) =>
      Appearance(mode: mode, colors: {...colors, key: argb});

  /// A copy with the colour under [key] back at its default.
  Appearance withoutColor(String key) =>
      Appearance(mode: mode, colors: {...colors}..remove(key));

  /// A copy without any changed colour; the mode stays.
  Appearance withoutColors() => Appearance(mode: mode);

  @override
  List<Object?> get props => [mode, colors];
}
