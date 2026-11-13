import 'package:flightsim_aide/ui/checklist_list/cubit/checklist_list_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _summary = ChecklistSummary(
  name: 'a',
  title: 'A',
  done: 1,
  total: 3,
  isComplete: false,
);

void main() {
  group('ChecklistSummary', () {
    test('summary equality', () {
      expect(
        _summary,
        const ChecklistSummary(
          name: 'a',
          title: 'A',
          done: 1,
          total: 3,
          isComplete: false,
        ),
      );
      expect(
        _summary,
        isNot(
          const ChecklistSummary(
            name: 'a',
            title: 'A',
            done: 2,
            total: 3,
            isComplete: false,
          ),
        ),
      );
    });
  });

  group('ChecklistListState', () {
    test('Loading is equal to Loading', () {
      expect(const ChecklistListLoading(), const ChecklistListLoading());
    });

    test('Loaded has value equality', () {
      ChecklistListLoaded loaded({
        List<String> warnings = const ['w'],
        String sourceName = 's.txt',
        bool dismissed = false,
      }) => ChecklistListLoaded(
        items: const [_summary],
        warnings: warnings,
        sourceName: sourceName,
        warningsDismissed: dismissed,
      );

      expect(loaded(), loaded());
      expect(loaded(), isNot(loaded(warnings: const [])));
      expect(loaded(), isNot(loaded(sourceName: 'other')));
      expect(loaded(), isNot(loaded(dismissed: true)));
    });

    test('Failure has value equality', () {
      expect(const ChecklistListFailure('x'), const ChecklistListFailure('x'));
      expect(
        const ChecklistListFailure('x'),
        isNot(const ChecklistListFailure('y')),
      );
    });

    test('different state kinds are not equal', () {
      expect(
        const ChecklistListLoading(),
        isNot(const ChecklistListFailure('x')),
      );
    });
  });
}
