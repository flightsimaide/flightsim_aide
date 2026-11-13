import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'status_colors.dart';

/// Material 3 themes with large, easy-to-tap checklist rows.
///
/// Each mode is built from an [AppPalette] (six colours) and [StatusColors].
abstract final class AppTheme {
  static const Color _seed = Colors.blueGrey;

  /// The default light palette.
  static final AppPalette lightPalette =
      AppPalette.fromSeed(_seed, Brightness.light).copyWith(
        background: const Color(0xFFE4E9EC),
        surface: const Color(0xFFD5D4D5),
      );

  /// The default dark palette.
  static final AppPalette darkPalette = AppPalette.fromSeed(
    _seed,
    Brightness.dark,
  );

  /// Light theme.
  static final ThemeData light = build(
    lightPalette,
    Brightness.light,
    StatusColors.light,
  );

  /// Dark theme.
  static final ThemeData dark = build(
    darkPalette,
    Brightness.dark,
    StatusColors.dark,
  );

  /// Builds a theme from [palette] and [status].
  static ThemeData build(
    AppPalette palette,
    Brightness brightness,
    StatusColors status,
  ) {
    final scheme = palette.toColorScheme(brightness, error: status.error);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: [status],
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 18),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 18),
      ),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
