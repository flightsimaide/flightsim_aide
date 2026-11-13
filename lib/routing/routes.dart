/// Route paths for the app's go_router table.
abstract final class Routes {
  /// Home screen.
  static const home = '/';

  /// Checklist list screen.
  static const list = '/checklists';

  /// Settings screen.
  static const settings = '/settings';

  /// Appearance screen, under Settings.
  static const appearance = '/settings/appearance';

  /// Checklist detail route pattern; the `:name` segment is URL-encoded.
  static const detail = '/checklists/:name';

  /// Concrete detail location for the checklist called [name].
  static String detailPath(String name) =>
      '/checklists/${Uri.encodeComponent(name)}';
}
