import 'dart:convert';
import 'dart:typed_data';

/// Decodes checklist file bytes: strict UTF-8 first, Latin-1 if that fails.
///
/// A leading BOM is kept; the parser strips it.
String decodeChecklistText(Uint8List bytes) {
  try {
    final text = utf8.decode(bytes);
    // utf8.decode drops a leading BOM, so put it back.
    final hasBom =
        bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF;
    return hasBom ? '﻿$text' : text;
  } on FormatException {
    return latin1.decode(bytes);
  }
}
