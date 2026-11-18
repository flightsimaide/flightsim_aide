// Checks the Microsoft Flight Simulator names of a checklist file against the
// running simulator, through the companion.
//
//   dart run tools/msfs_name_check.dart <baseUrl> <checklist.txt>
//
// Every quoted name that starts with A:, L: or B: is subscribed to and the
// answer is printed. The simulator must be running with the aircraft of the
// checklist loaded. What it can and cannot tell (GRAMMAR.md N7):
//   - an A: name or unit the sim refuses, and a B: name the aircraft does not
//     have, are reported as UNKNOWN;
//   - an L: name that does not exist reads 0 and cannot be told from one that
//     does, so the tool prints the value it reads: a name that stays 0 while
//     the switch it stands for is on is a spelling to check;
//   - a value of null means the simulator gave none.
// Exit code: 0 when no name is UNKNOWN, 1 when one is, 2 on a usage error or
// when the companion cannot be reached.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The distinct quoted `A:`, `L:` and `B:` names in [text], in file order.
List<String> msfsNamesIn(String text) {
  final found = <String>[];
  final pattern = RegExp(r'''(["'])([ALB]:[^"'\[\]]*?)\1''');
  for (final match in pattern.allMatches(text)) {
    final name = match.group(2)!.trim();
    if (!found.contains(name)) found.add(name);
  }
  return found;
}

/// Runs the check; returns the exit code.
Future<int> msfsNameCheck(
  List<String> args, {
  void Function(String)? out,
  Duration wait = const Duration(seconds: 6),
}) async {
  final void Function(String) write = out ?? (s) => stdout.writeln(s);
  if (args.length != 2) {
    write('usage: msfs_name_check.dart <baseUrl> <checklist.txt>');
    return 2;
  }
  final file = File(args[1]);
  if (!file.existsSync()) {
    write('no such file: ${args[1]}');
    return 2;
  }
  final names = msfsNamesIn(file.readAsStringSync());
  if (names.isEmpty) {
    write('no A:, L: or B: names found');
    return 0;
  }
  final WebSocket socket;
  try {
    final url = Uri.parse(args[0]).replace(scheme: 'ws', path: '/v1/stream');
    socket = await WebSocket.connect(url.toString());
  } on Object catch (e) {
    write('cannot connect to ${args[0]}: $e');
    return 2;
  }
  final answers = <int, String>{};
  final values = <int, Object?>{};
  final done = Completer<void>();
  final sub = socket.listen((message) {
    final Object? frame = jsonDecode(message as String);
    if (frame is! Map<String, Object?>) return;
    final id = frame['id'];
    if (frame['op'] == 'subscribed' && id is int) answers[id] = 'ok';
    if (frame['op'] == 'error' && id is int) {
      answers[id] = (frame['code'] as String? ?? 'error').toUpperCase();
    }
    if (frame['op'] == 'values') {
      final v = frame['v'];
      if (v is Map<String, Object?>) {
        v.forEach((k, value) => values[int.parse(k)] = value);
      }
    }
    if (answers.length >= names.length && values.length >= _okCount(answers)) {
      if (!done.isCompleted) done.complete();
    }
  });
  // At most 128 subscriptions go on one connection.
  final limited = names.length > 128 ? names.sublist(0, 128) : names;
  if (limited.length < names.length) {
    write('only the first 128 of ${names.length} names are checked');
  }
  for (var i = 0; i < limited.length; i++) {
    socket.add(
      jsonEncode({'op': 'subscribe', 'id': i, 'name': limited[i], 'hz': 2}),
    );
  }
  await done.future.timeout(wait, onTimeout: () {});
  await sub.cancel();
  await socket.close();

  var unknown = 0;
  for (var i = 0; i < limited.length; i++) {
    final answer = answers[i] ?? 'NO ANSWER';
    if (answer == 'UNKNOWN_NAME') unknown++;
    final value = answer == 'ok' ? '  value ${values[i] ?? 'none'}' : '';
    write(
      '${answer == 'UNKNOWN_NAME' ? 'UNKNOWN' : answer.padRight(7)}  '
      '${limited[i]}$value',
    );
  }
  write('${limited.length} names, $unknown unknown');
  return unknown == 0 ? 0 : 1;
}

int _okCount(Map<int, String> answers) =>
    answers.values.where((a) => a == 'ok').length;

Future<void> main(List<String> args) async {
  exitCode = await msfsNameCheck(args);
}
