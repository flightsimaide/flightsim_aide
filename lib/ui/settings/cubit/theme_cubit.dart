import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/settings/settings_repository.dart';
import '../../../domain/models/settings/appearance.dart';
import 'theme_state.dart';

/// Holds the Appearance choices (mode and changed colours), keeps them in the
/// [SettingsRepository] and gives the app the themes built from them.
class ThemeCubit extends Cubit<ThemeState> {
  /// Creates the cubit with the defaults; call [load] to read the saved ones.
  ThemeCubit({required this._settings})
    : super(ThemeState(Appearance.defaults));

  final SettingsRepository _settings;

  /// Reads the saved choices.
  Future<void> load() async {
    final saved = (await _settings.appearance()).valueOrNull;
    if (isClosed || saved == null) return;
    emit(ThemeState(saved));
  }

  /// Chooses dark, light or follow the system, and keeps it.
  Future<void> setMode(AppearanceMode mode) =>
      _change(state.appearance.withMode(mode));

  /// Shows [color] for [brightness] without keeping it (the picker is open).
  void previewColor(Brightness brightness, ThemeColor which, Color color) =>
      emit(ThemeState(_with(brightness, which, color)));

  /// Changes a colour and keeps it.
  Future<void> setColor(Brightness brightness, ThemeColor which, Color color) =>
      _change(_with(brightness, which, color));

  /// Back to the chosen colours and follow-the-system.
  Future<void> restoreDefaults() => _change(Appearance.defaults);

  Appearance _with(Brightness brightness, ThemeColor which, Color color) {
    final key = themeColorKey(brightness, which);
    return color.toARGB32() ==
            ThemeState.defaultOf(brightness, which).toARGB32()
        ? state.appearance.withoutColor(key)
        : state.appearance.withColor(key, color.toARGB32());
  }

  Future<void> _change(Appearance next) async {
    emit(ThemeState(next));
    await _settings.saveAppearance(next);
  }
}
