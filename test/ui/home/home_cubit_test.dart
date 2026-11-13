import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flightsim_aide/domain/models/checklist/attach_outcome.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/ui/home/cubit/home_cubit.dart';
import 'package:flightsim_aide/ui/home/cubit/home_state.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_checklist_progress_repository.dart';
import '../../../testing/fakes/repositories/fake_checklist_repository.dart';

// AC-21: file source attaches without an aircraft

final _doc = ChecklistDocument(
  checklists: const [],
  warnings: const [],
  sourceName: 'a.txt',
);

void main() {
  late FakeChecklistRepository repository;
  late FakeChecklistProgressRepository progress;

  HomeCubit build(List<Result<ChecklistDocument>> results) {
    repository = FakeChecklistRepository(loadResults: results);
    progress = FakeChecklistProgressRepository();
    return HomeCubit(
      checklistRepository: repository,
      progressRepository: progress,
    );
  }

  tearDown(() => repository.dispose());

  group('load success', () {
    blocTest<HomeCubit, HomeState>(
      'load emits [Loading, Loaded]',
      build: () => build([Ok(_doc)]),
      act: (c) => c.load(),
      expect: () => [const HomeLoading(), HomeLoaded(_doc)],
    );

    blocTest<HomeCubit, HomeState>(
      'repository.load called once',
      build: () => build([Ok(_doc)]),
      act: (c) => c.load(),
      verify: (_) => expect(repository.loadCount, 1),
    );

    blocTest<HomeCubit, HomeState>(
      'file source attaches without aircraft',
      build: () => build([Ok(_doc)]),
      act: (c) => c.load(),
      verify: (_) {
        expect(progress.attachCalls, hasLength(1));
        expect(progress.attachCalls.single.$1, _doc);
        expect(progress.attachCalls.single.$2, isNull);
      },
    );

    blocTest<HomeCubit, HomeState>(
      'resetAll is no longer called directly',
      build: () => build([Ok(_doc)]),
      act: (c) => c.load(),
      verify: (_) => expect(progress.resetAllCount, 0),
    );

    test('attach runs before HomeLoaded is emitted', () async {
      final cubit = build([Ok(_doc)]);
      int? attachesWhenLoaded;
      final sub = cubit.stream.listen((s) {
        if (s is HomeLoaded) attachesWhenLoaded = progress.attachCalls.length;
      });
      await cubit.load();
      await Future<void>.delayed(Duration.zero);
      expect(attachesWhenLoaded, 1);
      await sub.cancel();
      await cubit.close();
    });

    blocTest<HomeCubit, HomeState>(
      'a silent restore loads without opening the list',
      build: () {
        final c = build([Ok(_doc)]);
        progress.forcedOutcome = const AttachRestored('Taxi');
        return c;
      },
      act: (c) => c.load(),
      expect: () => [const HomeLoading(), HomeLoaded(_doc)],
    );

    blocTest<HomeCubit, HomeState>(
      'needsPrompt emits HomePromptRestore',
      build: () {
        final c = build([Ok(_doc)]);
        progress.forcedOutcome = const AttachNeedsPrompt();
        return c;
      },
      act: (c) => c.load(),
      expect: () => [const HomeLoading(), HomePromptRestore(_doc)],
    );

    blocTest<HomeCubit, HomeState>(
      'answering the prompt loads the document',
      build: () {
        final c = build([Ok(_doc)]);
        progress.forcedOutcome = const AttachNeedsPrompt();
        return c;
      },
      act: (c) async {
        await c.load();
        await c.answerPrompt(useSaved: false);
      },
      skip: 2,
      expect: () => [HomeLoaded(_doc)],
      verify: (_) => expect(progress.promptAnswers, [false]),
    );

    blocTest<HomeCubit, HomeState>(
      'using the saved progress asks the home screen to open the list',
      build: () {
        final c = build([Ok(_doc)]);
        progress.forcedOutcome = const AttachNeedsPrompt();
        return c;
      },
      act: (c) async {
        await c.load();
        progress.setLastViewed('Taxi');
        await c.answerPrompt(useSaved: true);
      },
      skip: 2,
      expect: () => [HomeLoaded(_doc, openLast: 'Taxi', openList: true)],
    );

    blocTest<HomeCubit, HomeState>(
      'answering without a prompt does nothing',
      build: () => build([Ok(_doc)]),
      act: (c) => c.answerPrompt(useSaved: true),
      expect: () => <HomeState>[],
    );
  });

  group('load failure and cancel', () {
    blocTest<HomeCubit, HomeState>(
      'read failure shows message',
      build: () => build([Error(SourceReadFailure('cannot read'))]),
      act: (c) => c.load(),
      expect: () => [const HomeLoading(), const HomeFailure('cannot read')],
    );

    blocTest<HomeCubit, HomeState>(
      'parse failure shows message',
      build: () => build([Error(ParseFailure('bad file'))]),
      act: (c) => c.load(),
      expect: () => [const HomeLoading(), const HomeFailure('bad file')],
    );

    blocTest<HomeCubit, HomeState>(
      'cancel returns to Initial with no failure',
      build: () => build([Error(SourceCancelled())]),
      act: (c) => c.load(),
      expect: () => [const HomeLoading(), const HomeInitial()],
    );

    blocTest<HomeCubit, HomeState>(
      'cancel never emits HomeFailure',
      build: () => build([Error(SourceCancelled())]),
      act: (c) => c.load(),
      verify: (c) => expect(c.state, isNot(isA<HomeFailure>())),
    );

    blocTest<HomeCubit, HomeState>(
      'attach NOT called after a failed load',
      build: () => build([Error(ParseFailure('bad'))]),
      act: (c) => c.load(),
      verify: (_) => expect(progress.attachCalls, isEmpty),
    );

    blocTest<HomeCubit, HomeState>(
      'attach NOT called after a cancel',
      build: () => build([Error(SourceCancelled())]),
      act: (c) => c.load(),
      verify: (_) => expect(progress.attachCalls, isEmpty),
    );
  });

  group('dismissError', () {
    blocTest<HomeCubit, HomeState>(
      'dismissError clears failure',
      build: () => build([Error(ParseFailure('bad'))]),
      act: (c) async {
        await c.load();
        c.dismissError();
      },
      expect: () => [
        const HomeLoading(),
        const HomeFailure('bad'),
        const HomeInitial(),
      ],
    );

    blocTest<HomeCubit, HomeState>(
      'dismissError in Initial emits nothing',
      build: () => build([Ok(_doc)]),
      act: (c) => c.dismissError(),
      expect: () => <HomeState>[],
    );

    blocTest<HomeCubit, HomeState>(
      'dismissError in Loaded emits nothing',
      build: () => build([Ok(_doc)]),
      act: (c) async {
        await c.load();
        c.dismissError();
      },
      expect: () => [const HomeLoading(), HomeLoaded(_doc)],
    );

    test('dismissError in Loading emits nothing', () async {
      final cubit = build([Ok(_doc)]);
      final gate = Completer<void>();
      repository.loadGate = gate.future;
      final states = <HomeState>[];
      final sub = cubit.stream.listen(states.add);
      final pending = cubit.load();
      await Future<void>.delayed(Duration.zero);
      cubit.dismissError();
      await Future<void>.delayed(Duration.zero);
      expect(states, [const HomeLoading()]);
      gate.complete();
      await pending;
      await sub.cancel();
      await cubit.close();
    });

    blocTest<HomeCubit, HomeState>(
      'a load after dismissError works normally',
      build: () => build([Error(ParseFailure('bad')), Ok(_doc)]),
      act: (c) async {
        await c.load();
        c.dismissError();
        await c.load();
      },
      expect: () => [
        const HomeLoading(),
        const HomeFailure('bad'),
        const HomeInitial(),
        const HomeLoading(),
        HomeLoaded(_doc),
      ],
    );
  });

  group('double-tap protection', () {
    test('second load while loading is ignored', () async {
      final cubit = build([Ok(_doc)]);
      final gate = Completer<void>();
      repository.loadGate = gate.future;
      final first = cubit.load();
      await Future<void>.delayed(Duration.zero);
      await cubit.load();
      gate.complete();
      await first;
      expect(repository.loadCount, 1);
      expect(progress.attachCalls, hasLength(1));
      await cubit.close();
    });
  });
}
