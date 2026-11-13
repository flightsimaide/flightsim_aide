import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flightsim_aide/domain/models/checklist/continue_link.dart';
import 'package:flightsim_aide/ui/checklist_list/cubit/checklist_list_cubit.dart';
import 'package:flightsim_aide/ui/checklist_list/cubit/checklist_list_state.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../../testing/fakes/repositories/fake_checklist_repository.dart';

const _check = ChecklistItemType.check;

Checklist _list(
  String name,
  int checks, {
  List<ContinueLink> continues = const [],
}) => Checklist(
  name: name,
  title: name.toUpperCase(),
  items: [
    const ChecklistItem(ChecklistItemType.note, 'header'),
    for (var i = 0; i < checks; i++) ChecklistItem(_check, 'item $i'),
  ],
  continues: continues,
);

ChecklistDocument _doc({
  List<Checklist>? checklists,
  List<String> warnings = const [],
  String sourceName = 'a.txt',
}) => ChecklistDocument(
  checklists: checklists ?? [_list('a', 2), _list('b', 1)],
  warnings: warnings,
  sourceName: sourceName,
);

ChecklistSummary _sum(String name, int done, int total) => ChecklistSummary(
  name: name,
  title: name.toUpperCase(),
  done: done,
  total: total,
  isComplete: total > 0 && done == total,
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeChecklistRepository repository;
  late FakeChecklistProgressRepository progress;

  ChecklistListCubit build([ChecklistDocument? doc]) {
    repository = FakeChecklistRepository(current: doc ?? _doc());
    progress = FakeChecklistProgressRepository();
    return ChecklistListCubit(
      checklistRepository: repository,
      progressRepository: progress,
    );
  }

  tearDown(() async {
    await repository.dispose();
    await progress.dispose();
  });

  group('load', () {
    blocTest<ChecklistListCubit, ChecklistListState>(
      'emits Loaded with titles and 0/total',
      build: build,
      act: (c) => c.load(),
      expect: () => [
        ChecklistListLoaded(
          items: [_sum('a', 0, 2), _sum('b', 0, 1)],
          warnings: const [],
          sourceName: 'a.txt',
        ),
      ],
    );

    blocTest<ChecklistListCubit, ChecklistListState>(
      'repository.load is never called',
      build: build,
      act: (c) => c.load(),
      verify: (_) => expect(repository.loadCount, 0),
    );

    blocTest<ChecklistListCubit, ChecklistListState>(
      'warnings and sourceName come from the document',
      build: () => build(_doc(warnings: ['Line 3: x'], sourceName: 'z.txt')),
      act: (c) => c.load(),
      verify: (c) {
        final state = c.state as ChecklistListLoaded;
        expect(state.warnings, ['Line 3: x']);
        expect(state.sourceName, 'z.txt');
        expect(state.warningsDismissed, isFalse);
      },
    );

    blocTest<ChecklistListCubit, ChecklistListState>(
      'items are in flight order, not file order',
      build: () => build(
        _doc(
          checklists: [
            _list('landing', 1),
            _list(
              'takeoff',
              1,
              continues: const [ContinueLink.named('landing')],
            ),
          ],
        ),
      ),
      act: (c) => c.load(),
      verify: (c) {
        final state = c.state as ChecklistListLoaded;
        expect(state.items.map((s) => s.name), ['takeoff', 'landing']);
      },
    );

    blocTest<ChecklistListCubit, ChecklistListState>(
      'null current gives Failure',
      build: () {
        final cubit = build();
        repository.current = null;
        return cubit;
      },
      act: (c) => c.load(),
      expect: () => [const ChecklistListFailure('No checklist loaded')],
    );
  });

  group('live updates', () {
    blocTest<ChecklistListCubit, ChecklistListState>(
      'toggle in the progress repo emits updated done count',
      build: build,
      act: (c) async {
        c.load();
        progress.toggle('a', 1);
        await _settle();
      },
      skip: 1,
      expect: () => [
        ChecklistListLoaded(
          items: [_sum('a', 1, 2), _sum('b', 0, 1)],
          warnings: const [],
          sourceName: 'a.txt',
        ),
      ],
    );

    blocTest<ChecklistListCubit, ChecklistListState>(
      'reset emits 0',
      build: build,
      act: (c) async {
        c.load();
        progress.toggle('a', 1);
        await _settle();
        progress.reset('a');
        await _settle();
      },
      verify: (c) {
        final state = c.state as ChecklistListLoaded;
        expect(state.items.first, _sum('a', 0, 2));
      },
    );

    blocTest<ChecklistListCubit, ChecklistListState>(
      'completing a checklist sets isComplete',
      build: build,
      act: (c) async {
        c.load();
        progress.toggle('b', 1);
        await _settle();
      },
      verify: (c) {
        final state = c.state as ChecklistListLoaded;
        expect(state.items.last.isComplete, isTrue);
        expect(state.items.first.isComplete, isFalse);
      },
    );

    blocTest<ChecklistListCubit, ChecklistListState>(
      'new document on changes replaces the summaries',
      build: build,
      act: (c) async {
        c.load();
        repository.emit(
          _doc(checklists: [_list('x', 4)], sourceName: 'new.txt'),
        );
        await _settle();
      },
      verify: (c) {
        final state = c.state as ChecklistListLoaded;
        expect(state.items, [_sum('x', 0, 4)]);
        expect(state.sourceName, 'new.txt');
      },
    );

    blocTest<ChecklistListCubit, ChecklistListState>(
      'a null document on changes gives Failure',
      build: build,
      act: (c) async {
        c.load();
        repository.emit(null);
        await _settle();
      },
      verify: (c) =>
          expect(c.state, const ChecklistListFailure('No checklist loaded')),
    );

    test('a document arriving after a null load is picked up', () async {
      final cubit = build();
      repository.current = null;
      cubit.load();
      expect(cubit.state, isA<ChecklistListFailure>());
      repository.emit(_doc());
      await _settle();
      expect(cubit.state, isA<ChecklistListLoaded>());
      await cubit.close();
    });
  });

  group('dismissWarnings', () {
    blocTest<ChecklistListCubit, ChecklistListState>(
      'dismiss sets the flag',
      build: () => build(_doc(warnings: ['w'])),
      act: (c) {
        c.load();
        c.dismissWarnings();
      },
      verify: (c) =>
          expect((c.state as ChecklistListLoaded).warningsDismissed, isTrue),
    );

    blocTest<ChecklistListCubit, ChecklistListState>(
      'the flag survives progress updates',
      build: () => build(_doc(warnings: ['w'])),
      act: (c) async {
        c.load();
        c.dismissWarnings();
        progress.toggle('a', 1);
        await _settle();
      },
      verify: (c) =>
          expect((c.state as ChecklistListLoaded).warningsDismissed, isTrue),
    );

    blocTest<ChecklistListCubit, ChecklistListState>(
      'reloading a new document resets the flag to false',
      build: () => build(_doc(warnings: ['w'])),
      act: (c) async {
        c.load();
        c.dismissWarnings();
        repository.emit(_doc(warnings: ['other']));
        await _settle();
      },
      verify: (c) =>
          expect((c.state as ChecklistListLoaded).warningsDismissed, isFalse),
    );

    blocTest<ChecklistListCubit, ChecklistListState>(
      'dismiss outside Loaded emits nothing',
      build: build,
      act: (c) => c.dismissWarnings(),
      expect: () => <ChecklistListState>[],
    );
  });

  group('subscriptions', () {
    late _StubChecklistRepository checklists;
    late _StubProgressRepository progresses;

    setUp(() {
      checklists = _StubChecklistRepository(_doc());
      progresses = _StubProgressRepository();
    });

    tearDown(() async {
      await checklists.controller.close();
      await progresses.controller.close();
    });

    test('load subscribes to both streams', () async {
      final cubit = ChecklistListCubit(
        checklistRepository: checklists,
        progressRepository: progresses,
      )..load();
      expect(checklists.controller.hasListener, isTrue);
      expect(progresses.controller.hasListener, isTrue);
      await cubit.close();
    });

    test('calling load twice keeps a single subscription', () async {
      final cubit = ChecklistListCubit(
        checklistRepository: checklists,
        progressRepository: progresses,
      )..load();
      cubit.load();
      await cubit.close();
      expect(checklists.controller.hasListener, isFalse);
      expect(progresses.controller.hasListener, isFalse);
    });

    test('after close the fake streams have no listeners', () async {
      final cubit = ChecklistListCubit(
        checklistRepository: checklists,
        progressRepository: progresses,
      )..load();
      await cubit.close();
      expect(checklists.controller.hasListener, isFalse);
      expect(progresses.controller.hasListener, isFalse);
    });

    test('events after close do not throw', () async {
      final cubit = ChecklistListCubit(
        checklistRepository: checklists,
        progressRepository: progresses,
      )..load();
      await cubit.close();
      checklists.controller.add(_doc());
      progresses.controller.add(ChecklistProgress());
      await _settle();
    });
  });
}

class _StubChecklistRepository implements ChecklistRepository {
  _StubChecklistRepository(this.current);

  final controller = StreamController<ChecklistDocument?>.broadcast();

  @override
  ChecklistDocument? current;

  @override
  Stream<ChecklistDocument?> get changes => controller.stream;

  @override
  Future<Result<ChecklistDocument>> load() => throw UnimplementedError();
}

class _StubProgressRepository implements ChecklistProgressRepository {
  // The persistence members are not used by these tests.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final controller = StreamController<ChecklistProgress>.broadcast();

  @override
  ChecklistProgress current = ChecklistProgress();

  @override
  Stream<ChecklistProgress> get progress => controller.stream;

  @override
  void toggle(String checklistName, int itemIndex, {bool disagrees = false}) {}

  @override
  void autoCheck(
    String checklistName,
    Iterable<int> itemIndexes, {
    int? cursor,
  }) {}

  @override
  void reset(String checklistName) {}

  @override
  void resetAll() {}
}
