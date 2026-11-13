import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _dir = 'testing/fixtures/protocol';

Object? _json(String name) =>
    jsonDecode(File('$_dir/$name').readAsStringSync());

Map<String, Object?> _map(String name) => _json(name)! as Map<String, Object?>;

List<Map<String, Object?>> _list(String name) =>
    (_json(name)! as List<Object?>).cast<Map<String, Object?>>();

void main() {
  group('golden json', () {
    for (final f in [
      'hello.json',
      'aircraft_with_checklist.json',
      'aircraft_no_checklist.json',
      'error_404.json',
      'cases.json',
      'stream_cases.json',
      'stream_values.json',
    ]) {
      test('$f parses', () {
        expect(() => _json(f), returnsNormally);
      });
    }

    test('golden bodies are compact with no newline', () {
      for (final f in [
        'aircraft_with_checklist.json',
        'aircraft_no_checklist.json',
        'hello.json',
        'error_404.json',
      ]) {
        final text = File('$_dir/$f').readAsStringSync();
        expect(text, isNot(contains('\n')), reason: f);
        expect(text, isNot(contains(': ')), reason: f);
      }
    });

    test('checklist numbers in the aircraft json give the etag in cases', () {
      final a = _map('aircraft_with_checklist.json');
      final bytes = File('$_dir/checklist_sample.txt').readAsBytesSync();
      expect(a['checklistSize'], bytes.length);
      final etag = '"${a['checklistModified']}-${a['checklistSize']}"';
      final ok = _list('cases.json')
          .firstWhere((c) => c['name'] == 'checklist 200');
      final headers =
          (ok['expect']! as Map<String, Object?>)['headers']!
              as Map<String, Object?>;
      expect(headers['ETag'], etag);
    });

    test('no-checklist json has neither checklist field', () {
      final a = _map('aircraft_no_checklist.json');
      expect(a.containsKey('checklistModified'), isFalse);
      expect(a.containsKey('checklistSize'), isFalse);
      expect(a.containsKey('checklistPath'), isFalse);
      expect(a['aircraftPath'], isNotNull);
    });

    test('checklist sample is small and uses CRLF', () {
      final bytes = File('$_dir/checklist_sample.txt').readAsBytesSync();
      expect(bytes.length, lessThan(2000));
      final text = latin1.decode(bytes);
      expect(text, contains('\r\n'));
      expect(text.replaceAll('\r\n', ''), isNot(contains('\n')));
    });

    test('hello has the required fields', () {
      final h = _map('hello.json');
      expect(h['protocolVersion'], 1);
      expect(h['port'], 18086);
      expect(h['streamPath'], '/v1/stream');
    });
  });

  group('cases.json', () {
    final cases = _list('cases.json');

    test('every body file exists', () {
      for (final c in cases) {
        final f = (c['expect']! as Map<String, Object?>)['bodyFile'];
        if (f != null) {
          expect(File('$_dir/$f').existsSync(), isTrue, reason: '$f');
        }
      }
    });

    test('every case has a unique name, a method and a path', () {
      final names = <String>{};
      for (final c in cases) {
        expect(names.add(c['name']! as String), isTrue, reason: '${c['name']}');
        expect(c['method'], isA<String>());
        expect(c['path'], isA<String>());
      }
    });

    test('covers the required behaviours', () {
      final names = cases.map((c) => c['name']).toSet();
      expect(
        names,
        containsAll([
          'hello 200',
          'aircraft 200',
          'checklist 200',
          'checklist 304',
          'checklist 404 no checklist',
          'checklist 413 oversize',
          'POST aircraft 405',
          'PUT checklist 405',
          'DELETE hello 405',
          'unknown path 404',
          'traversal encoded 404',
          'checklist query ignored',
          'double slash 404',
          'HEAD aircraft',
          'plain GET stream 400',
        ]),
      );
    });

    test('413 is the only plugin-only case', () {
      final plugin = cases.where((c) => c['pluginOnly'] == true);
      expect(plugin.map((c) => c['name']), ['checklist 413 oversize']);
    });
  });

  group('stream_cases.json', () {
    final cases = _list('stream_cases.json');
    const ops = {
      'subscribe',
      'unsubscribe',
      'ping',
      'set',
      'subscribed',
      'error',
      'values',
      'hb',
      'pong',
      'frobnicate', // deliberately unknown, for the bad_request case
    };
    const codes = {'unknown_name', 'unsupported', 'bad_request', 'limit'};
    const stepKinds = {
      'send',
      'sendRaw',
      'expect',
      'expectNone',
      'collect',
      'subscribeMany',
      'wait',
      'openExtraClients',
      'expectUpgradeStatus',
    };

    test('every step is a known kind and uses known ops and codes', () {
      expect(cases, isNotEmpty);
      for (final c in cases) {
        final steps = (c['steps']! as List<Object?>)
            .cast<Map<String, Object?>>();
        for (final step in steps) {
          expect(
            step.keys.where(stepKinds.contains),
            hasLength(1),
            reason: '${c['name']}: $step',
          );
          for (final key in ['send', 'expect', 'expectNone']) {
            final f = step[key];
            if (f is Map<String, Object?>) {
              if (f.containsKey('op')) {
                expect(ops, contains(f['op']), reason: '${c['name']}');
              }
              if (f.containsKey('code')) {
                expect(codes, contains(f['code']), reason: '${c['name']}');
              }
            }
          }
        }
      }
    });

    test('names are unique', () {
      final names = cases.map((c) => c['name']).toList();
      expect(names.toSet(), hasLength(names.length));
    });
  });

  group('stream_values.json', () {
    test('serves on-ground and the generation of the aircraft golden', () {
      final v = _map('stream_values.json');
      final signals = v['signals']! as Map<String, Object?>;
      expect(signals['sim/flightmodel/failures/onground_any'], 1);
      expect(
        signals['flightsim_aide/aircraft_generation'],
        _map('aircraft_with_checklist.json')['generation'],
      );
      expect(v['unsupported'], isA<List<Object?>>());
    });
  });

  group('binary captures', () {
    test('becn_xp12.bin starts with BECN and a NUL', () {
      final b = File('$_dir/becn_xp12.bin').readAsBytesSync();
      expect(b, isNotEmpty);
      expect(b.sublist(0, 5), [0x42, 0x45, 0x43, 0x4e, 0x00]);
    });

    test('every .bin fixture is non-empty and has the BECN header', () {
      final bins = Directory(_dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.bin'));
      expect(bins, isNotEmpty);
      for (final f in bins) {
        final b = f.readAsBytesSync();
        expect(b, isNotEmpty, reason: f.path);
        expect(ascii.decode(b.sublist(0, 4)), 'BECN', reason: f.path);
      }
    });
  });
}
