import 'package:flightsim_aide/data/services/local/checklist_cache_service.dart';
import 'package:flightsim_aide/data/services/local/model/cached_checklist.dart';
import 'package:flightsim_aide/utils/result.dart';

/// A [ChecklistCacheService] that keeps entries in a map.
class InMemoryChecklistCacheService implements ChecklistCacheService {
  /// The stored entries by aircraft path; tests may fill it directly.
  final Map<String, CachedChecklist> entries = {};

  @override
  Future<CachedChecklist?> read(String aircraftPath) async =>
      entries[aircraftPath];

  @override
  Future<Result<void>> write(String aircraftPath, CachedChecklist entry) async {
    entries[aircraftPath] = entry;
    return const Ok(null);
  }

  @override
  Future<void> delete(String aircraftPath) async =>
      entries.remove(aircraftPath);
}
