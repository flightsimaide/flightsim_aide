import 'dart:convert';
import 'dart:io';

import 'package:flightsim_aide/data/services/local/aircraft_file_name.dart';
import 'package:flightsim_aide/data/services/local/model/stored_progress.dart';
import 'package:flightsim_aide/data/services/local/progress_storage_service.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';

// AC-15: corrupt, truncated or unknown-version progress files are a miss

void main() {
  group('storage format 2', storageFormat2Tests);

  late Directory dir;
  late FileProgressStorageService storage;

  const path = 'Aircraft/Laminar Research/Cessna 172SP/Cessna_172SP.acf';

  const sample = StoredProgress(
    lastViewed: 'Before Start',
    runId: 'a1b2c3d4e5f60718',
    checklists: {
      'Before Start': StoredChecklistProgress(
        checked: [0, 2, 5],
        fingerprint: 'abc-6',
      ),
      'Taxi': StoredChecklistProgress(checked: [1], fingerprint: 'def-3'),
    },
  );

  File fileFor(String aircraftPath) => File(
    '${dir.path}${Platform.pathSeparator}${aircraftFileName(aircraftPath)}',
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('progress_storage_test');
    storage = FileProgressStorageService(dir);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('round trip', () {
    test('round trip including lastConnectedAt', () async {
      expect((await storage.write(path, sample)).isOk, isTrue);
      expect(await storage.read(path), sample);
    });

    test('missing file reads as null', () async {
      expect(await storage.read(path), isNull);
    });

    test('indexes are written sorted', () async {
      await storage.write(
        path,
        const StoredProgress(
          checklists: {
            'A': StoredChecklistProgress(checked: [5, 1, 3], fingerprint: 'f'),
          },
        ),
      );
      final json = jsonDecode(fileFor(path).readAsStringSync()) as Map;
      expect(((json['checklists'] as Map)['A'] as Map)['checked'], [1, 3, 5]);
    });

    test('file without a run id reads as null run id', () async {
      await storage.write(
        path,
        const StoredProgress(lastViewed: 'A', checklists: {}),
      );
      expect((await storage.read(path))!.runId, isNull);
    });

    test('different aircraft use different files', () async {
      await storage.write(path, sample);
      await storage.write('other.acf', const StoredProgress(lastViewed: 'X'));
      expect((await storage.read(path))!.lastViewed, 'Before Start');
      expect((await storage.read('other.acf'))!.lastViewed, 'X');
      expect(dir.listSync(), hasLength(2));
    });

    test('the file name holds no character of the path', () async {
      await storage.write(path, sample);
      final name = dir.listSync().single.uri.pathSegments.last;
      expect(name, matches(RegExp(r'^[0-9a-f]{16}\.json$')));
    });

    test('a record for another path in the same file is ignored', () async {
      await storage.write(path, sample);
      fileFor(path).copySync(fileFor('other.acf').path);
      expect(await storage.read('other.acf'), isNull);
    });
  });

  group('write', () {
    test('write is atomic: no temp file is left behind', () async {
      await storage.write(path, sample);
      expect(
        dir.listSync().map((e) => e.path).where((p) => p.endsWith('.tmp')),
        isEmpty,
      );
    });

    test('a later write replaces the earlier one', () async {
      await storage.write(path, sample);
      await storage.write(path, const StoredProgress(lastViewed: 'Z'));
      expect((await storage.read(path))!.checklists, isEmpty);
    });

    test('delete removes the file', () async {
      await storage.write(path, sample);
      await storage.delete(path);
      expect(await storage.read(path), isNull);
      await storage.delete(path);
    });

    test('write into a path that is a file gives an error result', () async {
      final blocker = File('${dir.path}${Platform.pathSeparator}blocked')
        ..writeAsStringSync('x');
      final broken = FileProgressStorageService(Directory(blocker.path));
      final result = await broken.write(path, sample);
      expect(result, isA<Error<void>>());
      expect((result as Error<void>).error, isA<SourceReadFailure>());
    });
  });

  group('corruption', () {
    Future<void> put(String text) async {
      await storage.write(path, sample);
      fileFor(path).writeAsStringSync(text);
    }

    test('truncated file is a miss', () async {
      await storage.write(path, sample);
      final text = fileFor(path).readAsStringSync();
      fileFor(path).writeAsStringSync(text.substring(0, text.length ~/ 2));
      expect(await storage.read(path), isNull);
    });

    test('empty file is a miss', () async {
      await put('');
      expect(await storage.read(path), isNull);
    });

    test('non-JSON is a miss', () async {
      await put('not json at all');
      expect(await storage.read(path), isNull);
    });

    test('invalid UTF-8 is a miss', () async {
      await storage.write(path, sample);
      fileFor(path).writeAsBytesSync([0xff, 0xfe, 0xfd]);
      expect(await storage.read(path), isNull);
    });

    test('unknown version is a miss', () async {
      await put(
        jsonEncode({
          'version': 99,
          'aircraftPath': path,
          'checklists': <String, Object?>{},
        }),
      );
      expect(await storage.read(path), isNull);
    });

    test('wrong shape (indexes as strings) is a miss', () async {
      await put(
        jsonEncode({
          'version': 1,
          'aircraftPath': path,
          'checklists': {
            'A': {
              'checked': ['1', '2'],
              'fingerprint': 'f',
            },
          },
        }),
      );
      expect(await storage.read(path), isNull);
    });

    test('negative index is a miss', () async {
      await put(
        jsonEncode({
          'version': 1,
          'aircraftPath': path,
          'checklists': {
            'A': {
              'checked': [-1],
              'fingerprint': 'f',
            },
          },
        }),
      );
      expect(await storage.read(path), isNull);
    });

    test('checklists that are not an object are a miss', () async {
      await put(
        jsonEncode({'version': 1, 'aircraftPath': path, 'checklists': []}),
      );
      expect(await storage.read(path), isNull);
    });

    test('run id of the wrong type is a miss', () async {
      await put(
        jsonEncode({
          'version': 1,
          'aircraftPath': path,
          'runId': 7,
          'checklists': <String, Object?>{},
        }),
      );
      expect(await storage.read(path), isNull);
    });

    test('a non-object top level is a miss', () async {
      await put('[1,2,3]');
      expect(await storage.read(path), isNull);
    });
  });

  test('no domain imports', () {
    final text = File('lib/data/services/local/progress_storage_service.dart')
        .readAsStringSync();
    expect(text, isNot(contains('domain/')));
  });
}

// AC-43: storage format 2 with the auto set; version 1 still loads
void storageFormat2Tests() {
  late Directory dir;
  late FileProgressStorageService storage;
  const path = 'Aircraft/Laminar Research/Cessna 172SP/Cessna_172SP.acf';
  File file() =>
      File('${dir.path}${Platform.pathSeparator}${aircraftFileName(path)}');

  setUp(() {
    dir = Directory.systemTemp.createTempSync('progress_storage_v2_test');
    storage = FileProgressStorageService(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('version 2 round trip keeps the sets sorted', () async {
    const data = StoredProgress(
      runId: 'r',
      checklists: {
        'A': StoredChecklistProgress(
          checked: [1, 3],
          autoChecked: [3],
          disagreed: [1],
          fingerprint: 'f',
        ),
      },
    );
    await storage.write(path, data);
    final json = jsonDecode(file().readAsStringSync()) as Map;
    expect(json['version'], 4);
    expect(await storage.read(path), data);
  });

  test('a real version 1 file loads with the sets empty', () async {
    final text = File(
      '${Directory.current.path}/testing/fixtures/progress/version1.json',
    ).readAsStringSync();
    file().writeAsStringSync(text);
    final read = await storage.read(path);
    expect(read, isNotNull);
    expect(read!.checklists['Before Start']!.checked, [0, 2, 5]);
    expect(read.checklists['Before Start']!.autoChecked, isEmpty);
    expect(read.checklists['Before Start']!.disagreed, isEmpty);
    expect(read.runId, 'a1b2c3d4e5f60718');
  });

  test('an unknown version is no saved progress', () async {
    file().writeAsStringSync(
      '{"version":5,"aircraftPath":"$path","lastViewed":null,"runId":null,"checklists":{}}',
    );
    expect(await storage.read(path), isNull);
  });

  test('a bad set in version 2 is no saved progress', () async {
    for (final bad in ['"x"', '[-1]', '[1.5]', '["a"]', '{}']) {
      file().writeAsStringSync(
        '{"version":2,"aircraftPath":"$path","lastViewed":null,"runId":null,'
        '"checklists":{"A":{"checked":[0],"fingerprint":"f","autoChecked":$bad}}}',
      );
      expect(await storage.read(path), isNull, reason: bad);
      file().writeAsStringSync(
        '{"version":2,"aircraftPath":"$path","lastViewed":null,"runId":null,'
        '"checklists":{"A":{"checked":[0],"fingerprint":"f","disagreed":$bad}}}',
      );
      expect(await storage.read(path), isNull, reason: bad);
    }
  });

  test('an old manuallyUnchecked entry is ignored, even a damaged one', () async {
    for (final old in ['[0,2]', '"x"', '[-1]']) {
      file().writeAsStringSync(
        '{"version":4,"aircraftPath":"$path","lastViewed":null,"runId":null,'
        '"checklists":{"A":{"checked":[0],"fingerprint":"f","manuallyUnchecked":$old}}}',
      );
      final read = await storage.read(path);
      expect(read!.checklists['A']!.checked, [0], reason: old);
    }
  });

  test('a corrupt file is no saved progress', () async {
    file().writeAsStringSync('{"version":2,"check');
    expect(await storage.read(path), isNull);
  });
}
