// Runs the shared protocol cases against the C++ core (core_test_server).
// Skipped unless plugin/build/core_test_server has been built (see
// plugin/build.ps1), so the Dart gate does not depend on a C++ toolchain.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tools/protocol_contract.dart';

// AC-22: HTTP security cases against the plugin core
// AC-29: stream contract cases against the plugin core

String? _binary() {
  for (final p in [
    'plugin/build/core_test_server.exe',
    'plugin/build/core_test_server',
  ]) {
    if (File(p).existsSync()) return File(p).absolute.path;
  }
  return null;
}

Future<(Process, int)> _start(String binary, String scenario) async {
  final p = await Process.start(binary, [
    '--exit-on-stdin-close',
    '--bind',
    '127.0.0.1',
    '--scenario',
    scenario,
  ]);
  final line = await p.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .firstWhere((l) => l.startsWith('PORT='))
      .timeout(const Duration(seconds: 10));
  return (p, int.parse(line.substring(5)));
}

Future<void> _stop(Process p) async {
  await p.stdin.close();
  if (await p.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          p.kill();
          return -1;
        },
      ) !=
      0) {
    // A forced stop is fine for a test server.
  }
}

void main() {
  final binary = _binary();
  final skip = binary == null
      ? 'plugin/build/core_test_server is not built'
      : null;

  for (final scenario in ['default', 'no_checklist', 'oversize']) {
    test(
      'core_test_server passes every $scenario case',
      () async {
        final (process, port) = await _start(binary!, scenario);
        addTearDown(() => _stop(process));
        final results = await runContract(
          Uri.parse('http://127.0.0.1:$port'),
          scenario: scenario,
          stream: scenario == 'default',
        );
        expect(results, isNotEmpty);
        final failed = results
            .where((r) => !r.passed)
            .map((r) => '${r.name}: ${r.reason}');
        expect(failed, isEmpty);
        if (scenario == 'oversize') {
          expect(
            results.map((r) => r.name),
            contains('checklist 413 oversize'),
          );
        }
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
