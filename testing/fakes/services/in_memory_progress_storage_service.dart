import 'package:flightsim_aide/data/services/local/model/stored_progress.dart';
import 'package:flightsim_aide/data/services/local/progress_storage_service.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flightsim_aide/utils/result.dart';

/// A [ProgressStorageService] that keeps records in a map and records calls.
class InMemoryProgressStorageService implements ProgressStorageService {
  /// The stored records by aircraft path; tests may fill it directly.
  final Map<String, StoredProgress> records = {};

  /// `(aircraftPath, data)` of every [write], in order.
  final writes = <(String, StoredProgress)>[];

  /// Aircraft path of every [read], in order.
  final reads = <String>[];

  /// Aircraft path of every [delete], in order.
  final deletes = <String>[];

  /// While true, [write] returns an error and store nothing.
  bool failWrites = false;

  /// Total number of calls of any kind.
  int get callCount => writes.length + reads.length + deletes.length;

  @override
  Future<StoredProgress?> read(String aircraftPath) async {
    reads.add(aircraftPath);
    return records[aircraftPath];
  }

  @override
  Future<Result<void>> write(String aircraftPath, StoredProgress data) async {
    writes.add((aircraftPath, data));
    if (failWrites) return Error(SourceReadFailure('disk full'));
    records[aircraftPath] = data;
    return const Ok(null);
  }

  @override
  Future<void> delete(String aircraftPath) async {
    deletes.add(aircraftPath);
    records.remove(aircraftPath);
  }
}
