import 'dart:convert';
import 'dart:io';

import 'package:flightsim_aide/data/services/local/aircraft_file_name.dart';
import 'package:flightsim_aide/data/services/local/model/stored_progress.dart';
import 'package:flightsim_aide/data/services/local/progress_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Storage format 3 adds the cursor and the disagreed marks (D-71). Formats
// 1 and 2 still load, with the cursor at the top and no disagreed marks.

void main() {
  late Directory dir;
  late FileProgressStorageService storage;
  const path = 'Aircraft/Laminar Research/Cessna 172SP/Cessna_172SP.acf';

  File file() =>
      File('${dir.path}${Platform.pathSeparator}${aircraftFileName(path)}');

  void writeRaw(Map<String, Object?> checklist, {int version = 3}) {
    file().writeAsStringSync(
      jsonEncode({
        'version': version,
        'aircraftPath': path,
        'lastViewed': null,
        'runId': 'r',
        'checklists': {'A': checklist},
      }),
    );
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('progress_storage_v3_test');
    storage = FileProgressStorageService(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('version 3 is written and the cursor and marks round trip', () async {
    const data = StoredProgress(
      runId: 'r',
      checklists: {
        'A': StoredChecklistProgress(
          checked: [1, 3, 4],
          disagreed: [3, 1],
          cursor: 5,
          fingerprint: 'f',
        ),
      },
    );
    await storage.write(path, data);
    final json = jsonDecode(file().readAsStringSync()) as Map;
    expect(json['version'], 4);
    final entry = (json['checklists'] as Map)['A'] as Map;
    expect(entry['disagreed'], [1, 3], reason: 'written sorted');
    expect(entry['cursor'], 5);
    final read = (await storage.read(path))!.checklists['A']!;
    expect(read.cursor, 5);
    expect(read.disagreed, [1, 3]);
  });

  test('a version 2 file loads with the cursor at the top', () async {
    writeRaw({
      'checked': [0, 1],
      'autoChecked': [1],
      'manuallyUnchecked': <int>[],
      'fingerprint': 'f',
    }, version: 2); // an old key, ignored
    final read = (await storage.read(path))!.checklists['A']!;
    expect(read.checked, [0, 1]);
    expect(read.cursor, 0);
    expect(read.disagreed, isEmpty);
  });

  test('a version 1 file loads with the cursor at the top', () async {
    writeRaw({
      'checked': [2],
      'fingerprint': 'f',
    }, version: 1);
    final read = (await storage.read(path))!.checklists['A']!;
    expect(read.checked, [2]);
    expect(read.cursor, 0);
  });

  for (final damaged in <Object?>[
    'five',
    -3,
    2.5,
    true,
    [1],
  ]) {
    test('a damaged cursor ($damaged) falls back to the top', () async {
      writeRaw({
        'checked': [1],
        'cursor': damaged,
        'fingerprint': 'f',
      });
      final read = (await storage.read(path))!.checklists['A']!;
      expect(read.cursor, 0);
      expect(read.checked, [1], reason: 'the rest of the file is kept');
    });
  }

  test('a damaged disagreed list makes the file a miss', () async {
    writeRaw({
      'checked': [1],
      'disagreed': ['x'],
      'fingerprint': 'f',
    });
    expect(await storage.read(path), isNull);
  });

  test('an unknown version 5 is still a miss', () async {
    writeRaw({
      'checked': [1],
      'fingerprint': 'f',
    }, version: 5);
    expect(await storage.read(path), isNull);
  });
}
