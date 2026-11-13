// Checks the condition fixtures in testing/fixtures/conditions.
//
//   dart run tools/check_condition_fixtures.dart [dir]
//
// For every `<name>.txt` it needs `<name>.values.json` and `<name>.expected.json`, both valid JSON of the shape in
// that folder's README.md, every item index in the expected file must exist in the checklist (check items counted
// from 0 in file order), and every checklist named in `show` and `continue` must exist. Prints `conditions OK` or
// one `FIXTURE FAIL [name]: reason` per problem, and exits non-zero on any.
import 'dart:convert';
import 'dart:io';

final _checklist = RegExp(
  r'^\s*@?sw_checklist:([^:\r\n]*)',
  caseSensitive: false,
);
final _checkItem = RegExp(r'^\s*@?sw_item(_c)?:', caseSensitive: false);

void main(List<String> args) => exit(_run(args));

int _run(List<String> args) {
  final dir = Directory(
    args.isEmpty ? 'testing/fixtures/conditions' : args.first,
  );
  if (!dir.existsSync()) {
    stdout.writeln('FIXTURE FAIL [conditions]: ${dir.path} not found');
    return 1;
  }
  final names =
      dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.txt'))
          .map((n) => n.substring(0, n.length - 4))
          .toList()
        ..sort();
  var failures = 0;
  void fail(String name, String why) {
    failures++;
    stdout.writeln('FIXTURE FAIL [$name]: $why');
  }

  if (names.isEmpty) {
    fail('conditions', 'no .txt fixtures found');
  }
  for (final name in names) {
    final values = File('${dir.path}/$name.values.json');
    final expected = File('${dir.path}/$name.expected.json');
    if (!values.existsSync()) {
      fail(name, 'missing $name.values.json');
    }
    if (!expected.existsSync()) {
      fail(name, 'missing $name.expected.json');
    }
    if (!values.existsSync() || !expected.existsSync()) {
      continue;
    }

    final lines = const LineSplitter().convert(
      File('${dir.path}/$name.txt').readAsStringSync(),
    );
    final lists = <String>{};
    var checkItems = 0;
    for (final line in lines) {
      final c = _checklist.firstMatch(line);
      if (c != null) {
        lists.add(c.group(1)!.trim());
      }
      if (_checkItem.hasMatch(line)) {
        checkItems++;
      }
    }

    Object? v;
    Object? e;
    try {
      v = jsonDecode(values.readAsStringSync());
    } on FormatException catch (x) {
      fail(name, '$name.values.json is not JSON: ${x.message}');
    }
    try {
      e = jsonDecode(expected.readAsStringSync());
    } on FormatException catch (x) {
      fail(name, '$name.expected.json is not JSON: ${x.message}');
    }
    if (v != null) {
      if (v is! Map<String, Object?>) {
        fail(name, 'values must be a JSON object');
      } else if (v.containsKey('steps')) {
        final steps = v['steps'];
        if (steps is! List || steps.isEmpty || steps.any((s) => s is! Map)) {
          fail(name, '"steps" must be a non-empty list of objects');
        } else {
          for (final s in steps) {
            for (final entry in (s as Map).entries) {
              if (entry.value != null && entry.value is! num) {
                fail(name, 'value of ${entry.key} is not a number or null');
              }
            }
          }
        }
      } else {
        for (final entry in v.entries) {
          if (entry.value is! num) {
            fail(name, 'value of ${entry.key} is not a number');
          }
        }
      }
    }
    if (e != null) {
      if (e is! Map<String, Object?>) {
        fail(name, 'expected must be a JSON object');
        continue;
      }
      if (e['source'] is! String) {
        fail(name, 'expected needs a "source" string');
      }
      final seen = <int>{};
      for (final key in ['met', 'not_met', 'unknown']) {
        final list = e[key];
        if (list is! List) {
          fail(name, '"$key" must be a list');
          continue;
        }
        for (final i in list) {
          if (i is! int || i < 0 || i >= checkItems) {
            fail(
              name,
              '"$key" has index $i but the file has $checkItems check items',
            );
          } else if (!seen.add(i)) {
            fail(name, 'index $i appears in more than one list');
          }
        }
      }
      final show = e['show'];
      if (show != null) {
        if (show is! Map) {
          fail(name, '"show" must be an object');
        } else {
          for (final entry in show.entries) {
            if (!lists.contains(entry.key)) {
              fail(name, '"show" names unknown checklist "${entry.key}"');
            }
            if (!const {'met', 'not_met', 'unknown'}.contains(entry.value)) {
              fail(name, 'bad show value ${entry.value}');
            }
          }
        }
      }
      final cont = e['continue'];
      if (cont != null) {
        if (cont is! Map) {
          fail(name, '"continue" must be an object');
        } else {
          for (final entry in cont.entries) {
            if (!lists.contains(entry.key)) {
              fail(name, '"continue" names unknown checklist "${entry.key}"');
            }
            if (entry.value != null && !lists.contains(entry.value)) {
              fail(
                name,
                '"continue" target "${entry.value}" is not a checklist',
              );
            }
          }
        }
      }
      final warnings = e['warnings'];
      if (warnings is! List || warnings.any((w) => w is! String)) {
        fail(name, '"warnings" must be a list of text');
      }
    }
  }
  if (failures == 0) {
    stdout.writeln('conditions OK (${names.length} fixtures)');
  }
  return failures == 0 ? 0 : 1;
}
