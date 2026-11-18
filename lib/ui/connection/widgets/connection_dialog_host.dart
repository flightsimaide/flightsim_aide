import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:go_router/go_router.dart';

import '../../../domain/models/aircraft/aircraft_identity.dart';
import '../../../domain/models/flight_sim/discovered_sim.dart';
import '../../../domain/models/flight_sim/switch_offer.dart';
import '../../../routing/routes.dart';
import '../../core/themes/status_colors.dart';
import '../../home/cubit/home_cubit.dart';
import '../cubit/connection_cubit.dart';
import '../cubit/connection_dialog_cubit.dart';
import 'connection_messages.dart';
import 'connection_panel.dart';

/// The question asked after Continue in manual mode, and again after a new run
/// of X-Plane when the answer was No.
const notifyQuestion =
    'Do you want to continue to be notified of lost '
    'connections?';

/// Opens and closes the connection dialogs on top of whatever page is shown,
/// as [ConnectionDialogCubit] decides (task 0.14). Needs a [ConnectionCubit]
/// and a [ConnectionDialogCubit] above it, and a [Navigator] above it.
class ConnectionDialogHost extends StatefulWidget {
  /// Creates the host around [child].
  const ConnectionDialogHost({required this.child, super.key});

  /// The routed screen.
  final Widget child;

  @override
  State<ConnectionDialogHost> createState() => _ConnectionDialogHostState();
}

class _ConnectionDialogHostState extends State<ConnectionDialogHost> {
  Route<void>? _connectionRoute;
  Route<void>? _askRoute;
  Route<void>? _aircraftRoute;
  Route<void>? _switchRoute;
  String? _shownAircraft;
  String? _autoOpened;
  SwitchOffer? _shownOffer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _apply(context.read<ConnectionDialogCubit>().state),
    );
  }

  @override
  void dispose() {
    _remove(_connectionRoute);
    _remove(_askRoute);
    _remove(_aircraftRoute);
    _remove(_switchRoute);
    super.dispose();
  }

  void _remove(Route<void>? route) {
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  void _apply(ConnectionDialogState state) {
    if (!mounted) return;
    final wantConnection = state.kind == ConnectionDialogKind.connection;
    final wantAsk = state.kind == ConnectionDialogKind.askNotify;
    if (wantConnection && !(_connectionRoute?.isActive ?? false)) {
      _connectionRoute = _push(
        child: BlocBuilder<ConnectionDialogCubit, ConnectionDialogState>(
          builder: (context, state) => ConnectionPanel(
            inDialog: true,
            onContinue: state.canContinue
                ? context.read<ConnectionDialogCubit>().continueManually
                : null,
          ),
        ),
      );
    } else if (!wantConnection) {
      _remove(_connectionRoute);
      _connectionRoute = null;
    }
    final live = state.live;
    if (!(state.kind == ConnectionDialogKind.aircraftChanged &&
        state.autoOpen)) {
      _autoOpened = null;
    }
    if (state.kind == ConnectionDialogKind.aircraftChanged &&
        live != null &&
        state.autoOpen) {
      // The user chose this computer: take over its checklist, no question.
      _remove(_aircraftRoute);
      _aircraftRoute = null;
      if (_autoOpened != live.aircraftPath) {
        _autoOpened = live.aircraftPath;
        context.read<ConnectionCubit>().clearSwitchedByUser();
        _openChecklist();
      }
    } else if (state.kind == ConnectionDialogKind.aircraftChanged &&
        live != null) {
      // A different aircraft replaces the question about the previous one.
      if ((_aircraftRoute?.isActive ?? false) &&
          _shownAircraft != live.aircraftPath) {
        _remove(_aircraftRoute);
        _aircraftRoute = null;
      }
      if (!(_aircraftRoute?.isActive ?? false)) {
        _shownAircraft = live.aircraftPath;
        _aircraftRoute = _push(
          child: _AircraftChangedDialog(
            live: live,
            computer: context.read<ConnectionCubit>().state.computer,
            onOpen: _openChecklist,
            onContinue: context
                .read<ConnectionDialogCubit>()
                .continueWithCurrentChecklist,
          ),
        );
      }
    } else {
      _remove(_aircraftRoute);
      _aircraftRoute = null;
    }
    final offer = state.offer;
    if (state.kind == ConnectionDialogKind.switchComputer && offer != null) {
      if ((_switchRoute?.isActive ?? false) && _shownOffer != offer) {
        _remove(_switchRoute);
        _switchRoute = null;
      }
      if (!(_switchRoute?.isActive ?? false)) {
        _shownOffer = offer;
        _switchRoute = _push(child: _SwitchDialog(offer: offer));
      }
    } else {
      _remove(_switchRoute);
      _switchRoute = null;
    }
    if (wantAsk && !(_askRoute?.isActive ?? false)) {
      _askRoute = _push(child: const _NotifyDialog());
    } else if (!wantAsk) {
      _remove(_askRoute);
      _askRoute = null;
    }
  }

  /// Goes home and loads the checklist of the aircraft X-Plane has now.
  void _openChecklist() {
    final home = context.read<HomeCubit>();
    context.go(Routes.home);
    home.load();
  }

  /// Pushes a dialog that cannot be dismissed. The providers are passed on
  /// because the dialog's route sits above them.
  Route<void> _push({required Widget child}) {
    final connection = context.read<ConnectionCubit>();
    final dialog = context.read<ConnectionDialogCubit>();
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider<ConnectionCubit>.value(value: connection),
          BlocProvider<ConnectionDialogCubit>.value(value: dialog),
        ],
        child: PopScope(canPop: false, child: child),
      ),
    );
    Navigator.of(context).push(route);
    return route;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ConnectionDialogCubit, ConnectionDialogState>(
      listener: (_, state) => _apply(state),
      child: widget.child,
    );
  }
}

