import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:go_router/go_router.dart';

import '../../../data/repositories/checklist/checklist_repository.dart';
import '../../../routing/routes.dart';
import '../../connection/cubit/connection_cubit.dart';
import '../../connection/cubit/connection_dialog_cubit.dart';
import '../../connection/widgets/connection_panel.dart';
import '../../connection/widgets/connection_status_indicator.dart';
import '../../core/app_info.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/loading_indicator.dart';
import '../cubit/home_cubit.dart';
import '../cubit/home_state.dart';

/// Landing screen: shows where the connection stands, then moves on to the
/// list. The [HomeCubit] comes from the app shell.
class HomeScreen extends StatelessWidget {
  /// Creates the home screen.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const _HomeView();
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    return BlocListener<HomeCubit, HomeState>(
      listenWhen: (previous, current) =>
          (current is HomeLoaded && current.openList) ||
          current is HomePromptRestore ||
          current is HomeReconnectPrompt,
      listener: (context, state) {
        switch (state) {
          case HomePromptRestore() || HomeReconnectPrompt():
            _askRestore(context);
          case HomeLoaded(:final document, :final openLast):
            // Only after "Use saved progress": go to the list and on to the
            // checklist that was open. Every other start stays on Home.
            context.push(Routes.list);
            if (openLast != null &&
                document.checklists.any((c) => c.name == openLast)) {
              context.push(Routes.detailPath(openLast));
            }
          default:
            break;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(appName),
          actions: [const ConnectionStatusIndicator()],
        ),
        body: BlocBuilder<HomeCubit, HomeState>(
          builder: (context, state) {
            final loading = state is HomeLoading;
            final network = _hasConnection(context);
            return Column(
              children: [
                if (state is HomeFailure)
                  ErrorBanner(
                    message: state.message,
                    onDismiss: context.read<HomeCubit>().dismissError,
                  ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (network) const _HomeConnection(),
                          const _FeatureCards(),
                          if (loading) ...[
                            const SizedBox(height: 24),
                            const LoadingIndicator(),
                          ],
                          const _Disclaimer(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The flight-simulation-only notice under the cards. It scrolls with them, so
/// it never covers a card on a small screen.
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Text(
        simOnlyDisclaimer,
        key: const Key('home-disclaimer'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// One card per main feature: what it is, a line of information, and a tap
/// to open it. Procedures has no page yet and is shown disabled.
class _FeatureCards extends StatelessWidget {
  const _FeatureCards();

  @override
  Widget build(BuildContext context) {
    // Rebuilt on every home state, so the Checklists card follows the load.
    return BlocBuilder<HomeCubit, HomeState>(builder: _cards);
  }

  Widget _cards(BuildContext context, HomeState state) {
    final checklists = context.read<ChecklistRepository>().current?.checklists;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          const _FeatureCard(
            key: Key('home-card-procedures'),
            icon: Icons.menu_book_outlined,
            title: 'Procedures',
            info: 'Coming soon',
          ),
          _FeatureCard(
            key: const Key('home-card-checklists'),
            icon: Icons.checklist,
            title: 'Checklists',
            info: checklists == null
                ? 'No checklist yet. Connect to X-Plane to load the '
                      "aircraft's checklists."
                : '${checklists.length} '
                      '${checklists.length == 1 ? 'checklist' : 'checklists'} '
                      'for this aircraft',
            onTap: checklists == null ? null : () => context.push(Routes.list),
          ),
          _FeatureCard(
            key: const Key('home-card-settings'),
            icon: Icons.settings_outlined,
            title: 'Settings',
            info: 'Appearance, light or dark, and colours',
            onTap: () => context.push(Routes.settings),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.info,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String info;

  /// Null when the feature cannot be opened (greyed out).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final colour = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: 0.5);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 28, color: colour),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colour,
                        ),
                      ),
                      Text(
                        info,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: enabled
                              ? theme.colorScheme.onSurfaceVariant
                              : colour,
                        ),
                      ),
                    ],
                  ),
                ),
                if (enabled) Icon(Icons.chevron_right, color: colour),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The connection panel on the home page. While the connection dialog is
/// armed the dialog covers every lost connection, so only the connected panels
/// show here; once disarmed (Continue in manual mode) the page shows the
/// current state with the switch that turns the notification back on.
class _HomeConnection extends StatelessWidget {
  const _HomeConnection();

  @override
  Widget build(BuildContext context) {
    final ConnectionDialogCubit dialog;
    try {
      dialog = context.read<ConnectionDialogCubit>();
    } on ProviderNotFoundException {
      return const ConnectionPanel(connectedOnly: true);
    }
    return BlocBuilder<ConnectionDialogCubit, ConnectionDialogState>(
      builder: (context, state) {
        final disarmed = state.kind == ConnectionDialogKind.none;
        return ConnectionPanel(
          connectedOnly: !disarmed,
          notifyOn: dialog.armed,
          onNotifyChanged: (on) {
            if (on) dialog.enableNotification();
          },
        );
      },
    );
  }
}

bool _hasConnection(BuildContext context) {
  try {
    context.read<ConnectionCubit>();
    return true;
  } on ProviderNotFoundException {
    return false;
  }
}

/// Asks whether to use the progress saved for this aircraft. The dialog cannot
/// be dismissed without an answer; the answer goes to the cubit, whose next
/// state opens the list as for any load.
Future<void> _askRestore(BuildContext context) async {
  final cubit = context.read<HomeCubit>();
  final useSaved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Saved progress found'),
        content: const Text(
          'This aircraft has progress saved from earlier. Use it, or start '
          'with everything unchecked?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Reset'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Use saved progress'),
          ),
        ],
      ),
    ),
  );
  if (useSaved == null) return;
  await cubit.answerPrompt(useSaved: useSaved);
}
