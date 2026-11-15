import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../utils/app_exception.dart';
import '../../../utils/result.dart';
import 'aircraft_file_name.dart';
import 'model/stored_progress.dart';

/// Keeps the checked items of each aircraft between runs, keyed by the
/// aircraft path. It deals in raw values; the repository maps them to the
/// domain.
abstract class ProgressStorageService {
  /// The record for [aircraftPath], or null when there is none or it is
  /// unreadable. Never throws.
  Future<StoredProgress?> read(String aircraftPath);

  /// Stores [data] atomically. A failure is returned, not thrown.
  Future<Result<void>> write(String aircraftPath, StoredProgress data);

  /// Removes the record for [aircraftPath]; a missing one is fine.
  Future<void> delete(String aircraftPath);
}

/// The format written. Version 1 (no auto or manual-uncheck sets), version 2
/// (no cursor or disagreed marks) and version 3 (no skipped items) are
/// still read.
const _version = 4;

/// [ProgressStorageService] with one JSON file per aircraft in a directory.
class FileProgressStorageService implements ProgressStorageService {
  /// Creates the service over [directory], created on the first write.
  FileProgressStorageService(Directory directory)
    : _resolveDirectory = (() async => directory);

  /// A `progress` folder in the application support directory.
  FileProgressStorageService.inApplicationSupport()
    : _resolveDirectory = (() async {
        final support = await getApplicationSupportDirectory();
        return Directory('${support.path}${Platform.pathSeparator}progress');
      });

  final Future<Directory> Function() _resolveDirectory;
  Directory? _directory;

  Future<Directory> _dir() async => _directory ??= await _resolveDirectory();

  Future<File> _file(String aircraftPath) async => File(
    '${(await _dir()).path}${Platform.pathSeparator}'
    '${aircraftFileName(aircraftPath)}',
  );

  @override
  Future<StoredProgress?> read(String aircraftPath) async {
    try {
      final file = await _file(aircraftPath);
      if (!await file.exists()) return null;
      final json = jsonDecode(utf8.decode(await file.readAsBytes()));
      return _decode(json, aircraftPath);
    } on Object {
      return null;
    }
  }

  StoredProgress? _decode(Object? json, String aircraftPath) {
    if (json is! Map<String, Object?> ||
        (json['version'] != 1 &&
            json['version'] != 2 &&
            json['version'] != 3 &&
            json['version'] != _version) ||
        json['aircraftPath'] != aircraftPath) {
      return null;
    }
    final lastViewed = json['lastViewed'];
    final runId = json['runId'];
    final lists = json['checklists'];
    if (lastViewed != null && lastViewed is! String) return null;
    if (runId != null && runId is! String) return null;
    if (lists is! Map<String, Object?>) return null;
    final checklists = <String, StoredChecklistProgress>{};
    for (final entry in lists.entries) {
      final value = entry.value;
      if (value is! Map<String, Object?>) return null;
      final checked = value['checked'];
      final fingerprint = value['fingerprint'];
      if (checked is! List || fingerprint is! String) return null;
      if (checked.any((i) => i is! int || i < 0)) return null;
      final auto = _indexes(value['autoChecked']);
      // Older files may hold 'manuallyUnchecked'; it is ignored.
      final disagreed = _indexes(value['disagreed']);
      final skipped = _indexes(value['skipped']);
      // Added with the switch blocks (D-82); absent in older files of this
      // version, which then read as every switch off.
      final enabled = _indexes(value['enabled']);
      if (auto == null ||
          disagreed == null ||
          skipped == null ||
          enabled == null) {
        return null;
      }
      // A damaged cursor is not worth losing the marks for: back to the top.
      final cursor = value['cursor'];
      checklists[entry.key] = StoredChecklistProgress(
        checked: List<int>.from(checked),
        fingerprint: fingerprint,
        autoChecked: auto,
        disagreed: disagreed,
        skipped: skipped,
        enabled: enabled,
        cursor: cursor is int && cursor > 0 ? cursor : 0,
      );
    }
    return StoredProgress(
      lastViewed: lastViewed as String?,
      runId: runId as String?,
      checklists: checklists,
    );
  }

  /// A list of non-negative whole numbers; empty when absent (version 1);
  /// null when it is anything else.
  List<int>? _indexes(Object? value) {
    if (value == null) return const [];
    if (value is! List || value.any((i) => i is! int || i < 0)) return null;
    return List<int>.from(value);
  }

  @override
  Future<Result<void>> write(String aircraftPath, StoredProgress data) async {
    File? temp;
    try {
      final target = await _file(aircraftPath);
      temp = File('${target.path}.tmp');
      await (await _dir()).create(recursive: true);
      await temp.writeAsString(
        jsonEncode({
          'version': _version,
          'aircraftPath': aircraftPath,
          'lastViewed': data.lastViewed,
          'runId': data.runId,
          'checklists': {
            for (final e in data.checklists.entries)
              e.key: {
                'checked': ([...e.value.checked]..sort()),
                'autoChecked': ([...e.value.autoChecked]..sort()),
                'disagreed': ([...e.value.disagreed]..sort()),
                'skipped': ([...e.value.skipped]..sort()),
                'enabled': ([...e.value.enabled]..sort()),
                'cursor': e.value.cursor,
                'fingerprint': e.value.fingerprint,
              },
          },
        }),
        flush: true,
      );
      await temp.rename(target.path);
      return const Ok(null);
    } on Object catch (e) {
      try {
        if (temp != null && await temp.exists()) await temp.delete();
      } on Object {
        // Nothing more can be done about a temp file we cannot remove.
      }
      return Error(SourceReadFailure('Could not save progress: $e'));
    }
  }

  @override
  Future<void> delete(String aircraftPath) async {
    try {
      final file = await _file(aircraftPath);
      if (await file.exists()) await file.delete();
    } on Object {
      // A record that cannot be removed is overwritten by the next write.
    }
  }
}
