import '../../models/checklist/checklist.dart';
import '../../models/checklist/checklist_item.dart';
import '../../models/flight_sim/dataref.dart';

/// The datarefs an open [checklist] needs: those of its check items'
/// conditions and of its conditional `sw_continue` links, each once, in order
/// of appearance (items top to bottom, then links).
///
/// This is what the app subscribes to while the checklist is open
/// (decision D-52). A checklist with no conditions gives an empty list.
List<Dataref> signalsFor(Checklist checklist) {
  final seen = <Dataref>{};
  final result = <Dataref>[];
  void add(Iterable<Dataref> signals) {
    for (final d in signals) {
      if (seen.add(d)) result.add(d);
    }
  }

  for (final item in checklist.items) {
    if (item.type == ChecklistItemType.check) {
      add(item.condition?.signals ?? const []);
    }
  }
  for (final link in checklist.continues) {
    add(link.condition?.signals ?? const []);
  }
  return result;
}
