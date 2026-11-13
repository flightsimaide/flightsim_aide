import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/settings/appearance.dart';
import '../../core/themes/app_palette.dart';
import '../../core/themes/app_theme.dart';
import '../../core/themes/status_colors.dart';

/// The names of the ten editable colours: six palette colours, four status
/// colours.
enum ThemeColor {
  /// Page and app bar background.
  background('background'),

  /// Cards, rows, dialogs, bars and fields.
  surface('surface'),

  /// Main text and icons.
  text('text'),

  /// Secondary text.
  mutedText('mutedText'),

  /// Buttons, switches and selection.
  accent('accent'),

  /// Borders and dividers.
  outline('outline'),

  /// Good (green).
  success('success (green)'),

  /// Caution (amber).
  caution('caution (amber)'),

  /// Warning (red).
  error('error (red)'),

  /// Information (cyan): does not affect the operation of the aircraft.
  info('info (cyan)');

  const ThemeColor(this.label);

  /// What the Appearance page calls it.
  final String label;

  /// Whether this is one of the three status colours.
  bool get isStatus => index >= ThemeColor.success.index;
}

/// The key of [color] for [brightness] in `Appearance.colors`.
String themeColorKey(Brightness brightness, ThemeColor color) =>
    '${brightness.name}.${color.name}';

/// The user's Appearance choices and the themes built from them.
class ThemeState extends Equatable {
  /// Creates the state for [appearance].
  ThemeState(this.appearance)
    : light = _build(appearance, Brightness.light),
      dark = _build(appearance, Brightness.dark);

  /// What the user chose.
  final Appearance appearance;

  /// The light theme with the user's colours.
  final ThemeData light;

  /// The dark theme with the user's colours.
  final ThemeData dark;

  /// Dark, light or system for `MaterialApp.themeMode`.
  ThemeMode get themeMode => switch (appearance.mode) {
    AppearanceMode.system => ThemeMode.system,
    AppearanceMode.light => ThemeMode.light,
    AppearanceMode.dark => ThemeMode.dark,
  };

  /// The colour [color] has for [brightness] now.
  Color colorOf(Brightness brightness, ThemeColor color) {
    final theme = brightness == Brightness.light ? light : dark;
    final status = theme.extension<StatusColors>()!;
    final palette = _palette(appearance, brightness);
    return switch (color) {
      ThemeColor.background => palette.background,
      ThemeColor.surface => palette.surface,
      ThemeColor.text => palette.text,
      ThemeColor.mutedText => palette.mutedText,
      ThemeColor.accent => palette.accent,
      ThemeColor.outline => palette.outline,
      ThemeColor.success => status.success,
      ThemeColor.caution => status.caution,
      ThemeColor.error => status.error,
      ThemeColor.info => status.info,
    };
  }

  static final _defaults = ThemeState(Appearance.defaults);

  /// The default of [color] for [brightness].
  static Color defaultOf(Brightness brightness, ThemeColor color) =>
      _defaults.colorOf(brightness, color);

  static AppPalette _palette(Appearance a, Brightness b) {
    final base = b == Brightness.light
        ? AppTheme.lightPalette
        : AppTheme.darkPalette;
    Color pick(ThemeColor c, Color fallback) {
      final v = a.colors[themeColorKey(b, c)];
      return v == null ? fallback : Color(v);
    }

    return AppPalette(
      background: pick(ThemeColor.background, base.background),
      surface: pick(ThemeColor.surface, base.surface),
      text: pick(ThemeColor.text, base.text),
      mutedText: pick(ThemeColor.mutedText, base.mutedText),
      accent: pick(ThemeColor.accent, base.accent),
      outline: pick(ThemeColor.outline, base.outline),
    );
  }

  static ThemeData _build(Appearance a, Brightness b) {
    final base = b == Brightness.light ? StatusColors.light : StatusColors.dark;
    Color pick(ThemeColor c, Color fallback) {
      final v = a.colors[themeColorKey(b, c)];
      return v == null ? fallback : Color(v);
    }

    final status = StatusColors(
      success: pick(ThemeColor.success, base.success),
      caution: pick(ThemeColor.caution, base.caution),
      error: pick(ThemeColor.error, base.error),
      info: pick(ThemeColor.info, base.info),
      // A caution colour the user set is used as the fill too.
      cautionFill: a.colors.containsKey(themeColorKey(b, ThemeColor.caution))
          ? null
          : base.cautionFill,
    );
    return AppTheme.build(_palette(a, b), b, status);
  }

  @override
  List<Object?> get props => [appearance];
}
