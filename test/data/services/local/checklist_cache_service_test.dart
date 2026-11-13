import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flightsim_aide/data/services/local/checklist_cache_service.dart';
import 'package:flightsim_aide/data/services/local/model/cached_checklist.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late FileChecklistCacheService cache;

  const path = 'Aircraft/Laminar Research/Cessna 172SP/Cessna_172SP.acf';

  CachedChecklist entry({List<int>? bytes, int mtime = 1761206400123}) =>
      CachedChecklist(
        bytes: Uint8List.fromList(bytes ?? utf8.encode('sw_checklist:A\r\n')),
        checklistPath: 'Aircraft/Laminar Research/Cessna 172SP/clist.txt',
        mtime: mtime,
        size: (bytes ?? utf8.encode('sw_checklist:A\r\n')).length,
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('checklist_cache_test');
    cache = FileChecklistCacheService(dir);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  File fileFor(String aircraftPath) =>
      File('${dir.path}/${cache.fileNameFor(aircraftPath)}');

  test('round trip keeps bytes, path, mtime and size', () async {
    final original = entry(bytes: [0x73, 0xe9, 0xff, 0x0d, 0x0a, 0x00, 0x80]);
    expect((await cache.write(path, original)).isOk, isTrue);
    final read = await cache.read(path);
    expect(read, original);
    expect(read!.bytes, original.bytes);
    expect(read.checklistPath, original.checklistPath);
    expect(read.mtime, original.mtime);
    expect(read.size, original.size);
  });

  test('different aircraft paths use different files', () async {
    await cache.write(path, entry());
    await cache.write('Aircraft/Other/other.acf', entry(mtime: 5));
    expect(
      cache.fileNameFor(path),
      isNot(cache.fileNameFor('Aircraft/Other/other.acf')),
    );
    expect((await cache.read(path))!.mtime, 1761206400123);
    expect((await cache.read('Aircraft/Other/other.acf'))!.mtime, 5);
    expect(dir.listSync().length, 2);
  });

  test('same path overwrites', () async {
    await cache.write(path, entry(mtime: 1));
    await cache.write(path, entry(mtime: 2));
    expect((await cache.read(path))!.mtime, 2);
    expect(dir.listSync().length, 1);
  });

  test('read of a missing entry is null', () async {
    expect(await cache.read(path), isNull);
  });

  test('read from a directory that does not exist yet is null', () async {
    final missing = FileChecklistCacheService(Directory('${dir.path}/nope'));
    expect(await missing.read(path), isNull);
  });

  test('write creates the directory when it is missing', () async {
    final nested = FileChecklistCacheService(Directory('${dir.path}/a/b'));
    expect((await nested.write(path, entry())).isOk, isTrue);
    expect(await nested.read(path), isNotNull);
  });

  test('write is atomic (temp file is gone after success)', () async {
    await cache.write(path, entry());
    final names = dir.listSync().map((e) => e.uri.pathSegments.last).toList();
    expect(names.where((n) => n.endsWith('.tmp')), isEmpty);
    expect(names.length, 1);
  });

  test('file name contains no characters from the aircraft path', () {
    final name = cache.fileNameFor(path);
    expect(name, matches(RegExp(r'^[0-9a-f]{16}\.json$')));
    expect(
      cache.fileNameFor('a/b:c*d?e'),
      matches(RegExp(r'^[0-9a-f]{16}\.json$')),
    );
  });

  test('delete removes the entry and tolerates a missing one', () async {
    await cache.write(path, entry());
    await cache.delete(path);
    expect(await cache.read(path), isNull);
    await cache.delete(path);
  });

  group('corruption', () {
    Future<void> put(List<int> bytes) async {
      await cache.write(path, entry());
      await fileFor(path).writeAsBytes(bytes);
    }

    test('truncated entry is a miss', () async {
      await cache.write(path, entry());
      final file = fileFor(path);
      final bytes = await file.readAsBytes();
      await file.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
      expect(await cache.read(path), isNull);
    });

    test('empty file is a miss', () async {
      await put(const []);
      expect(await cache.read(path), isNull);
    });

    test('unknown version is a miss', () async {
      await cache.write(path, entry());
      final file = fileFor(path);
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      json['version'] = 99;
      await file.writeAsString(jsonEncode(json));
      expect(await cache.read(path), isNull);
    });

    test('garbage bytes are a miss', () async {
      await put([0xff, 0xfe, 0x00, 0x01, 0x02]);
      expect(await cache.read(path), isNull);
    });

    test('wrong shape is a miss', () async {
      await put(utf8.encode('{"version":1,"aircraftPath":5}'));
      expect(await cache.read(path), isNull);
      await put(utf8.encode('[1,2,3]'));
      expect(await cache.read(path), isNull);
    });

    test('an entry for another aircraft path is a miss', () async {
      await cache.write(path, entry());
      final file = fileFor(path);
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      json['aircraftPath'] = 'Aircraft/Other/other.acf';
      await file.writeAsString(jsonEncode(json));
      expect(await cache.read(path), isNull);
    });

    test('a corrupt entry is replaced on the next write', () async {
      await put([0xff, 0x00]);
      expect((await cache.write(path, entry(mtime: 9))).isOk, isTrue);
      expect((await cache.read(path))!.mtime, 9);
    });

    test('write failure returns an error result and does not throw', () async {
      final blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
      final broken = FileChecklistCacheService(
        Directory('${blocker.path}/sub'),
      );
      final result = await broken.write(path, entry());
      expect(result.errorOrNull, isA<SourceReadFailure>());
      expect(await broken.read(path), isNull);
    });
  });
}
