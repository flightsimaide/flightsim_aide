import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// The outcome of `GET /v1/checklist`.
sealed class RawChecklistFetch extends Equatable {
  const RawChecklistFetch();

  @override
  List<Object?> get props => const [];
}

/// A `200` answer: the file's raw bytes, undecoded.
final class RawChecklistResponse extends RawChecklistFetch {
  /// Creates a checklist answer.
  const RawChecklistResponse({
    required this.bytes,
    required this.etag,
    required this.generation,
  });

  /// The file exactly as served.
  final Uint8List bytes;

  /// The `ETag` header, quotes included.
  final String etag;

  /// The `X-Aircraft-Generation` header.
  final int generation;

  @override
  List<Object?> get props => [bytes, etag, generation];
}

/// A `304` answer: the cached copy is still current.
final class NotModified extends RawChecklistFetch {
  /// Creates the answer.
  const NotModified();
}
