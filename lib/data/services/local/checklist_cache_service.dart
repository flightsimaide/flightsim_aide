import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../../utils/app_exception.dart';
import '../../../utils/result.dart';
import 'aircraft_file_name.dart';
import 'model/cached_checklist.dart';

/// Keeps the raw text of each aircraft's checklist between runs, keyed by the
/// aircraft path (not the ICAO: liveries and variants share one).
abstract class ChecklistCacheService {
  /// The entry for [aircraftPath], or null when there is none or it is
  /// unreadable. Never throws.
  Future<CachedChecklist?> read(String aircraftPath);

  /// Stores [entry]. A failure is returned, not thrown.
  Future<Result<void>> write(String aircraftPath, CachedChecklist entry);

  /// Removes the entry for [aircraftPath]; a missing one is fine.
  Future<void> delete(String aircraftPath);
}

const _version = 1;

/// [ChecklistCacheService] with one JSON file per aircraft in [directory].
///
/// The file name is a hash of the aircraft path, so it holds no character from
/// the path. The entry repeats the path and is ignored if it does not match
/// (a hash collision, or a file copied by hand).
class FileChecklistCacheService implements ChecklistCacheService {
  /// Creates a cache in [directory], which is created on the first write.
  FileChecklistCacheService(Directory directory)
    : _resolveDirectory = (() async => directory);

  /// Creates a cache whose directory is found on first use.
  FileChecklistCacheService.lazy(Future<Directory> Function() resolve)
    : _resolveDirectory = resolve;

  /// A cache in a `checklist_cache` folder of the app's support directory.
  FileChecklistCacheService.inApplicationSupport()
    : _resolveDirectory = (() async {
        final support = await getApplicationSupportDirectory();
        return Directory(
          '${support.path}${Platform.pathSeparator}checklist_cache',
        );
      });

  final Future<Directory> Function() _resolveDirectory;
  Directory? _directory;

  Future<Directory> _dir() async => _directory ??= await _resolveDirectory();

  /// The file name for [aircraftPath]: 16 hex digits of a 64-bit FNV-1a hash.
  String fileNameFor(String aircraftPath) => aircraftFileName(aircraftPath);

  Future<File> _file(String aircraftPath) async => File(
    '${(await _dir()).path}${Platform.pathSeparator}${fileNameFor(aircraftPath)}',
  );

  @override
  Future<CachedChecklist?> read(String aircraftPath) async {
    try {
      final file = await _file(aircraftPath);
      if (!await file.exists()) return null;
      final json = jsonDecode(utf8.decode(await file.readAsBytes()));
      if (json is! Map<String, Object?> ||
          json['version'] != _version ||
          json['aircraftPath'] != aircraftPath) {
        return null;
      }
      final path = json['checklistPath'];
      final mtime = json['mtime'];
      final size = json['size'];
      final data = json['data'];
      if (path is! String || mtime is! int || size is! int || data is! String) {
        return null;
      }
      return CachedChecklist(
        bytes: Uint8List.fromList(base64Decode(data)),
        checklistPath: path,
        mtime: mtime,
        size: size,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<Result<void>> write(String aircraftPath, CachedChecklist entry) async {
    File? temp;
    try {
      final target = await _file(aircraftPath);
      temp = File('${target.path}.tmp');
      await (await _dir()).create(recursive: true);
      await temp.writeAsString(
        jsonEncode({
          'version': _version,
          'aircraftPath': aircraftPath,
          'checklistPath': entry.checklistPath,
          'mtime': entry.mtime,
          'size': entry.size,
          'data': base64Encode(entry.bytes),
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
      return Error(
        SourceReadFailure('Could not store the checklist cache: $e'),
      );
    }
  }

  @override
  Future<void> delete(String aircraftPath) async {
    try {
      final file = await _file(aircraftPath);
      if (await file.exists()) await file.delete();
    } on Object {
      // A cache entry that cannot be removed is simply stale; reads verify it.
    }
  }
}
