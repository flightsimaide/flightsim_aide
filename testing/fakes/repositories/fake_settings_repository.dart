import 'package:flightsim_aide/data/repositories/settings/settings_repository_impl.dart';

import '../services/in_memory_preferences_service.dart';

/// The real settings logic over an in-memory store.
class FakeSettingsRepository extends SettingsRepositoryImpl {
  /// Creates the fake with its own empty store.
  FakeSettingsRepository() : super(preferences: InMemoryPreferencesService());
}
