import 'dart:convert';

/// The file name for data kept per aircraft: 16 hex digits of a 64-bit FNV-1a
/// hash of [aircraftPath] plus `.json`, so no character of the path (which may
/// hold separators or odd characters) reaches the file system.
String aircraftFileName(String aircraftPath) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(aircraftPath)) {
    hash ^= byte;
    hash *= 0x100000001b3;
  }
  final hex = BigInt.from(hash).toUnsigned(64).toRadixString(16);
  return '${hex.padLeft(16, '0')}.json';
}
