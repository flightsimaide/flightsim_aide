import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/routes.dart';
import '../../connection/widgets/connection_status_indicator.dart';

/// The Settings page: a list of option groups. Appearance is the first.
class SettingsScreen extends StatelessWidget {
  /// Creates the page.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [const ConnectionStatusIndicator()],
      ),
      body: ListView(
        children: [
          ListTile(
            key: const Key('settings-appearance'),
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Appearance'),
            subtitle: const Text('Dark, light or system; colours'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.appearance),
          ),
          ListTile(
            key: const Key('settings-voice'),
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Voice'),
            subtitle: const Text('Read items aloud and listen for answers'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.voice),
          ),
        ],
      ),
    );
  }
}
