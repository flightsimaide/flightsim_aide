import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flightsim_aide/ui/home/cubit/home_state.dart';
import 'package:flutter_test/flutter_test.dart';

ChecklistDocument _doc(String name) => ChecklistDocument(
  checklists: const [],
  warnings: const [],
  sourceName: name,
);

void main() {
  group('HomeState', () {
    test('states with equal data are equal', () {
      expect(const HomeInitial(), const HomeInitial());
      expect(const HomeLoading(), const HomeLoading());
      expect(HomeLoaded(_doc('a')), HomeLoaded(_doc('a')));
      expect(const HomeFailure('x'), const HomeFailure('x'));
      expect(HomeLoaded(_doc('a')), isNot(HomeLoaded(_doc('b'))));
      expect(const HomeInitial(), isNot(const HomeLoading()));
    });

    test('HomeFailure differs by message', () {
      expect(const HomeFailure('x'), isNot(const HomeFailure('y')));
    });
  });
}
