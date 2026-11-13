import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// AC-25: the architecture gates pass.

Future<ProcessResult?> runScript(String script) async {
  try {
    return await Process.run('bash', ['tools/$script']);
  } on ProcessException {
    return null;
  }
}

void main() {
  for (final script in [
    'check_layers.sh',
    'check_structure.sh',
    'check_temporary_isolation.sh',
  ]) {
    test('$script passes', () async {
      final result = await runScript(script);
      if (result == null) {
        markTestSkipped('bash is not available');
        return;
      }
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    });
  }

  test('no dart:io or http use outside data/services and the config composition root', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll(r'\', '/');
      if (path.contains('lib/data/services/') || path.contains('lib/config/')) {
        continue;
      }
      final text = entity.readAsStringSync();
      if (RegExp(r"import 'package:http/|import 'dart:io'").hasMatch(text)) {
        hits.add(path);
      }
    }
    expect(hits, isEmpty);
  });
}
