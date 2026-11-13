import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/models/flight_sim/simulator.dart';
import '../../core/themes/status_colors.dart';
import '../cubit/connection_cubit.dart';
import '../cubit/connection_state.dart';

/// What the app bar shows about the connection (task 0.17).
enum IndicatorKind {
  /// No network: red.
  noNetwork('No network'),

  /// Searching, waiting for the plugin or retrying: amber.
  connecting('Connecting'),

  /// Connected to a plugin: green.
  connected('Connected'),

  /// Cannot connect and retrying will not help by itself (Local Network off,
  /// plugin version): red.
  notConnected('Not connected');

  const IndicatorKind(this.label);

  /// The word shown.
  final String label;
}

/// Maps the connection state to what the indicator shows.
IndicatorKind indicatorFor(ConnectionViewState state) => switch (state) {
  LinkNoNetwork() => IndicatorKind.noNetwork,
  LinkSearching() ||
  LinkConnecting() ||
  LinkSimUnreachable() => IndicatorKind.connecting,
  LinkConnected() ||
  LinkNoChecklist() ||
  LinkAircraftChanged() => IndicatorKind.connected,
  LinkLocalNetworkDenied() ||
  LinkVersionMismatch() => IndicatorKind.notConnected,
};

/// A small status for the right of every app bar: the computer and simulator
/// on the line above, then an icon in the status colour and one word. It only
/// shows; tapping it does nothing. Without a connection cubit (the file and
/// sample sources) it is empty.
class ConnectionStatusIndicator extends StatelessWidget {
  /// Creates the indicator.
  const ConnectionStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final ConnectionCubit cubit;
    try {
      cubit = context.read<ConnectionCubit>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    return BlocBuilder<ConnectionCubit, ConnectionViewState>(
      bloc: cubit,
      builder: (context, state) {
        final kind = indicatorFor(state);
        final theme = Theme.of(context);
        final colours = theme.extension<StatusColors>();
        final (icon, colour) = switch (kind) {
          IndicatorKind.connected => (
            Icons.check_circle,
            colours?.success ?? theme.colorScheme.primary,
          ),
          IndicatorKind.connecting => (
            Icons.warning,
            colours?.caution ?? theme.colorScheme.primary,
          ),
          IndicatorKind.noNetwork || IndicatorKind.notConnected => (
            Icons.error,
            colours?.error ?? theme.colorScheme.error,
          ),
        };
        final computer =
            kind == IndicatorKind.connected || kind == IndicatorKind.connecting
            ? (state.computer ?? cubit.target)
            : null;
        final where = computer == null
            ? null
            : '${computer.name ?? computer.host} · '
                  '${(computer.simulator ?? Simulator.xplane).displayName}';
        return Padding(
          key: const Key('connection-indicator'),
          padding: const EdgeInsets.only(right: 16, left: 8),
          child: Semantics(
            container: true,
            label: where == null ? kind.label : '$where, ${kind.label}',
            excludeSemantics: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (where != null)
                  Text(
                    where,
                    key: const Key('connection-indicator-where'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: colour),
                    const SizedBox(width: 4),
                    Text(
                      kind.label,
                      key: const Key('connection-indicator-status'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colour,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
