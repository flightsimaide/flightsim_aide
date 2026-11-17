import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/checklist/checklist_progress_repository.dart';
import '../../../data/repositories/checklist/checklist_repository.dart';
import '../../../data/repositories/settings/settings_repository.dart';
import '../../../data/repositories/voice/voice_repository.dart';
import '../cubit/checklist_detail_cubit.dart';
import '../cubit/voice_session_cubit.dart';
import '../cubit/voice_session_state.dart';

/// Finds the Pause button, for tests.
const voicePauseButtonKey = ValueKey<String>('voice-pause-button');

/// Finds the flashing PAUSED chip, for tests.
const voicePausedChipKey = ValueKey<String>('voice-paused-chip');

/// Finds the icon that says the microphone is not available, for tests.
const voiceMicOffKey = ValueKey<String>('voice-mic-off');

T? _optional<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}

/// Gives [child] a [VoiceSessionCubit] for [checklistName] when the app has a
/// voice (a [VoiceRepository] and settings); otherwise it is just [child].
/// A [ChecklistDetailCubit] must be above it: a spoken answer ticks or skips
/// through it, the same as a tap.
class VoiceScope extends StatelessWidget {
  /// Creates the scope.
  const VoiceScope({
    required this.checklistName,
    required this.child,
    super.key,
  });

  /// The checklist the voice follows.
  final String checklistName;

  /// The screen.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final voice = _optional<VoiceRepository>(context);
    final settings = _optional<SettingsRepository>(context);
    if (voice == null || settings == null) return child;
    return BlocProvider<VoiceSessionCubit>(
      create: (context) {
        final detail = context.read<ChecklistDetailCubit>();
        return VoiceSessionCubit(
          checklistName: checklistName,
          checklistRepository: context.read<ChecklistRepository>(),
          progressRepository: context.read<ChecklistProgressRepository>(),
          settings: settings,
          voice: voice,
          checkNext: detail.checkNext,
          skipNext: detail.skipNext,
        )..load();
      },
      child: child,
    );
  }
}

/// The Pause button and the flashing PAUSED chip, for the app bar. Shows
/// nothing while the voice is off or when the screen has no voice.
class VoiceControls extends StatelessWidget {
  /// Creates the controls.
  const VoiceControls({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = _optional<VoiceSessionCubit>(context);
    if (cubit == null) return const SizedBox.shrink();
    return BlocBuilder<VoiceSessionCubit, VoiceSessionState>(
      bloc: cubit,
      builder: (context, state) {
        if (!state.active) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.micUnavailable)
              const Tooltip(
                message: 'Speech recognition is not available',
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.mic_off, key: voiceMicOffKey),
                ),
              ),
            if (state.paused) const _PausedChip(),
            IconButton(
              key: voicePauseButtonKey,
              tooltip: state.paused ? 'Resume voice' : 'Pause voice',
              icon: Icon(state.paused ? Icons.play_arrow : Icons.pause),
              onPressed: state.paused ? cubit.resume : cubit.pause,
            ),
          ],
        );
      },
    );
  }
}

/// PAUSED with an icon, flashing. The icon and the word carry the meaning, not
/// the colour; the flash stops when the system asks for no animation.
class _PausedChip extends StatefulWidget {
  const _PausedChip();

  @override
  State<_PausedChip> createState() => _PausedChipState();
}

class _PausedChipState extends State<_PausedChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _flash.stop();
      _flash.value = 1;
    } else if (!_flash.isAnimating) {
      _flash.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_flash),
      child: Container(
        key: voicePausedChipKey,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pause_circle,
              size: 18,
              color: scheme.onTertiaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              'PAUSED',
              style: TextStyle(
                color: scheme.onTertiaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
