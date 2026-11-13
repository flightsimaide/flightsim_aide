import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flightsim_aide/ui/checklist_detail/cubit/checklist_detail_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final before = ChecklistProgress();

  test('the message is the simulation value for label and result', () {
    final w = TickWarning(
      index: 0,
      label: 'Gear',
      result: 'DOWN',
      before: before,
    );
    expect(w.message, 'The simulation value for Gear down is false.');
  });

  test('an item without a result leaves the result out', () {
    final w = TickWarning(index: 0, label: 'Gear', before: before);
    expect(w.message, 'The simulation value for Gear is false.');
  });
}
