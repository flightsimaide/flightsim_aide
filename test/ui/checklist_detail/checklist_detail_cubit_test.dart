import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_progress_repository.dart';
import 'package:flightsim_aide/data/repositories/checklist/checklist_repository.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_colour.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flightsim_aide/domain/models/checklist/continue_link.dart';
import 'package:flightsim_aide/ui/checklist_detail/cubit/checklist_detail_cubit.dart';
import 'package:flightsim_aide/ui/checklist_detail/cubit/checklist_detail_state.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../../testing/fakes/repositories/fake_checklist_repository.dart';

const _note = ChecklistItem(ChecklistItemType.note, 'header');
const _a = ChecklistItem(ChecklistItemType.check, 'Parking brake', 'SET');
const _b = ChecklistItem(ChecklistItemType.check, 'Batteries', 'ON');

ChecklistDocument _doc() => ChecklistDocument(
  checklists: [
    Checklist(
      name: 'prep',
      title: 'Prepare',
      items: [_note, _a, _b],
      continues: const [ContinueLink.named('taxi'), ContinueLink.next()],
    ),
    Checklist(name: 'other', title: 'Other', items: [_a]),
    Checklist(name: 'taxi', title: 'Taxi', items: [_b]),
    Checklist(name: 'notes', title: 'Notes only', items: [_note]),
  ],
  warnings: const [],
  colours: const {'red': ChecklistColour('red', 1, 0, 0)},
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeChecklistRepository repository;
  late FakeChecklistProgressRepository progress;

  ChecklistDetailCubit build(String name, {ChecklistDocument? doc}) {
    repository = FakeChecklistRepository(current: doc);
    progress = FakeChecklistProgressRepository();
    return ChecklistDetailCubit(
      checklistName: name,
      checklistRepository: repository,
      progressRepository: progress,
    );
  }

  ChecklistDetailLoaded loaded(ChecklistDetailCubit c) =>
      c.state as ChecklistDetailLoaded;

  tearDown(() async {
    await repository.dispose();
    await progress.dispose();
  });

  group('last viewed', () {
    test('opening a checklist records last viewed', () async {
      final cubit = build('taxi', doc: _doc());
      cubit.load();
      expect(progress.lastViewed, 'taxi');
      await cubit.close();
    });

    test('a missing checklist records nothing', () async {
      final cubit = build('nope', doc: _doc());
      cubit.load();
      expect(progress.lastViewed, isNull);
      await cubit.close();
    });
  });

  group('load', () {
    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'rows match the checklist in order',
      build: () => build('prep', doc: _doc()),
      act: (c) => c.load(),
      verify: (c) {
        final rows = loaded(c).rows;
        expect(rows.map((r) => r.item), [_note, _a, _b]);
        expect(rows.map((r) => r.index), [0, 1, 2]);
      },
    );

    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'note rows have index and checked false',
      build: () => build('prep', doc: _doc()),
      act: (c) => c.load(),
      verify: (c) {
        final note = loaded(c).rows.first;
        expect(note.index, 0);
        expect(note.checked, isFalse);
      },
    );

    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'done and total exclude notes',
      build: () => build('prep', doc: _doc()),
      act: (c) => c.load(),
      verify: (c) {
        expect(loaded(c).total, 2);
        expect(loaded(c).done, 0);
      },
    );

    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'title is the checklist title',
      build: () => build('prep', doc: _doc()),
      act: (c) => c.load(),
      verify: (c) => expect(loaded(c).title, 'Prepare'),
    );

    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'palette and next checklists come from the document',
      build: () => build('prep', doc: _doc()),
      act: (c) => c.load(),
      verify: (c) {
        expect(loaded(c).colours.keys, ['red']);
        expect(loaded(c).next, const [
          NextChecklist(name: 'taxi', title: 'Taxi'),
          NextChecklist(name: 'other', title: 'Other'),
        ]);
      },
    );

    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'repository.load is never called',
      build: () => build('prep', doc: _doc()),
      act: (c) => c.load(),
      verify: (_) => expect(repository.loadCount, 0),
    );
  });

  group('unknown checklist', () {
    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'unknown name gives Failure',
      build: () => build('nope', doc: _doc()),
      act: (c) => c.load(),
      expect: () => [const ChecklistDetailFailure('Checklist not found')],
    );

    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'null document gives Failure',
      build: () => build('prep'),
      act: (c) => c.load(),
      expect: () => [const ChecklistDetailFailure('Checklist not found')],
    );

    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'a new document without the checklist gives Failure',
      build: () => build('prep', doc: _doc()),
      act: (c) async {
        c.load();
        repository.emit(
          ChecklistDocument(checklists: const [], warnings: const []),
        );
        await _settle();
      },
      verify: (c) =>
          expect(c.state, const ChecklistDetailFailure('Checklist not found')),
    );
  });

  group('toggle', () {
    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'toggle on a check row calls the repository once',
      build: () => build('prep', doc: _doc()),
      act: (c) {
        c.load();
        c.toggle(1);
      },
      verify: (_) => expect(progress.toggleCalls, [('prep', 1)]),
    );

    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'toggle on a note row does nothing',
      build: () => build('prep', doc: _doc()),
      act: (c) {
        c.load();
        c.toggle(0);
      },
      verify: (_) => expect(progress.toggleCalls, isEmpty),
    );

    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'toggle out of range does nothing',
      build: () => build('prep', doc: _doc()),
      act: (c) {
        c.load();
        c.toggle(3);
        c.toggle(-1);
      },
      verify: (_) => expect(progress.toggleCalls, isEmpty),
    );

    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'toggle before the checklist is found does nothing',
      build: () => build('nope', doc: _doc()),
      act: (c) {
        c.load();
        c.toggle(0);
      },
      verify: (_) => expect(progress.toggleCalls, isEmpty),
    );

    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'state shows row checked after toggle',
      build: () => build('prep', doc: _doc()),
      act: (c) async {
        c.load();
        c.toggle(1);
        await _settle();
      },
      verify: (c) {
        expect(loaded(c).rows[1].checked, isTrue);
        expect(loaded(c).rows[2].checked, isFalse);
        expect(loaded(c).done, 1);
      },
    );

    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'toggle again unchecks',
      build: () => build('prep', doc: _doc()),
      act: (c) async {
        c.load();
        c.toggle(1);
        await _settle();
        c.toggle(1);
        await _settle();
      },
      verify: (c) {
        expect(loaded(c).rows[1].checked, isFalse);
        expect(loaded(c).done, 0);
      },
    );
  });

  group('reset', () {
    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'reset clears checks in state',
      build: () => build('prep', doc: _doc()),
      act: (c) async {
        c.load();
        c.toggle(1);
        c.toggle(2);
        await _settle();
        c.reset();
        await _settle();
      },
      verify: (c) {
        expect(loaded(c).done, 0);
        expect(loaded(c).rows.any((r) => r.checked), isFalse);
      },
    );

    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'reset leaves other checklists state alone',
      build: () => build('prep', doc: _doc()),
      act: (c) async {
        progress.toggle('other', 0);
        c.load();
        c.toggle(1);
        await _settle();
        c.reset();
        await _settle();
      },
      verify: (_) {
        expect(progress.resetCalls, ['prep']);
        expect(progress.current.isChecked('other', 0), isTrue);
        expect(progress.current.isChecked('prep', 1), isFalse);
      },
    );
  });

  group('completion', () {
    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'becomes complete after the last check',
      build: () => build('prep', doc: _doc()),
      act: (c) async {
        c.load();
        c.toggle(1);
        await _settle();
        expect(loaded(c).isComplete, isFalse);
        c.toggle(2);
        await _settle();
      },
      verify: (c) => expect(loaded(c).isComplete, isTrue),
    );

    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'stops being complete after one uncheck',
      build: () => build('prep', doc: _doc()),
      act: (c) async {
        c.load();
        c.toggle(1);
        c.toggle(2);
        await _settle();
        c.toggle(2);
        await _settle();
      },
      verify: (c) => expect(loaded(c).isComplete, isFalse),
    );

    blocTest<ChecklistDetailCubit, ChecklistDetailState>(
      'notes-only checklist never complete',
      build: () => build('notes', doc: _doc()),
      act: (c) => c.load(),
      verify: (c) {
        expect(loaded(c).total, 0);
        expect(loaded(c).isComplete, isFalse);
      },
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

    test('close cancels the progress and changes subscriptions', () async {
      final cubit = ChecklistDetailCubit(
        checklistName: 'prep',
        checklistRepository: checklists,
        progressRepository: progresses,
      )..load();
      expect(checklists.controller.hasListener, isTrue);
      expect(progresses.controller.hasListener, isTrue);
      await cubit.close();
      expect(checklists.controller.hasListener, isFalse);
      expect(progresses.controller.hasListener, isFalse);
    });

    test('events after close do not throw', () async {
      final cubit = ChecklistDetailCubit(
        checklistName: 'prep',
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
  dynamic noSuchMethod(Invocation invocation) => null;

  final lastViewedCalls = <String>[];

  @override
  void setLastViewed(String checklistName) =>
      lastViewedCalls.add(checklistName);

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

  @override
  bool isManual(String checklistName) => false;

  @override
  void setManual(String checklistName, {required bool manual}) {}
}
