import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// AC-48: every acceptance criterion in PLAN.md has its test tag or manual-test entry.
// AC-49: the production wiring is final: no temporary code, no file_picker, no bundled sample.
// AC-51: socket, http and stream code stays in data/services; domain is pure.
// AC-52: every grammar rule has a status and evidence.
// AC-53: the plugin builds on Windows, macOS and Linux in CI.

String norm(String path) => path.replaceAll(r'\', '/');

List<File> dartFiles(String dir) => [
  for (final e in Directory(dir).listSync(recursive: true))
    if (e is File && e.path.endsWith('.dart')) e,
];

Future<ProcessResult?> run(String script, List<String> args) async {
  try {
    return await Process.run('bash', ['tools/$script', ...args]);
  } on ProcessException {
    return null;
  }
}

void main() {
  group('every criterion is covered (AC-48)', () {
    test('check_acceptance_tags passes', () async {
      final result = await run('check_acceptance_tags.sh', []);
      if (result == null) {
        markTestSkipped('bash is not available');
        return;
      }
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    });
  });

  group('the production wiring is final (AC-49)', () {
    test('no temporary folder remains in lib or test', () {
      final found = [
        for (final dir in ['lib', 'test'])
          for (final e in Directory(dir).listSync(recursive: true))
            if (e is Directory && norm(e.path).endsWith('/temporary'))
              norm(e.path),
      ];
      expect(found, isEmpty);
    });

    test('no file_picker and no bundled sample', () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        isNot(contains('file_picker')),
      );
      expect(File('assets/sample_checklist.txt').existsSync(), isFalse);
      final users = [
        for (final f in dartFiles('lib'))
          if (f.readAsStringSync().contains('file_picker')) norm(f.path),
      ];
      expect(users, isEmpty);
    });

    test('main.dart runs through the production providers', () {
      expect(
        File('lib/main.dart').readAsStringSync(),
        contains('productionProviders'),
      );
    });
  });

  group('layering (AC-51)', () {
    test('no socket or http import outside data/services and config', () {
      final hits = <String>[];
      for (final f in dartFiles('lib')) {
        final path = norm(f.path);
        if (path.contains('lib/data/services/') ||
            path.contains('lib/config/')) {
          continue;
        }
        if (RegExp(r"import 'package:http/|import 'dart:io'")
            .hasMatch(f.readAsStringSync())) {
          hits.add(path);
        }
      }
      expect(hits, isEmpty);
    });

    test('no stream, socket or throttle code in a widget file', () {
      final hits = <String>[];
      final bad = RegExp(
        r'WebSocket|RawDatagramSocket|RawSocket|\.throttle|ThrottleStream',
      );
      for (final f in dartFiles('lib/ui')) {
        if (!norm(f.path).contains('/widgets/')) continue;
        if (bad.hasMatch(f.readAsStringSync())) hits.add(norm(f.path));
      }
      expect(hits, isEmpty);
    });

    test('domain imports only Dart core and equatable', () {
      final hits = <String>[];
      final import = RegExp(r"^import '([^']+)';", multiLine: true);
      for (final f in dartFiles('lib/domain')) {
        for (final m in import.allMatches(f.readAsStringSync())) {
          final target = m.group(1)!;
          final ok =
              target.startsWith('dart:') && target != 'dart:io' ||
              target.startsWith('package:equatable/') ||
              target.startsWith('package:flightsim_aide/domain/') ||
              (!target.contains(':') &&
                  !target.contains('../data') &&
                  !target.contains('../ui') &&
                  !target.contains('../config'));
          if (!ok) hits.add('${norm(f.path)}: $target');
        }
      }
      expect(hits, isEmpty);
    });
  });

  group('the grammar is complete (AC-52)', () {
    test('every rule in GRAMMAR section 8 has a status and evidence', () {
      final text = File('Documentation/Reference/GRAMMAR.md')
          .readAsStringSync();
      final start = text.indexOf('## 8. Conditions');
      final end = text.indexOf('## Changelog');
      expect(start, greaterThan(-1));
      final section = text.substring(start, end > start ? end : text.length);
      final rows = section
          .split('\n')
          .where((l) => RegExp(r'^\| [A-Z]+\d+ \|').hasMatch(l))
          .toList();
      expect(rows, isNotEmpty);
      final missing = <String>[];
      for (final row in rows) {
        final cells = row.split(RegExp(r'(?<!\\)\|')).map((c) => c.trim());
        final list = cells.toList();
        // Cells: '', id, rule, status, evidence, ''.
        if (list.length < 6 || list[3].isEmpty || list[4].isEmpty) {
          missing.add(list.length > 1 ? list[1] : row);
        }
      }
      expect(missing, isEmpty);
    });
  });

  group('plugin health in CI (AC-53)', () {
    test('the plugin workflow builds on Windows, macOS and Linux', () {
      final yml = File('.github/workflows/plugin.yml').readAsStringSync();
      for (final os in ['windows-latest', 'macos-latest', 'ubuntu-latest']) {
        expect(yml, contains(os));
      }
    });
  });
}