/// "You were connected to X-Plane on A. Switch to X-Plane on B?" (task 0.16).
class _SwitchDialog extends StatelessWidget {
  const _SwitchDialog({required this.offer});

  final SwitchOffer offer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caution =
        theme.extension<StatusColors>()?.caution ?? theme.colorScheme.primary;
    final cubit = context.read<ConnectionCubit>();
    final from = offer.from;
    final question = from == null
        ? '${computerLabel(offer.to)} answered. Switch to it?'
        : 'You were connected to ${computerLabel(from)}. '
              'Do you want to switch to ${computerLabel(offer.to)}?';
    return AlertDialog(
      icon: Icon(Icons.warning, color: caution),
      title: Text(
        'Switch computer?',
        style: theme.textTheme.titleLarge?.copyWith(color: caution),
      ),
      content: Text(question, key: const Key('switch-question')),
      actions: [
        TextButton(
          key: const Key('switch-no'),
          onPressed: () => cubit.answerSwitch(accept: false),
          child: const Text('No'),
        ),
        TextButton(
          key: const Key('switch-yes'),
          onPressed: () => cubit.answerSwitch(accept: true),
          child: const Text('Yes'),
        ),
      ],
    );
  }
}

class _NotifyDialog extends StatelessWidget {
  const _NotifyDialog();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ConnectionDialogCubit>();
    return AlertDialog(
      content: const Text(notifyQuestion),
      actions: [
        TextButton(
          onPressed: () => cubit.answerNotify(notify: false),
          child: const Text('No'),
        ),
        TextButton(
          onPressed: () => cubit.answerNotify(notify: true),
          child: const Text('Yes'),
        ),
      ],
    );
  }
}

/// Asks what to do when X-Plane loads a different aircraft than the checklist
/// on screen: open the new aircraft's checklist (when it has one), or continue
/// with the current one.
class _AircraftChangedDialog extends StatelessWidget {
  const _AircraftChangedDialog({
    required this.live,
    required this.computer,
    required this.onOpen,
    required this.onContinue,
  });

  final AircraftIdentity live;
  final DiscoveredSim? computer;
  final VoidCallback onOpen;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caution =
        theme.extension<StatusColors>()?.caution ?? theme.colorScheme.primary;
    final line = aircraftLine(live, computer);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ExcludeSemantics(
                        child: Icon(Icons.warning, size: 24, color: caution),
                      ),
                      const SizedBox(width: 16),
                      Flexible(
                        child: Text(
                          aircraftChangedHeadline,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: caution,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    line,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (live.checklistPath != null)
                    _ChoiceTile(
                      key: const Key('aircraft-open'),
                      title: 'Open checklist for "$line"',
                      onTap: onOpen,
                    )
                  else
                    _ChoiceTile(
                      key: const Key('aircraft-no-checklist'),
                      title: '$line has no checklist',
                      info: true,
                    ),
                  _ChoiceTile(
                    key: const Key('aircraft-continue'),
                    title: 'Continue with current checklist',
                    onTap: onContinue,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A choice in a dialog: a bordered rectangle with an empty circle in front,
/// like the entries that list the computers. Disabled when [onTap] is null,
/// unless it is an [info] box.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    this.onTap,
    this.info = false,
    super.key,
  });

  /// Looks like a choice but only states a fact: no circle, no action.
  final bool info;

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: onTap == null && !info
                ? scheme.outline.withValues(alpha: 0.4)
                : scheme.outline,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          enabled: onTap != null || info,
          minVerticalPadding: 12,
          leading: info ? null : const Icon(Icons.radio_button_unchecked),
          title: Text(title),
          onTap: onTap,
        ),
      ),
    );
  }
}
