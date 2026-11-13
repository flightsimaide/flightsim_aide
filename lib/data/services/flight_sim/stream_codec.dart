import 'dart:convert';

import 'model/raw_frame.dart';

const _maxNameLength = 200;
const _maxHz = 60;

/// The `subscribe` frame for signal [name] at [hz] under subscription [id].
///
/// Throws [ArgumentError] when the request breaks the protocol's limits (id
/// 0 or more, name 1 to 200 characters without control characters, hz 1 to
/// 60), so a bad request fails here and not on the wire.
String encodeSubscribe(int id, String name, int hz) {
  if (id < 0) throw ArgumentError.value(id, 'id', 'must not be negative');
  if (name.isEmpty || name.length > _maxNameLength) {
    throw ArgumentError.value(name, 'name', 'must be 1 to 200 characters');
  }
  if (name.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
    throw ArgumentError.value(name, 'name', 'has a control character');
  }
  if (hz < 1 || hz > _maxHz) {
    throw ArgumentError.value(hz, 'hz', 'must be 1 to 60');
  }
  return jsonEncode({'op': 'subscribe', 'id': id, 'name': name, 'hz': hz});
}

/// The `unsubscribe` frame for [id].
String encodeUnsubscribe(int id) => jsonEncode({'op': 'unsubscribe', 'id': id});

/// The `ping` frame.
String encodePing() => jsonEncode({'op': 'ping'});

/// Decodes a server frame. Returns null for invalid JSON, an unknown `op` or
/// a wrong shape; unknown fields are ignored. Never throws.
RawFrame? decodeFrame(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, Object?>) return null;
  switch (json['op']) {
    case 'subscribed':
      final id = json['id'];
      return id is int ? Subscribed(id) : null;
    case 'error':
      final code = json['code'];
      final id = json['id'];
      if (code is! String) return null;
      if (id != null && id is! int) return null;
      return StreamError(code, id: id as int?);
    case 'values':
      return _values(json);
    case 'hb':
      return const Heartbeat();
    case 'pong':
      return const Pong();
    default:
      return null;
  }
}

Values? _values(Map<String, Object?> json) {
  final t = json['t'];
  final v = json['v'];
  if (t is! num || v is! Map<String, Object?>) return null;
  final values = <int, num?>{};
  final lists = <int, List<num?>>{};
  for (final entry in v.entries) {
    final id = int.tryParse(entry.key);
    final value = entry.value;
    if (id == null) return null;
    if (value is List<Object?>) {
      if (value.any((e) => e != null && e is! num)) return null;
      lists[id] = [for (final e in value) e as num?];
    } else if (value == null || value is num) {
      values[id] = value as num?;
    } else {
      return null;
    }
  }
  return Values(t.toInt(), values, lists: lists);
}
