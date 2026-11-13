import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../testing/fakes/plugin/fake_companion_plugin_server.dart';
import '../../tools/protocol_contract.dart';

// AC-22: HTTP security cases against the Dart fake
// AC-29: stream contract cases against the Dart fake
// AC-42: the stream cases (array elements, the cap of 128) against the Dart fake

const _fixtures = 'testing/fixtures/protocol';

Future<List<CaseResult>> _run(
  FakeCompanionPluginServer server, {
  String scenario = 'default',
  bool pluginOnly = false,
  bool stream = false,
  bool http = true,
  bool live = false,
  bool requireFixtureAircraft = false,
  String fixtures = _fixtures,
}) => runContract(
  server.baseUri,
  scenario: scenario,
  includePluginOnly: pluginOnly,
  http: http,
  stream: stream,
  fixtureDir: fixtures,
  live: live,
  requireFixtureAircraft: requireFixtureAircraft,
);

String _failures(List<CaseResult> r) =>
    r.where((c) => c.failed).map((c) => '${c.name}: ${c.reason}').join('\n');

List<String> _skipped(List<CaseResult> r) =>
    r.where((c) => c.skipped).map((c) => c.name).toList();

void main() {
  late FakeCompanionPluginServer server;

  setUp(() async {
    server = await FakeCompanionPluginServer.start();
  });

  tearDown(() async {
    await server.close();
  });

  group('HTTP cases against the Dart fake', () {
    test('every default case passes', () async {
      final results = await _run(server);
      expect(results, isNotEmpty);
      expect(_failures(results), isEmpty);
    });

    test('no_checklist scenario passes', () async {
      server.useScenario('no_checklist');
      final results = await _run(server, scenario: 'no_checklist');
      expect(results.length, greaterThanOrEqualTo(2));
      expect(_failures(results), isEmpty);
    });

    test(
      'oversize scenario passes when plugin-only cases are included',
      () async {
        server.useScenario('oversize');
        final results = await _run(
          server,
          scenario: 'oversize',
          pluginOnly: true,
        );
        expect(results.map((r) => r.name), contains('checklist 413 oversize'));
        expect(_failures(results), isEmpty);
      },
    );

    test('plugin-only cases are skipped with --no-plugin-only', () async {
      server.useScenario('oversize');
      final results = await _run(server, scenario: 'oversize');
      expect(
        results.map((r) => r.name),
        isNot(contains('checklist 413 oversize')),
      );
    });
  });

  group('live mode (a real sim)', () {
    // Same icao, description and checklist text as the fixtures; the path,
    // generation and modification time are the sim's own.
    void loadSimAircraft() => server.loadAircraft(
      icao: 'C172',
      description: 'Cessna Skyhawk 172SP',
      aircraftPath: '/X-Plane 12/Aircraft/Test/Cessna_172SP.acf',
      checklistPath: '/X-Plane 12/Aircraft/Test/Cessna_172SP_clist.txt',
      checklistBytes: File('$_fixtures/checklist_sample.txt').readAsBytesSync(),
    );

    test('strict mode fails on the sim own path and generation', () async {
      loadSimAircraft();
      expect(_failures(await _run(server)), isNotEmpty);
    });

    test('live mode takes those values from the server', () async {
      loadSimAircraft();
      expect(_failures(await _run(server, live: true)), isEmpty);
    });

    test('the fixture aircraft skips nothing', () async {
      loadSimAircraft();
      final results = await _run(server, live: true);
      expect(_skipped(results), isEmpty);
    });

    test('a different aircraft skips the fixture cases, not fails', () async {
      loadSimAircraft();
      server.icao = 'B738';
      final results = await _run(server, live: true);
      expect(_failures(results), isEmpty);
      expect(
        _skipped(results),
        containsAll(['aircraft 200', 'checklist 200', 'HEAD checklist']),
      );
      expect(_skipped(results).length, 10);
      expect(
        results.firstWhere((r) => r.skipped).reason,
        contains('loaded: B738'),
      );
    });

    test('a different checklist on the fixture icao is skipped too', () async {
      server.loadAircraft(
        icao: 'C172',
        description: 'Cessna Skyhawk 172SP',
        aircraftPath: '/X-Plane 12/Aircraft/Test/Cessna_172SP.acf',
        checklistPath: '/X-Plane 12/Aircraft/Test/Cessna_172SP_clist.txt',
        checklistBytes: utf8.encode('sw_checklist:Other\nsw_item:A|B\n'),
      );
      final results = await _run(server, live: true);
      expect(_failures(results), isEmpty);
      expect(_skipped(results).length, 10);
    });

    test('the other cases still run when fixture cases are skipped', () async {
      loadSimAircraft();
      server.icao = 'B738';
      final results = await _run(server, live: true);
      expect(results.where((r) => r.passed && !r.skipped), isNotEmpty);
      expect(results.where((r) => r.name == 'hello 200').single.passed, isTrue);
    });

    test('--require-fixture-aircraft fails them instead', () async {
      loadSimAircraft();
      server.icao = 'B738';
      final results = await _run(
        server,
        live: true,
        requireFixtureAircraft: true,
      );
      expect(_skipped(results), isEmpty);
      expect(_failures(results), contains('aircraft 200'));
    });

    test('live stream case follows the generation', () async {
      loadSimAircraft();
      // The value a real sim would hold for the name live mode substitutes.
      // Without a simApi the range cases keep the fixture values.
      server.stream.setSignal('sim/cockpit/misc/barometer_setting', 29.92);
      final results = await _run(server, live: true, http: false, stream: true);
      expect(_failures(results), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('stream cases against the Dart fake', () {
    test('every stream case passes', () async {
      final results = await _run(server, http: false, stream: true);
      expect(results.length, greaterThanOrEqualTo(15));
      expect(_failures(results), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('failures are reported by case name', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('contract_fixtures');
      for (final f in Directory(_fixtures).listSync().whereType<File>()) {
        f.copySync('${tmp.path}/${f.uri.pathSegments.last}');
      }
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    test('a wrong status fails that case only', () async {
      final file = File('${tmp.path}/cases.json');
      final cases = (jsonDecode(file.readAsStringSync()) as List<Object?>)
          .cast<Map<String, Object?>>();
      (cases.firstWhere((c) => c['name'] == 'aircraft 200')['expect']!
              as Map<String, Object?>)['status'] =
          201;
      file.writeAsStringSync(jsonEncode(cases));
      final results = await _run(server, fixtures: tmp.path);
      final failed = results.where((r) => !r.passed).toList();
      expect(failed.map((r) => r.name), ['aircraft 200']);
      expect(failed.single.reason, contains('201'));
    });

    test('a wrong stream expectation fails that case only', () async {
      final file = File('${tmp.path}/stream_cases.json');
      final cases = (jsonDecode(file.readAsStringSync()) as List<Object?>)
          .cast<Map<String, Object?>>();
      final only = cases.firstWhere((c) => c['name'] == 'ping gets pong');
      ((only['steps']! as List<Object?>)[1]!
          as Map<String, Object?>)['expect'] = {
        'op': 'nope',
      };
      ((only['steps']! as List<Object?>)[1]!
              as Map<String, Object?>)['withinMs'] =
          300;
      file.writeAsStringSync(jsonEncode([only]));
      final results = await _run(
        server,
        http: false,
        stream: true,
        fixtures: tmp.path,
      );
      expect(results.single.name, 'stream: ping gets pong');
      expect(results.single.passed, isFalse);
    });

    test(
      'main exits non-zero on a failure and prints FAIL with the name',
      () async {
        final file = File('${tmp.path}/cases.json');
        final cases = (jsonDecode(file.readAsStringSync()) as List<Object?>)
            .cast<Map<String, Object?>>();
        (cases.first['expect']! as Map<String, Object?>)['status'] = 500;
        file.writeAsStringSync(jsonEncode(cases));
        final lines = <String>[];
        final code = await contractMain([
          server.baseUri.toString(),
          '--fixtures',
          tmp.path,
          '--no-plugin-only',
          '--http-only',
        ], out: lines.add);
        expect(code, 1);
        expect(
          lines.where((l) => l.startsWith('FAIL hello 200')),
          hasLength(1),
        );
        expect(lines.where((l) => l.startsWith('PASS ')), isNotEmpty);
      },
    );

    test('main exits zero when everything passes', () async {
      final code = await contractMain([
        server.baseUri.toString(),
        '--no-plugin-only',
        '--http-only',
      ], out: (_) {});
      expect(code, 0);
    });

    test('main without a url is a usage error', () async {
      expect(await contractMain([], out: (_) {}), 2);
    });
  });
}
