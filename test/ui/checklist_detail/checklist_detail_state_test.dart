import 'package:flightsim_aide/domain/models/checklist/checklist_colour.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/ui/checklist_detail/cubit/checklist_detail_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _item = ChecklistItem(ChecklistItemType.check, 'Brake', 'SET');

ChecklistDetailLoaded _loaded({
  String title = 'T',
  bool checked = false,
  int done = 0,
  Map<String, ChecklistColour> colours = const {},
  List<NextChecklist> next = const [],
}) => ChecklistDetailLoaded(
  title: title,
  rows: [ChecklistDetailRow(index: 0, item: _item, checked: checked)],
  done: done,
  total: 1,
  isComplete: false,
  colours: colours,
  next: next,
);

void main() {
  group('ChecklistDetailRow', () {
    test('equality covers index, item and checked', () {
      const row = ChecklistDetailRow(index: 0, item: _item, checked: false);
      expect(
        row,
        const ChecklistDetailRow(index: 0, item: _item, checked: false),
      );
      expect(
        row,
        isNot(const ChecklistDetailRow(index: 1, item: _item, checked: false)),
      );
      expect(
        row,
        isNot(const ChecklistDetailRow(index: 0, item: _item, checked: true)),
      );
    });
  });

  group('ChecklistDetailState', () {
    test('Loading equals Loading', () {
      expect(const ChecklistDetailLoading(), const ChecklistDetailLoading());
    });

    test('Loaded has value equality', () {
      expect(_loaded(), _loaded());
      expect(_loaded(), isNot(_loaded(title: 'U')));
      expect(_loaded(), isNot(_loaded(checked: true)));
      expect(_loaded(), isNot(_loaded(done: 1)));
      expect(
        _loaded(),
        isNot(_loaded(colours: const {'red': ChecklistColour('red', 1, 0, 0)})),
      );
      expect(
        _loaded(),
        isNot(
          _loaded(
            next: const [NextChecklist(name: 'n', title: 'N')],
          ),
        ),
      );
    });

    test('Failure has value equality', () {
      expect(
        const ChecklistDetailFailure('x'),
        const ChecklistDetailFailure('x'),
      );
      expect(
        const ChecklistDetailFailure('x'),
        isNot(const ChecklistDetailFailure('y')),
      );
    });
  });
}
