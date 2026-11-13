import 'package:flightsim_aide/domain/models/settings/appearance.dart';
import 'package:flightsim_aide/ui/core/themes/app_theme.dart';
import 'package:flightsim_aide/ui/settings/cubit/theme_cubit.dart';
import 'package:flightsim_aide/ui/settings/cubit/theme_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_settings_repository.dart';

void main() {
  late FakeSettingsRepository settings;
  late ThemeCubit cubit;

  setUp(() {
    settings = FakeSettingsRepository();
    cubit = ThemeCubit(settings: settings);
  });
  tearDown(() => cubit.close());

  test('starts with the chosen defaults and follows the system', () {
    expect(cubit.state.themeMode, ThemeMode.system);
    expect(cubit.state.dark.colorScheme.primary, AppTheme.darkPalette.accent);
    expect(
      cubit.state.light.colorScheme.surface,
      AppTheme.lightPalette.background,
    );
  });

  test('load reads the saved choices', () async {
    await settings.saveAppearance(
      const Appearance(
        mode: AppearanceMode.light,
        colors: {'light.accent': 0xFF00FF00},
      ),
    );
    await cubit.load();
    expect(cubit.state.themeMode, ThemeMode.light);
    expect(cubit.state.light.colorScheme.primary, const Color(0xFF00FF00));
    expect(cubit.state.dark.colorScheme.primary, AppTheme.darkPalette.accent);
  });

  test('setMode changes the mode and keeps it', () async {
    await cubit.setMode(AppearanceMode.dark);
    expect(cubit.state.themeMode, ThemeMode.dark);
    expect(
      (await settings.appearance()).valueOrNull!.mode,
      AppearanceMode.dark,
    );
  });

  test('setColor changes one colour of one theme and keeps it', () async {
    await cubit.setColor(
      Brightness.dark,
      ThemeColor.accent,
      const Color(0xFF00FF00),
    );
    expect(cubit.state.dark.colorScheme.primary, const Color(0xFF00FF00));
    expect(cubit.state.light.colorScheme.primary, AppTheme.lightPalette.accent);
    expect((await settings.appearance()).valueOrNull!.colors, {
      'dark.accent': 0xFF00FF00,
    });
  });

  test('a status colour reaches the scheme error colour', () async {
    await cubit.setColor(
      Brightness.light,
      ThemeColor.error,
      const Color(0xFF0000FF),
    );
    expect(cubit.state.light.colorScheme.error, const Color(0xFF0000FF));
  });

  test('previewColor shows a colour without keeping it', () async {
    const red = Color(0xFFFF0000);
    cubit.previewColor(Brightness.dark, ThemeColor.accent, red);
    expect(cubit.state.dark.colorScheme.primary, red);
    expect((await settings.appearance()).valueOrNull, Appearance.defaults);
  });

  test('setting a colour back to its default drops it', () async {
    await cubit.setColor(
      Brightness.dark,
      ThemeColor.accent,
      const Color(0xFFFF0000),
    );
    await cubit.setColor(
      Brightness.dark,
      ThemeColor.accent,
      AppTheme.darkPalette.accent,
    );
    expect(cubit.state.appearance.colors, isEmpty);
    expect((await settings.appearance()).valueOrNull, Appearance.defaults);
  });

  test('restoreDefaults brings back the colours and the system mode', () async {
    await cubit.setMode(AppearanceMode.dark);
    await cubit.setColor(
      Brightness.dark,
      ThemeColor.accent,
      const Color(0xFFFF0000),
    );
    await cubit.restoreDefaults();
    expect(cubit.state.appearance, Appearance.defaults);
    expect(cubit.state.dark.colorScheme.primary, AppTheme.darkPalette.accent);
    expect((await settings.appearance()).valueOrNull, Appearance.defaults);
  });
}
