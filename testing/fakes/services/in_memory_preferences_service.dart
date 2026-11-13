import 'package:flightsim_aide/data/services/local/preferences_service.dart';

/// A [PreferencesService] that keeps its values in a map.
class InMemoryPreferencesService implements PreferencesService {
  /// The stored values; tests may read and fill it directly.
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}
