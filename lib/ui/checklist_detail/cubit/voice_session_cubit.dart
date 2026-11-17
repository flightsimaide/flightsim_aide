import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/checklist/checklist_progress_repository.dart';
import '../../../data/repositories/checklist/checklist_repository.dart';
import '../../../data/repositories/settings/settings_repository.dart';
import '../../../data/repositories/voice/voice_repository.dart';
import '../../../domain/models/checklist/checklist.dart';
import '../../../domain/models/checklist/checklist_progress.dart';
import '../../../domain/models/voice/spoken_input.dart';
import '../../../domain/models/voice/voice_prompt.dart';
import '../../../domain/models/voice/voice_settings.dart';
import '../../../domain/use_cases/voice/build_voice_prompt_use_case.dart';
import '../../../domain/use_cases/voice/match_spoken_response_use_case.dart';
import 'voice_session_state.dart';

/// Plays the second pilot for one open checklist (D-84): reads the next item
/// after every step, listens for the pilot's answer and ticks or skips on it.
///
/// It follows the progress repository, so a tick by hand, by auto-check or by
/// voice is all the same to it. Ticking and skipping go through [_checkNext]
/// and [_skipNext], which the screen wires to the detail cubit, so a spoken
/// answer takes the same path as a tap (a sim that disagrees gives the same
/// warning). Nothing is spoken or heard while both settings are off.
class VoiceSessionCubit extends Cubit<VoiceSessionState> {
  /// Creates the cubit for the checklist called [_checklistName].
  VoiceSessionCubit({
    required this._checklistName,
    required this._checklistRepository,
    required this._progressRepository,
    required this._settings,
    required this._voice,
    required this._checkNext,
    required this._skipNext,
    BuildVoicePromptUseCase? prompts,
    MatchSpokenResponseUseCase? matcher,
  }) : _prompts = prompts ?? const BuildVoicePromptUseCase(),
       _matcher = matcher ?? const MatchSpokenResponseUseCase(),
       super(const VoiceSessionState());

  final String _checklistName;
  final ChecklistRepository _checklistRepository;
  final ChecklistProgressRepository _progressRepository;
  final SettingsRepository _settings;
  final VoiceRepository _voice;
  final void Function() _checkNext;
  final void Function() _skipNext;
  final BuildVoicePromptUseCase _prompts;
  final MatchSpokenResponseUseCase _matcher;

  final _subscriptions = <StreamSubscription<Object?>>[];
  ChecklistProgress _before = ChecklistProgress();
  VoiceSettings _voiceSettings = const VoiceSettings();
  VoicePrompt _prompt = VoicePrompt.silent;

  /// What a "yes" would do: the meaning of the last close match.
  SpokenInput? _pending;

  /// True from opening a challenge checklist in auto mode until the pilot says
  /// yes (or ticks something by hand): the voice asked "Ready for ...?" and
  /// reads nothing else meanwhile.
  bool _awaitingReady = false;

  /// Starts following the progress, the settings and the microphone.
  void load() {
    _before = _progressRepository.current;
    _voiceSettings = _settings.options.voice;
    _subscriptions
      ..add(_progressRepository.progress.listen(_onProgress))
      ..add(_settings.optionsChanges.listen((o) => _onSettings(o.voice)))
      ..add(_voice.phrases.listen(_onPhrase));
    if (_voiceSettings.any) _activate();
  }

  /// Pauses the voice: it stops speaking and ignores everything but
  /// "resume checklist". The screen flashes PAUSED.
  void pause() {
    if (!state.active || state.paused) return;
    _pending = null;
    unawaited(_voice.stopSpeaking());
    emit(state.copyWith(paused: true));
  }

  /// Carries on after a pause by reading the item the voice waits on.
  void resume() {
    if (!state.paused) return;
    emit(state.copyWith(paused: false));
    if (_awaitingReady) {
      _askReady();
    } else {
      _speak(_afterStep());
    }
  }

  Checklist? _find() {
    for (final c
        in _checklistRepository.current?.checklists ?? const <Checklist>[]) {
      if (c.name == _checklistName) return c;
    }
    return null;
  }

  VoicePrompt _afterStep({
    List<int> auto = const [],
    List<int> ticked = const [],
  }) {
    final checklist = _find();
    if (checklist == null) return VoicePrompt.silent;
    return _prompts.afterStep(
      checklist: checklist,
      progress: _progressRepository.current,
      settings: _voiceSettings,
      autoChecked: auto,
      ticked: ticked,
    );
  }

  /// Whether auto mode is on for this checklist, as the detail cubit sees it.
  bool get _auto =>
      !_progressRepository.isManual(_checklistName) &&
      _settings.options.autoMode;

  /// Asks "Ready for ...?" when a challenge checklist opens in auto mode.
  bool _shouldAskReady() {
    final checklist = _find();
    return _voiceSettings.challenges &&
        _auto &&
        checklist != null &&
        _prompts.startsWithChallenge(checklist, _progressRepository.current);
  }

