// Reads many Microsoft Flight Simulator names at once through the companion and
// saves them, or compares two saved readings. Use it to find which variable
// goes with a switch: take a reading, move the switch, take another and compare.
//
//   dart run tools/msfs_snapshot.dart take <baseUrl> <names.txt> <out.tsv>
//   dart run tools/msfs_snapshot.dart diff <before.tsv> <after.tsv>
//   dart run tools/msfs_snapshot.dart watch <baseUrl> <names.txt>
//
// `watch` prints every change as it happens, with the time, until stopped. A
// name that changes more than 6 times in 10 seconds is muted (a clock, a gauge).
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
      // Input events are read about four times a second after the sim lists
      // them, so keep listening a little for their first real value.
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (!done.isCompleted) done.complete();
      });
    }
  });
  for (var i = 0; i < names.length; i++) {
    socket.add(
      jsonEncode({'op': 'subscribe', 'id': i, 'name': names[i], 'hz': 2}),
    );
  }
  await done.future.timeout(const Duration(seconds: 12), onTimeout: () {});
  await sub.cancel();
  await socket.close();
  return result;
}

/// Prints each change of [names] as it happens. Runs until the process ends.
Future<void> watchNames(
  String baseUrl,
  List<String> names,
  void Function(String) write,
) async {
  final url = Uri.parse(baseUrl).replace(scheme: 'ws', path: '/v1/stream');
  final last = <String, String>{};
  final changes = <String, List<DateTime>>{};
  final muted = <String>{};
  var ready = false;
  Future<void>.delayed(const Duration(seconds: 6), () => ready = true);
  for (var start = 0; start < names.length; start += _batch) {
    final end = start + _batch < names.length ? start + _batch : names.length;
    final part = names.sublist(start, end);
    final socket = await WebSocket.connect(url.toString());
    socket.listen((message) {
      final Object? frame = jsonDecode(message as String);
      if (frame is! Map<String, Object?> || frame['op'] != 'values') return;
      final v = frame['v'];
      if (v is! Map<String, Object?>) return;
      v.forEach((key, value) {
        final i = int.parse(key);
        if (i >= part.length) return;
        final name = part[i];
        final now = value == null ? '-' : '$value';
        final before = last[name];
        last[name] = now;
        if (before == null || before == now || !ready || muted.contains(name)) {
          return;
        }
        final x = double.tryParse(before);
        final y = double.tryParse(now);
        if (x != null && y != null && (x - y).abs() < 0.001) return;
        final at = DateTime.now();
        final log = (changes[name] ??= [])
          ..add(at)
          ..removeWhere((d) => at.difference(d).inSeconds > 10);
        if (log.length > 6) {
          muted.add(name);
          write('${_clock(at)}  (muted, changes constantly) $name');
          return;
        }
        write('${_clock(at)}  $name: $before -> $now');
      });
    });
    for (var i = 0; i < part.length; i++) {
      socket.add(
        jsonEncode({'op': 'subscribe', 'id': i, 'name': part[i], 'hz': 4}),
      );
    }
  }
  write('watching ${names.length} names; the first 6 seconds are not shown');
  await Completer<void>().future;
}

String _clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}';

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
  if (args.length == 3 && args[0] == 'watch') {
    final file = File(args[2]);
    if (!file.existsSync()) {
      write('no such file: ${args[2]}');
      return 2;
    }
    try {
      await watchNames(args[1], namesIn(file.readAsStringSync()), write);
    } on Object catch (e) {
      write('cannot read from ${args[1]}: $e');
      return 2;
    }
    return 0;
  }
  write('usage: msfs_snapshot.dart take <baseUrl> <names.txt> <out.tsv>');
  write('       msfs_snapshot.dart diff <before.tsv> <after.tsv>');
  write('       msfs_snapshot.dart watch <baseUrl> <names.txt>');
  return 2;
}

Future<void> main(List<String> args) async {
  exitCode = await msfsSnapshot(args);
}
