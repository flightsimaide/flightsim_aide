// Reads many Microsoft Flight Simulator names at once through the companion and
// saves them, or compares two saved readings. Use it to find which variable
// goes with a switch: take a reading, move the switch, take another and compare.
//
//   dart run tools/msfs_snapshot.dart take <baseUrl> <names.txt> <out.tsv>
//   dart run tools/msfs_snapshot.dart diff <before.tsv> <after.tsv>
//
// names.txt has one name per line (`A:...`, `L:...`, `B:...`); blank lines and
// lines starting with # are skipped. A name the sim does not know is saved as
// `unknown`; a value the sim gave none for is saved as `-`.
// Exit code: 0, or 2 on a usage error or when the companion cannot be reached.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _batch = 128;

/// The names of [text]: one per line, comments and blank lines skipped.
List<String> namesIn(String text) => [
  for (final line in const LineSplitter().convert(text))
    if (line.trim().isNotEmpty && !line.trim().startsWith('#')) line.trim(),
];

/// Parses a saved reading (`name<TAB>value` lines) into a map.
Map<String, String> parseReading(String text) {
  final map = <String, String>{};
  for (final line in const LineSplitter().convert(text)) {
    final tab = line.lastIndexOf('\t');
    if (tab <= 0) continue;
    map[line.substring(0, tab)] = line.substring(tab + 1);
  }
  return map;
}

/// The lines that differ between two readings, as `name: before -> after`.
List<String> diffReadings(Map<String, String> a, Map<String, String> b) {
  final out = <String>[];
  for (final name in {...a.keys, ...b.keys}) {
    final x = a[name] ?? 'missing';
    final y = b[name] ?? 'missing';
    if (x == y) continue;
    final dx = double.tryParse(x);
    final dy = double.tryParse(y);
    if (dx != null && dy != null && (dx - dy).abs() < 1e-6) continue;
    out.add('$name: $x -> $y');
  }
  out.sort();
  return out;
}

Future<Map<String, String>> _readBatch(
  String baseUrl,
  List<String> names,
) async {
  final url = Uri.parse(baseUrl).replace(scheme: 'ws', path: '/v1/stream');
  final socket = await WebSocket.connect(url.toString());
  final result = {for (final n in names) n: '-'};
  final answered = <int>{};
  final gotValue = <int>{};
  final done = Completer<void>();
  final sub = socket.listen((message) {
    final Object? frame = jsonDecode(message as String);
    if (frame is! Map<String, Object?>) return;
    final id = frame['id'];
    if (frame['op'] == 'error' && id is int && id < names.length) {
      result[names[id]] = 'unknown';
      answered.add(id);
      gotValue.add(id);
    } else if (frame['op'] == 'subscribed' && id is int) {
      answered.add(id);
    } else if (frame['op'] == 'values') {
      final v = frame['v'];
      if (v is Map<String, Object?>) {
        v.forEach((key, value) {
          final i = int.parse(key);
          if (i >= names.length) return;
          gotValue.add(i);
          result[names[i]] = value == null ? '-' : '$value';
        });
      }
    }
    if (answered.length >= names.length && gotValue.length >= names.length) {
      if (!done.isCompleted) done.complete();
    }
  });
  for (var i = 0; i < names.length; i++) {
    socket.add(
      jsonEncode({'op': 'subscribe', 'id': i, 'name': names[i], 'hz': 2}),
    );
  }
  await done.future.timeout(const Duration(seconds: 8), onTimeout: () {});
  await sub.cancel();
  await socket.close();
  return result;
}

/// Runs the tool; returns the exit code.
Future<int> msfsSnapshot(
  List<String> args, {
  void Function(String)? out,
}) async {
  final void Function(String) write = out ?? (s) => stdout.writeln(s);
  if (args.length == 3 && args[0] == 'diff') {
    final a = File(args[1]);
    final b = File(args[2]);
    if (!a.existsSync() || !b.existsSync()) {
      write('no such file');
      return 2;
    }
    final lines = diffReadings(
      parseReading(a.readAsStringSync()),
      parseReading(b.readAsStringSync()),
    );
    lines.forEach(write);
    write('${lines.length} changed');
    return 0;
  }
  if (args.length == 4 && args[0] == 'take') {
    final names = File(args[2]).existsSync()
        ? namesIn(File(args[2]).readAsStringSync())
        : null;
    if (names == null) {
      write('no such file: ${args[2]}');
      return 2;
    }
    final all = <String, String>{};
    try {
      for (var i = 0; i < names.length; i += _batch) {
        final end = i + _batch < names.length ? i + _batch : names.length;
        all.addAll(await _readBatch(args[1], names.sublist(i, end)));
      }
    } on Object catch (e) {
      write('cannot read from ${args[1]}: $e');
      return 2;
    }
    File(args[3]).writeAsStringSync(
      [for (final e in all.entries) '${e.key}\t${e.value}'].join('\n'),
    );
    final unknown = all.values.where((v) => v == 'unknown').length;
    write('${all.length} names saved to ${args[3]} ($unknown unknown)');
    return 0;
  }
  write('usage: msfs_snapshot.dart take <baseUrl> <names.txt> <out.tsv>');
  write('       msfs_snapshot.dart diff <before.tsv> <after.tsv>');
  return 2;
}

Future<void> main(List<String> args) async {
  exitCode = await msfsSnapshot(args);
}
