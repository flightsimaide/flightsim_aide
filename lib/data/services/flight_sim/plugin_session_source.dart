import '../../../utils/result.dart';
import 'model/plugin_session.dart';

/// The single source of "which aircraft is loaded, and where is the plugin".
/// Everything that needs the aircraft listens here instead of fetching it.
abstract class PluginSessionSource {
  /// The current session, or null while the plugin is not ready.
  PluginSession? get current;

  /// A new session when the aircraft changes; null when the plugin goes away.
  /// A failed fetch arrives on the error channel; the last session stays.
  Stream<PluginSession?> get changes;

  /// Fetches the aircraft again now, whether or not the generation changed.
  Future<Result<PluginSession>> reload();
}