  void _askReady() {
    final checklist = _find();
    if (checklist == null) return;
    _awaitingReady = true;
    _speak(_prompts.ready(checklist));
  }

  Future<void> _activate() async {
    emit(state.copyWith(active: true));
    final result = await _voice.startListening();
    if (isClosed) return;
    emit(state.copyWith(listening: result.isOk, micUnavailable: !result.isOk));
    if (state.paused) return;
    if (_shouldAskReady()) {
      _askReady();
    } else {
      _speak(_afterStep());
    }
  }

  void _deactivate() {
    _pending = null;
    _awaitingReady = false;
    _prompt = VoicePrompt.silent;
    unawaited(_voice.stopSpeaking());
    unawaited(_voice.stopListening());
    emit(const VoiceSessionState());
  }

  void _speak(VoicePrompt prompt) {
    _prompt = prompt;
    _pending = null;
    unawaited(_voice.say(prompt));
  }

  void _onSettings(VoiceSettings next) {
    final was = _voiceSettings;
    _voiceSettings = next;
    if (next == was) return;
    if (!next.any) {
      _deactivate();
    } else if (!was.any) {
      unawaited(_activate());
    } else if (!state.paused && !_awaitingReady) {
      _speak(_afterStep());
    }
  }

  void _onProgress(ChecklistProgress now) {
    final before = _before;
    _before = now;
    if (!state.active || state.paused) return;
    final name = _checklistName;
    Set<int> marks(ChecklistProgress p) => p.checked[name] ?? const {};
    Set<int> skips(ChecklistProgress p) => p.skipped[name] ?? const {};
    final changed =
        !_same(marks(now), marks(before)) ||
        !_same(skips(now), skips(before)) ||
        now.switches.length != before.switches.length ||
        now.switches.entries.any((e) => before.switches[e.key] != e.value);
    if (!changed) return;

    final newly = marks(now).difference(marks(before));
    final auto = [
      for (final i in newly)
        if (now.isAutoChecked(name, i)) i,
    ]..sort();
    final disagreed = [
      for (final i in newly)
        if (now.isDisagreed(name, i)) i,
    ];
    if (_awaitingReady) {
      // Waiting for "yes": only a tick or skip by hand starts the checklist;
      // auto-check ticking items does not.
      final byHand =
          newly.any((i) => !now.isAutoChecked(name, i)) ||
          !_same(skips(now), skips(before));
      if (!byHand) return;
      _awaitingReady = false;
    }
    final next = _afterStep(
      auto: auto,
      ticked: [
        for (final i in newly)
          if (!disagreed.contains(i)) i,
      ]..sort(),
    );
    final checklist = _find();
    if (disagreed.isNotEmpty && checklist != null) {
      final warning = _prompts.doubleCheck(checklist.items[disagreed.first]);
      _speak(
        VoicePrompt(
          utterances: [...warning.utterances, ...next.utterances],
          waitingFor: next.waitingFor,
          waitingForChallenge: next.waitingForChallenge,
          complete: next.complete,
        ),
      );
    } else {
      _speak(next);
    }
  }

  static bool _same(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  void _onPhrase(String heard) {
    if (!state.active) return;
    final checklist = _find();
    final waiting = _prompt.waitingFor;
    final result = checklist != null && waiting != null
        ? checklist.items[waiting].result
        : '';
    final input = _matcher.match(heard, itemResult: result);
    if (_awaitingReady && !state.paused) {
      switch (input) {
        case SpokenYes():
          _awaitingReady = false;
          _speak(_afterStep());
        case SpokenPause():
          pause();
        default:
      }
      return;
    }
    if (state.paused) {
      switch (input) {
        case SpokenResume():
          resume();
        case SpokenCloseMatch(:final phrase, :final meant)
            when meant is SpokenResume:
          _pending = meant;
          unawaited(_voice.say(_prompts.didYouMean(phrase)));
        case SpokenYes() when _pending is SpokenResume:
          _pending = null;
          resume();
        default:
      }
      return;
    }
    switch (input) {
      case SpokenCloseMatch(:final phrase, :final meant):
        _pending = meant;
        unawaited(_voice.say(_prompts.didYouMean(phrase)));
      case SpokenYes():
        final meant = _pending;
        _pending = null;
        if (meant != null) _apply(meant);
      case SpokenNo():
        if (_pending != null) _speak(_afterStep());
      default:
        _apply(input);
    }
  }

  void _apply(SpokenInput input) {
    final waiting = _prompt.waitingFor != null;
    switch (input) {
      case SpokenAnswer() when waiting:
        _pending = null;
        _checkNext();
      case SpokenSkip() when waiting:
        _pending = null;
        _skipNext();
      case SpokenPause():
        pause();
      default:
    }
  }

  @override
  Future<void> close() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    if (state.active) {
      unawaited(_voice.stopSpeaking());
      unawaited(_voice.stopListening());
    }
    return super.close();
  }
}
