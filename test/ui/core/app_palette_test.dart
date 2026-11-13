import 'package:flightsim_aide/ui/core/themes/app_palette.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flightsim_aide/ui/core/themes/status_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const palette = AppPalette(
    background: Color(0xFF101010),
    surface: Color(0xFF202020),
    text: Color(0xFFEEEEEE),
    mutedText: Color(0xFFAAAAAA),
    accent: Color(0xFF3366CC),
    outline: Color(0xFF666666),
  );

  test('the six colours map onto the ColorScheme roles', () {
    final s = palette.toColorScheme(Brightness.dark, error: Colors.red);
    expect(s.surface, palette.background);
    expect(s.surfaceContainerHigh, palette.surface);
    expect(s.onSurface, palette.text);
    expect(s.onSurfaceVariant, palette.mutedText);
    expect(s.primary, palette.accent);
    expect(s.outline, palette.outline);
    expect(s.error, Colors.red);
  });

  test('text on the accent is readable', () {
    final dark = palette.copyWith(accent: const Color(0xFF111111));
    final light = palette.copyWith(accent: const Color(0xFFEEEEEE));
    expect(
      dark.toColorScheme(Brightness.dark, error: Colors.red).onPrimary,
      Colors.white,
    );
    expect(
      light.toColorScheme(Brightness.dark, error: Colors.red).onPrimary,
      Colors.black,
    );
  });

  test('copyWith changes only the given colour', () {
    final changed = palette.copyWith(accent: Colors.green);
    expect(changed.accent, Colors.green);
    expect(changed.background, palette.background);
    expect(changed == palette, isFalse);
    expect(palette.copyWith() == palette, isTrue);
  });

  test('both themes carry the status colours', () {
    expect(AppTheme.dark.extension<StatusColors>(), StatusColors.dark);
    expect(AppTheme.light.extension<StatusColors>(), StatusColors.light);
  });
}
