import 'dart:io';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository_impl.dart';
import 'package:flightsim_aide/data/services/checklist/model/raw_checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/services/fake_checklist_source_service.dart';

String fixture(String name) =>
    File('testing/fixtures/$name.txt').readAsStringSync();

FakeChecklistSourceService sourceWith(String text, {String name = 'f.txt'}) =>
    FakeChecklistSourceService(
      Ok(RawChecklistDocument(name: name, text: text)),
    );

class _ThrowingParser extends AircraftWorkflowParser {
  const _ThrowingParser();

  @override
  ChecklistDocument parse(String text) => throw StateError('parser exploded');
}

void main() {
  test('current is null before load', () {
    expect(ChecklistRepositoryImpl(source: sourceWith('')).current, isNull);
  });

  group('successful load', () {
    late FakeChecklistSourceService source;
    late ChecklistRepositoryImpl repo;
    late Result<ChecklistDocument> result;

    setUp(() async {
      source = sourceWith(fixture('minimal'), name: 'minimal.txt');
      repo = ChecklistRepositoryImpl(source: source);
      result = await repo.load();
    });

    test('returns Ok with 1 checklist', () {
      expect(result.valueOrNull!.checklists, hasLength(1));
    });

    test('sourceName equals raw name', () {
      expect(result.valueOrNull!.sourceName, 'minimal.txt');
    });

    test('current equals returned document', () {
      expect(repo.current, result.valueOrNull);
    });

    test('source called exactly once', () {
      expect(source.callCount, 1);
    });
  });

  group('changes stream', () {
    test('emits document after load', () async {
      final repo = ChecklistRepositoryImpl(
        source: sourceWith(fixture('minimal')),
      );
      final future = repo.changes.first;
      final result = await repo.load();
      expect(await future, result.valueOrNull);
    });

    test('two listeners both receive', () async {
      final repo = ChecklistRepositoryImpl(
        source: sourceWith(fixture('minimal')),
      );
      final a = repo.changes.first;
      final b = repo.changes.first;
      await repo.load();
      expect(await a, isNotNull);
      expect(await b, isNotNull);
    });

    test('two loads emit two events', () async {
      final repo = ChecklistRepositoryImpl(
        source: sourceWith(fixture('minimal')),
      );
      final events = <ChecklistDocument?>[];
      repo.changes.listen(events.add);
      await repo.load();
      await repo.load();
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(2));
    });

    test('failed load emits nothing', () async {
      final repo = ChecklistRepositoryImpl(source: sourceWith(''));
      final events = <ChecklistDocument?>[];
      repo.changes.listen(events.add);
      await repo.load();
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
    });
  });

  group('source errors pass through', () {
    test('SourceReadFailure is returned as-is', () async {
      final failure = SourceReadFailure('disk');
      final repo = ChecklistRepositoryImpl(
        source: FakeChecklistSourceService(Error(failure)),
      );
      expect((await repo.load()).errorOrNull, same(failure));
    });

    test('SourceCancelled is returned as the same type', () async {
      final repo = ChecklistRepositoryImpl(
        source: FakeChecklistSourceService(Error(SourceCancelled())),
      );
      expect((await repo.load()).errorOrNull, isA<SourceCancelled>());
    });

    test('current unchanged after failed load', () async {
      final source = sourceWith(fixture('minimal'));
      final repo = ChecklistRepositoryImpl(source: source);
      final first = (await repo.load()).valueOrNull;
      source.result = Error(SourceReadFailure('gone'));
      await repo.load();
      expect(repo.current, same(first));
    });
  });

  group('zero checklists is a failure', () {
    test('empty text gives ParseFailure', () async {
      final repo = ChecklistRepositoryImpl(source: sourceWith(''));
      expect((await repo.load()).errorOrNull, isA<ParseFailure>());
    });

    test('garbage text gives ParseFailure', () async {
      final repo = ChecklistRepositoryImpl(
        source: sourceWith('\u0000\u0001 not a checklist\nfoo bar'),
      );
      expect((await repo.load()).errorOrNull, isA<ParseFailure>());
    });

    test('message mentions "No checklists found"', () async {
      final repo = ChecklistRepositoryImpl(source: sourceWith(''));
      expect(
        (await repo.load()).errorOrNull!.message,
        contains('No checklists found'),
      );
    });

    test('current unchanged', () async {
      final repo = ChecklistRepositoryImpl(source: sourceWith(''));
      await repo.load();
      expect(repo.current, isNull);
    });

    test('previous good document survives a bad reload', () async {
      final source = sourceWith(fixture('minimal'));
      final repo = ChecklistRepositoryImpl(source: source);
      final first = (await repo.load()).valueOrNull;
      source.result = const Ok(RawChecklistDocument(name: 'bad', text: ''));
      expect((await repo.load()).isOk, isFalse);
      expect(repo.current, same(first));
    });
  });

  test('warnings are preserved (messy.txt)', () async {
    final repo = ChecklistRepositoryImpl(source: sourceWith(fixture('messy')));
    final result = await repo.load();
    expect(result.isOk, isTrue);
    expect(result.valueOrNull!.warnings, const [
      'Line 1: item before any checklist',
      'Line 4: unrecognized line',
      'Line 11: unknown keyword "bogus_keyword"',
      'Line 16: duplicate colour "red"; first definition kept',
      'Line 17: colour component out of range; clamped',
      'Line 18: bad colour definition',
      'Line 20: unknown colour "ghost"',
      'Line 13: checklist "Empty" has no items; dropped',
      'Line 22: continue target "Nowhere" not found',
    ]);
    expect(repo.current!.warnings, result.valueOrNull!.warnings);
  });

  group('parser exceptions contained', () {
    test(
      'a parser that throws becomes ParseFailure, not an exception',
      () async {
        final repo = ChecklistRepositoryImpl(
          source: sourceWith('x'),
          parser: const _ThrowingParser(),
        );
        expect((await repo.load()).errorOrNull, isA<ParseFailure>());
      },
    );

    test('repository.load() never throws', () async {
      final repo = ChecklistRepositoryImpl(
        source: sourceWith('x'),
        parser: const _ThrowingParser(),
      );
      await expectLater(repo.load(), completes);
    });
  });
}
