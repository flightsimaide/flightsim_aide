import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'data/repositories/settings/settings_repository.dart';
import 'routing/router.dart';
import 'ui/core/app_info.dart';
import 'ui/core/themes/app_theme.dart';
import 'ui/settings/cubit/theme_cubit.dart';
import 'ui/settings/cubit/theme_state.dart';

/// Root widget: provides the repositories and the routed [MaterialApp].
class App extends StatefulWidget {
  /// Creates the app with the given repository [providers].
  ///
  /// A [router] may be injected (tests); otherwise the default is created.
  const App({required this.providers, this.router, super.key});

  /// Repository providers wired by the composition root in `config/`.
  final List<RepositoryProvider<dynamic>> providers;

  /// Optional router override.
  final GoRouter? router;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final GoRouter _router = widget.router ?? createRouter();

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: widget.providers,
      child: Builder(
        builder: (context) {
          SettingsRepository? settings;
          try {
            settings = context.read<SettingsRepository>();
          } on ProviderNotFoundException {
            // The file and sample sources have no settings: default themes.
          }
          if (settings == null) return _app(null);
          return BlocProvider<ThemeCubit>(
            create: (_) => ThemeCubit(settings: settings!)..load(),
            child: BlocBuilder<ThemeCubit, ThemeState>(
              builder: (context, theme) => _app(theme),
            ),
          );
        },
      ),
    );
  }

  Widget _app(ThemeState? theme) => MaterialApp.router(
    title: appName,
    // The debug ribbon would cover the app bar's trailing actions.
    debugShowCheckedModeBanner: false,
    routerConfig: _router,
    theme: theme?.light ?? AppTheme.light,
    darkTheme: theme?.dark ?? AppTheme.dark,
    themeMode: theme?.themeMode ?? ThemeMode.system,
  );
}
