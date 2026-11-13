import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// A checklist file as the cache stores it: the raw bytes and the facts the
/// plugin reported about the file when it was fetched.
class CachedChecklist extends Equatable {
  /// Creates an entry.
  const CachedChecklist({
    required this.bytes,
    required this.checklistPath,
    required this.mtime,
    required this.size,
  });

  /// The file exactly as the plugin served it, undecoded.
  final Uint8List bytes;

  /// Path of the file the plugin used.
  final String checklistPath;

  /// Last-write time of the file, epoch milliseconds.
  final int mtime;

  /// Size of the file in bytes.
  final int size;

  @override
  List<Object?> get props => [bytes, checklistPath, mtime, size];
}
