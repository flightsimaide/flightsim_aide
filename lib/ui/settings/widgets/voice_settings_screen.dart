import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/settings/settings_repository.dart';
import '../../../domain/models/voice/voice_settings.dart';
import '../../connection/widgets/connection_status_indicator.dart';
import '../cubit/voice_settings_cubit.dart';

/// Voice: one switch for flow rows and one for challenge rows (D-84). Both are
/// off by default.
class VoiceSettingsScreen extends StatelessWidget {
  /// Creates the page.
  const VoiceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          VoiceSettingsCubit(settings: context.read<SettingsRepository>()),
      child: const _VoiceSettingsView(),
    );
  }
}

class _VoiceSettingsView extends StatelessWidget {
  const _VoiceSettingsView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<VoiceSettingsCubit>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice'),
        actions: [const ConnectionStatusIndicator()],
      ),
      body: BlocBuilder<VoiceSettingsCubit, VoiceSettings>(
        builder: (context, settings) => ListView(
          children: [
            SwitchListTile(
              key: const Key('voice-flows'),
              title: const Text('Voice for flows'),
              subtitle: const Text(
                'Reads the next item and waits for you to do it',
              ),
              value: settings.flows,
              onChanged: cubit.setFlows,
            ),
            SwitchListTile(
              key: const Key('voice-challenges'),
              title: const Text('Voice for challenges'),
              subtitle: const Text(
                'Reads the items between sw_challenge lines and listens for '
                'your answer',
              ),
              value: settings.challenges,
              onChanged: cubit.setChallenges,
            ),
          ],
        ),
      ),
    );
  }
}
