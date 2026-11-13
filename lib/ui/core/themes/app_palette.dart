import 'package:flutter/material.dart';

/// The six colours one mode of the app is built from.
///
/// Every `ColorScheme` role Flutter's Material 3 widgets read is mapped from
/// these six (see [toColorScheme]), so changing one colour here changes every
/// widget that uses it. The status colours (red, amber, green) live apart in
/// `StatusColors`.
class AppPalette {
  /// Creates a palette.
  const AppPalette({
    required this.background,
    required this.surface,
    required this.text,
    required this.mutedText,
    required this.accent,
    required this.outline,
  });

  /// Starts from the colours Material 3 generates for [seed], then keeps only
  /// the six this app uses.
  factory AppPalette.fromSeed(Color seed, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final light = brightness == Brightness.light;
    return AppPalette(
      background: light ? scheme.surfaceContainer : scheme.surface,
      surface: light ? scheme.surfaceContainerHigh : scheme.surfaceContainer,
      text: scheme.onSurface,
      mutedText: scheme.onSurfaceVariant,
      accent: scheme.primary,
      outline: scheme.outline,
    );
  }

  /// Page and app bar background.
  final Color background;

  /// Cards, rows, dialogs, sheets, bars and fields.
  final Color surface;

  /// Main text and icons.
  final Color text;

  /// Secondary text, hints and captions.
  final Color mutedText;

  /// Buttons, switches, selection and links.
  final Color accent;

  /// Borders and dividers.
  final Color outline;

  /// A copy with the given colours replaced.
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? text,
    Color? mutedText,
    Color? accent,
    Color? outline,
  }) => AppPalette(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    text: text ?? this.text,
    mutedText: mutedText ?? this.mutedText,
    accent: accent ?? this.accent,
    outline: outline ?? this.outline,
  );

  /// Maps the six colours (and the status red) onto every `ColorScheme` role.
  ColorScheme toColorScheme(Brightness brightness, {required Color error}) {
    final onAccent = _onColor(accent);
    final accentContainer = Color.alphaBlend(
      accent.withValues(alpha: 0.25),
      surface,
    );
    return ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: accentContainer,
      onPrimaryContainer: text,
      secondary: accent,
      onSecondary: onAccent,
      secondaryContainer: accentContainer,
      onSecondaryContainer: text,
      tertiary: accent,
      onTertiary: onAccent,
      tertiaryContainer: accentContainer,
      onTertiaryContainer: text,
      error: error,
      onError: _onColor(error),
      errorContainer: Color.alphaBlend(error.withValues(alpha: 0.25), surface),
      onErrorContainer: text,
      surface: background,
      onSurface: text,
      onSurfaceVariant: mutedText,
      surfaceDim: background,
      surfaceBright: surface,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surface,
      surfaceContainerHighest: surface,
      outline: outline,
      outlineVariant: outline.withValues(alpha: 0.5),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: text,
      onInverseSurface: background,
      inversePrimary: accent,
      surfaceTint: Colors.transparent,
    );
  }

  static Color _onColor(Color c) =>
      ThemeData.estimateBrightnessForColor(c) == Brightness.dark
      ? Colors.white
      : Colors.black;

  @override
  bool operator ==(Object other) =>
      other is AppPalette &&
      other.background == background &&
      other.surface == surface &&
      other.text == text &&
      other.mutedText == mutedText &&
      other.accent == accent &&
      other.outline == outline;

  @override
  int get hashCode =>
      Object.hash(background, surface, text, mutedText, accent, outline);
}
