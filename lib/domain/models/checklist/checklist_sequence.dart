import 'checklist.dart';

/// The flight order of checklists, found by following their continue links.
///
/// File order is not flight order: a landing checklist may come before the
/// takeoff checklist in the file. The `sw_continue` links say what follows
/// what. Names are unique within a document, so they identify checklists.
class ChecklistSequence {
  /// Creates a sequence over [checklists], which are in file order.
  ChecklistSequence(List<Checklist> checklists)
    : checklists = List.unmodifiable(checklists),
      _indexByName = {
        for (var i = 0; i < checklists.length; i++) checklists[i].name: i,
      };

  /// The checklists, in file order.
  final List<Checklist> checklists;

  final Map<String, int> _indexByName;

  /// The checklists [checklist] continues to, in link order, without repeats.
  ///
  /// A bare link means the next checklist in file order. A link to a checklist
  /// that does not exist is skipped.
  List<Checklist> successors(Checklist checklist) {
    final index = _indexByName[checklist.name];
    if (index == null) return const [];
    final result = <Checklist>[];
    for (final link in checklist.continues) {
      final targetIndex = link.isNext ? index + 1 : _indexByName[link.target];
      if (targetIndex == null || targetIndex >= checklists.length) continue;
      final target = checklists[targetIndex];
      if (!result.contains(target)) result.add(target);
    }
    return result;
  }

  /// Every checklist exactly once, in flight order.
  ///
  /// Starts from the checklists nothing else continues to (in file order) and
  /// follows the links depth first, first link first. Checklists left over,
  /// such as those in a loop with no entry point, follow in file order.
  List<Checklist> get ordered {
    final linkedTo = <String>{};
    for (final c in checklists) {
      for (final next in successors(c)) {
        if (next.name != c.name) linkedTo.add(next.name);
      }
    }
    final visited = <String>{};
    final result = <Checklist>[];
    void visit(Checklist start) {
      final pending = [start];
      while (pending.isNotEmpty) {
        final current = pending.removeLast();
        if (!visited.add(current.name)) continue;
        result.add(current);
        pending.addAll(successors(current).reversed);
      }
    }

    for (final c in checklists) {
      if (!linkedTo.contains(c.name)) visit(c);
    }
    for (final c in checklists) {
      visit(c);
    }
    return result;
  }

  /// [start] and the checklists reached by always taking the first link.
  ///
  /// Stops at a checklist with no links, or before one already in the chain,
  /// so a loop ends.
  List<Checklist> chainFrom(Checklist start) {
    final chain = <Checklist>[];
    final seen = <String>{};
    Checklist? current = start;
    while (current != null && seen.add(current.name)) {
      chain.add(current);
      final next = successors(current);
      current = next.isEmpty ? null : next.first;
    }
    return chain;
  }
}
