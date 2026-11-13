import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/models/flight_sim/discovered_sim.dart';
import '../../core/themes/status_colors.dart';
import '../cubit/connection_cubit.dart';
import '../cubit/connection_state.dart';
import 'cancel_connecting_flow.dart';
import 'connection_messages.dart';
import 'manual_ip_dialog.dart';
import 'sim_chooser.dart';
import 'spinning_hourglass.dart';

/// Icon for [state]; the text always says the same thing, so colour and
/// icon are never the only carrier of meaning.
IconData connectionIcon(ConnectionViewState state) => switch (state) {
  LinkSearching() || LinkConnecting() => Icons.hourglass_top,
  LinkConnected() => Icons.check_circle,
  LinkNoChecklist() => Icons.warning,
  LinkAircraftChanged() => Icons.warning,
  LinkNoNetwork() => Icons.error,
  LinkLocalNetworkDenied() => Icons.lan,
  LinkSimUnreachable() => Icons.cloud_off,
  LinkVersionMismatch() => Icons.system_update,
};

/// The label of the switch that turns the lost-connection dialog back on.
const notifyOutageLabel = 'Enable notification of network outage';

bool _isConnected(ConnectionViewState state) =>
    state is LinkConnected ||
    state is LinkNoChecklist ||
    state is LinkAircraftChanged;

/// Shows where the connection stands, with the actions that fit the state,
/// as a box like a dialog. Needs a [ConnectionCubit] above it.
class ConnectionPanel extends StatefulWidget {
  /// Creates the panel. With [onContinue] it offers Continue in manual mode;
  /// with [inDialog] it is the content of a dialog instead of a card.
  const ConnectionPanel({
    this.onContinue,
    this.inDialog = false,
    this.connectedOnly = false,
    this.notifyOn,
    this.onNotifyChanged,
    super.key,
  });

  /// Where the dialog is disarmed (the home page): the position of the
  /// "Enable notification of network outage" switch, shown instead of
  /// Continue in manual mode while the connection is down.
  final bool? notifyOn;

  /// Called when the notification switch is turned.
  final ValueChanged<bool>? onNotifyChanged;

  /// Draws nothing unless connected: the connection dialog covers the other
  /// states (task 0.14).
  final bool connectedOnly;

  /// Called by Continue in manual mode; null hides the button.
  final VoidCallback? onContinue;

  /// Whether the panel is laid out as a dialog.
  final bool inDialog;

  @override
  State<ConnectionPanel> createState() => _ConnectionPanelState();
}

class _ConnectionPanelState extends State<ConnectionPanel> {
  /// Whether the hidden Details section is open.
  bool _details = false;

  /// Reloads, then tells the user for a few seconds that it is done.
  Future<void> _reload(ConnectionCubit cubit) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final worked = await cubit.reload();
    if (!worked || messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Checklist reloaded'),
          duration: Duration(seconds: 3),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionCubit, ConnectionViewState>(
      builder: (context, state) {
        if (widget.connectedOnly &&
            state is! LinkConnected &&
            state is! LinkNoChecklist) {
          return const SizedBox.shrink();
        }
        final message = messageFor(state);
        final cubit = context.read<ConnectionCubit>();
        final theme = Theme.of(context);
        // The colour of the text of an outlined button.
        final iconColor = theme.colorScheme.primary;
        // Status colours: green for good, yellow for caution.
        final status = theme.extension<StatusColors>();
        final stateIconColor = switch (message.tone) {
          MessageTone.good => status?.success ?? iconColor,
          MessageTone.caution => status?.caution ?? iconColor,
          MessageTone.warning => status?.error ?? theme.colorScheme.error,
          MessageTone.neutral => iconColor,
        };
        final headlineColor =
            message.tone == MessageTone.caution ||
                message.tone == MessageTone.warning
            ? stateIconColor
            : null;
        final sims = state is LinkSearching
            ? state.sims
            : const <DiscoveredSim>[];
        final content = Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            container: true,
            liveRegion: true,
            label: [
              message.headline,
              if (message.detail.isNotEmpty) message.detail,
            ].join(' '),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (message.showIcon) ...[
                      ExcludeSemantics(
                        child: message.spinning
                            ? SpinningHourglass(size: 24, color: iconColor)
                            : Icon(
                                connectionIcon(state),
                                size: 24,
                                color: stateIconColor,
                              ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    Flexible(
                      child: Text(
                        message.headline,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: headlineColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (message.warning != null) ...[
                  const SizedBox(height: 24),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        message.warning!,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onError,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
                if (message.note != null) ...[
                  const SizedBox(height: 24),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.error),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        message.note!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
                if (message.detail.isNotEmpty) ...[
                  SizedBox(height: message.detailGap),
                  Text(
                    message.detail,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
                if (state.inputError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.inputError!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (sims.length > 1) ...[
                  const SizedBox(height: 16),
                  SimChooser(sims: List.of(sims)),
                ],
                if ((_isConnected(state) || state is LinkSimUnreachable) &&
                    !widget.inDialog &&
                    state.others.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SimChooser(
                    key: const Key('other-computers'),
                    sims: state.others,
                    from: state.computer,
                    lost: state is LinkSimUnreachable,
                  ),
                ],
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (message.offersCancel)
                      OutlinedButton(
                        onPressed: () => state is LinkSimUnreachable
                            ? cubit.dropManualIp()
                            : showCancelConnectingFlow(context),
                        child: Text(message.cancelLabel),
                      ),
                    if (message.offersReload)
                      OutlinedButton(
                        onPressed: () => unawaited(_reload(cubit)),
                        child: const Text('Reload'),
                      ),
                    if (message.offersRetry)
                      FilledButton(
                        onPressed: cubit.retry,
                        child: const Text('Retry'),
                      ),
                    if (message.offersManualIp)
                      OutlinedButton(
                        onPressed: () => showManualIpDialog(context),
                        child: const Text('Enter IP address'),
                      ),
                    if (message.offersDetails)
                      OutlinedButton(
                        onPressed: () => setState(() => _details = !_details),
                        child: const Text('Details'),
                      ),
                    if (widget.onContinue != null)
                      OutlinedButton(
                        onPressed: widget.onContinue,
                        child: const Text('Continue in manual mode'),
                      ),
                  ],
                ),
                if (widget.onNotifyChanged != null &&
                    widget.notifyOn != null &&
                    !_isConnected(state)) ...[
                  const SizedBox(height: 16),
                  SwitchListTile(
                    key: const Key('notify-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(notifyOutageLabel),
                    value: widget.notifyOn!,
                    onChanged: widget.onNotifyChanged,
                  ),
                ],
                if (_details && message.offersDetails) ...[
                  const SizedBox(height: 24),
                  _DetailsBox(color: theme.colorScheme.primary),
                ],
              ],
            ),
          ),
        );
        if (widget.inDialog) {
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(child: content),
            ),
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(margin: const EdgeInsets.all(16), child: content),
          ),
        );
      },
    );
  }
}

/// The hidden Details section: a box whose outline breaks for its title.
class _DetailsBox extends StatelessWidget {
  const _DetailsBox({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color),
    );
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Details',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: TextStyle(color: color),
        floatingLabelStyle: TextStyle(color: color),
        border: border,
        enabledBorder: border,
        contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      ),
      child: Text(
        noActivityDetails,
        key: const Key('connection-details'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
