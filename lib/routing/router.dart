import 'package:go_router/go_router.dart';

import '../ui/checklist_detail/widgets/checklist_detail_screen.dart';
import '../ui/checklist_list/widgets/checklist_list_screen.dart';
import '../ui/home/widgets/home_screen.dart';
import '../ui/settings/widgets/appearance_screen.dart';
import '../ui/settings/widgets/settings_screen.dart';
import 'app_shell.dart';
import 'routes.dart';

/// Builds the app's router, starting at [initialLocation].
///
/// The screens are built from the repositories provided above the router.
GoRouter createRouter({String initialLocation = Routes.home}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: Routes.home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: Routes.list,
            builder: (context, state) => const ChecklistListScreen(),
          ),
          GoRoute(
            path: Routes.settings,
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: Routes.appearance,
            builder: (context, state) => const AppearanceScreen(),
          ),
          GoRoute(
            path: Routes.detail,
            builder: (context, state) => ChecklistDetailScreen(
              checklistName: state.pathParameters['name']!,
            ),
          ),
        ],
      ),
    ],
  );
}
