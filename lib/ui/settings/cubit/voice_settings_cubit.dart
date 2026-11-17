import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/settings/settings_repository.dart';
import '../../../domain/models/settings/user_options.dart';
import '../../../domain/models/voice/voice_settings.dart';

/// Holds the two voice switches (D-84) and keeps them in the
/// [SettingsRepository]. Both are off until the user turns them on.
class VoiceSettingsCubit extends Cubit<VoiceSettings> {
  /// Creates the cubit from the options now in [settings] and follows later
  /// changes.
  VoiceSettingsCubit({required SettingsRepository settings})
    : _settings = settings,
      super(settings.options.voice) {
    _sub = settings.optionsChanges.listen((o) {
      if (!isClosed) emit(o.voice);
    });
  }

  final SettingsRepository _settings;
  late final StreamSubscription<UserOptions> _sub;

  /// Turns the voice for flow rows on or off, and keeps it.
  Future<void> setFlows(bool on) =>
      _settings.update((o) => o.set(UserOptions.voiceFlowsOption, on));

  /// Turns the voice for challenge rows on or off, and keeps it.
  Future<void> setChallenges(bool on) =>
      _settings.update((o) => o.set(UserOptions.voiceChallengesOption, on));

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
