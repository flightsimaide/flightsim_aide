import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository_impl.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ChecklistProgressRepositoryImpl repo;
  setUp(() => repo = ChecklistProgressRepositoryImpl());

  test('starts empty', () {
    expect(repo.current.checked, isEmpty);
  });

  test('toggle updates current', () {
    repo.toggle('A', 1);
    expect(repo.current.isChecked('A', 1), isTrue);
    repo.toggle('A', 1);
    expect(repo.current.isChecked('A', 1), isFalse);
  });

  test('toggle emits new progress', () async {
    final future = repo.progress.first;
    repo.toggle('A', 0);
    expect((await future).isChecked('A', 0), isTrue);
  });

  test('reset clears one checklist', () {
    repo
      ..toggle('A', 0)
      ..toggle('B', 0)
      ..reset('A');
    expect(repo.current.isChecked('A', 0), isFalse);
    expect(repo.current.isChecked('B', 0), isTrue);
  });

  test('resetAll clears everything and emits', () async {
    repo
      ..toggle('A', 0)
      ..toggle('B', 0);
    final future = repo.progress.first;
    repo.resetAll();
    expect(await future, ChecklistProgress());
    expect(repo.current.checked, isEmpty);
  });

  test('current is already updated when the stream event arrives', () async {
    final seen = <bool>[];
    repo.progress.listen((p) => seen.add(identical(p, repo.current)));
    repo.toggle('A', 0);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [true]);
  });

  group('stream behavior', () {
    test('two listeners both receive', () async {
      final a = repo.progress.first;
      final b = repo.progress.first;
      repo.toggle('A', 0);
      expect((await a).isChecked('A', 0), isTrue);
      expect((await b).isChecked('A', 0), isTrue);
    });

    test('late listener gets only later events', () async {
      repo.toggle('A', 0);
      final events = <ChecklistProgress>[];
      repo.progress.listen(events.add);
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      repo.toggle('A', 1);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
    });

    test('dispose completes the stream', () async {
      final done = repo.progress.toList();
      await repo.dispose();
      expect(await done, isEmpty);
    });

    test('calling toggle after dispose does not throw', () async {
      await repo.dispose();
      expect(() => repo.toggle('A', 0), returnsNormally);
    });
  });
}
