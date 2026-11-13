import 'package:shared_preferences/shared_preferences.dart';

/// Small key-value storage for settings. Strings only: a setting that needs
/// more structure belongs in its own service.
abstract class PreferencesService {
  /// The value stored under [key], or null.
  Future<String?> getString(String key);

  /// Stores [value] under [key].
  Future<void> setString(String key, String value);

  /// Removes [key]; a missing key is fine.
  Future<void> remove(String key);
}

/// [PreferencesService] over `shared_preferences`.
class SharedPreferencesService implements PreferencesService {
  /// Creates the service.
  SharedPreferencesService();

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> getString(String key) async => (await _prefs).getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await (await _prefs).setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await (await _prefs).remove(key);
  }
}
