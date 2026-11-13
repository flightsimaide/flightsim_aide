import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/checklist/checklist_progress_repository.dart';
import '../data/repositories/checklist/checklist_repository.dart';
import '../data/repositories/flight_sim/flight_sim_repository.dart';
import '../data/repositories/settings/settings_repository.dart';
import '../ui/connection/cubit/connection_cubit.dart';
import '../ui/connection/cubit/connection_dialog_cubit.dart';
import '../ui/connection/widgets/connection_dialog_host.dart';
import '../ui/connection/widgets/save_manual_ip_prompt.dart';
import '../ui/core/widgets/app_navigation_bar.dart';
import '../ui/home/cubit/home_cubit.dart';
import '../ui/home/cubit/home_state.dart';
import '../utils/app_exception.dart';
import 'routes.dart';

T? _optional<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on ProviderNotFoundException {
    return null;
  }
}

/// Wraps every routed screen: creates the app-wide cubits once and shows the
/// notice banner above the screen. Without a [FlightSimRepository] (the file
/// and sample sources) there is no connection cubit and no banner.
class AppShell extends StatelessWidget {
  /// Creates the shell around the routed [child], which is at [location].
  const AppShell({required this.child, this.location = Routes.home, super.key});

  /// The current screen.
  final Widget child;

  /// The path of the current screen, to mark its entry in the bottom bar.
  final String location;

  @override
  Widget build(BuildContext context) {
    final sim = _optional<FlightSimRepository>(context);
    final settings = _optional<SettingsRepository>(context);
    final connected = sim != null && settings != null;
    return MultiBlocProvider(
      providers: [
        BlocProvider<HomeCubit>(
          create: (context) => HomeCubit(
            checklistRepository: context.read<ChecklistRepository>(),
            progressRepository: context.read<ChecklistProgressRepository>(),
            flightSim: sim,
          ),
        ),
        if (connected)
          BlocProvider<ConnectionCubit>(
            create: (_) => ConnectionCubit(flightSim: sim, settings: settings),
          ),
        if (connected)
          BlocProvider<ConnectionDialogCubit>(
            lazy: false,
            create: (context) => ConnectionDialogCubit(
              connection: context.read<ConnectionCubit>(),
              runId: () => sim.runId,
            ),
          ),
      ],
      child: _ShellEffects(
        child: _WithNavigationBar(
          location: location,
          child: connected
              ? BlocListener<HomeCubit, HomeState>(
                  listenWhen: (_, current) =>
                      current is HomeLoaded || current is HomePromptRestore,
                  listener: (context, state) {
                    context.read<ConnectionCubit>().setLoadedAircraft(
                      switch (state) {
                        HomeLoaded(:final aircraft) => aircraft,
                        HomePromptRestore(:final aircraft) => aircraft,
                        _ => null,
                      },
                    );
                  },
                  child: _ChecklistWatcher(
                    child: ConnectionDialogHost(
                      child: SaveManualIpPrompt(child: child),
                    ),
                  ),
                )
              : child,
        ),
      ),
    );
  }
}

/// Puts the bottom navigation bar under every routed page.
class _WithNavigationBar extends StatelessWidget {
  const _WithNavigationBar({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onList = location.startsWith(Routes.list);
    final onSettings = location.startsWith(Routes.settings);
    return Scaffold(
      body: child,
      bottomNavigationBar: BlocBuilder<HomeCubit, HomeState>(
        builder: (context, _) => AppNavigationBar(
          selectedIndex: onSettings ? 3 : (onList ? 2 : 0),
          checklistsEnabled:
              context.read<ChecklistRepository>().current != null,
          onHome: () => context.go(Routes.home),
          onSettings: () {
            if (!onSettings) {
              context.push(Routes.settings);
            } else if (location != Routes.settings) {
              // On Appearance: back to the Settings list.
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(Routes.settings);
              }
            }
          },
          onChecklists: () {
            if (!onList) {
              context.push(Routes.list);
            } else if (location != Routes.list) {
              // On a checklist's page: back to the list.
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(Routes.list);
              }
            }
          },
        ),
      ),
    );
  }
}

/// Tells the [ConnectionDialogCubit] whether a checklist is loaded and whether
/// the restore question is on screen.
class _ChecklistWatcher extends StatelessWidget {
  const _ChecklistWatcher({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    void tell(HomeState state) =>
        context.read<ConnectionDialogCubit>().setChecklist(
          hasChecklist:
              state is HomeLoaded ||
              state is HomePromptRestore ||
              state is HomeReconnectPrompt,
          prompting: state is HomePromptRestore || state is HomeReconnectPrompt,
        );
    return BlocListener<HomeCubit, HomeState>(
      listener: (context, state) => tell(state),
      child: child,
    );
  }
}

/// App-wide reactions: the background/foreground cycle and failed saves.
class _ShellEffects extends StatefulWidget {
  const _ShellEffects({required this.child});

  final Widget child;

  @override
  State<_ShellEffects> createState() => _ShellEffectsState();
}

class _ShellEffectsState extends State<_ShellEffects>
    with WidgetsBindingObserver {
  StreamSubscription<AppException>? _errors;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _errors ??= context
        .read<ChecklistProgressRepository>()
        .persistenceErrors
        .listen(_onSaveError);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _errors?.cancel();
    super.dispose();
  }

  void _onSaveError(AppException error) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Could not save your progress on this device.'),
        ),
      );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final home = context.read<HomeCubit>();
    final connection = _connection();
    switch (state) {
      case AppLifecycleState.paused:
        home.appPaused();
        connection?.pauseLink();
      case AppLifecycleState.resumed:
        connection?.resumeLink();
        home.appResumed();
      default:
        break;
    }
  }

  ConnectionCubit? _connection() {
    try {
      return context.read<ConnectionCubit>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
