import 'checklist.dart';

/// A stable text identifying the shape of [checklist]: the item types and
/// labels in order. Results and colour runs do not matter, so a colour or
/// wording change in an expected response keeps the saved marks.
///
/// It is 32-bit FNV-1a over the UTF-16 code units of
/// `type US label RS` for each item, written as 8 hex digits followed by the
/// item count. Dart's `hashCode` is not used: it is not stable across runs.
String fingerprintOf(Checklist checklist) {
  var hash = 0x811c9dc5;
  void add(int unit) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }

  for (final item in checklist.items) {
    add(item.type.index + 0x30);
    add(0x1f);
    item.label.codeUnits.forEach(add);
    add(0x1e);
  }
  final hex = hash.toRadixString(16).padLeft(8, '0');
  return '$hex-${checklist.items.length}';
}
