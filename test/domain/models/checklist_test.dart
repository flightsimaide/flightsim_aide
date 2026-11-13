import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/continue_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const item = ChecklistItem(ChecklistItemType.check, 'Battery', 'ON');

  test('equality by value', () {
    final a = Checklist(name: 'A', title: 'Alpha', items: [item]);
    final b = Checklist(name: 'A', title: 'Alpha', items: [item]);
    expect(a, b);
    expect(a, isNot(Checklist(name: 'B', title: 'Alpha', items: [item])));
  });

  test('continues are part of equality', () {
    Checklist make(List<ContinueLink> continues) => Checklist(
      name: 'A',
      title: 'Alpha',
      items: [item],
      continues: continues,
    );
    final a = make([const ContinueLink.named('B')]);
    expect(a, make([const ContinueLink.named('B')]));
    expect(a.hashCode, make([const ContinueLink.named('B')]).hashCode);
    expect(a, isNot(make([const ContinueLink.next()])));
    expect(a, isNot(make(const [])));
  });

  test('continues default to empty and are unmodifiable', () {
    final c = Checklist(name: 'A', title: 'Alpha', items: [item]);
    expect(c.continues, isEmpty);
    expect(
      () => c.continues.add(const ContinueLink.next()),
      throwsUnsupportedError,
    );
  });

  test('items list is unmodifiable', () {
    final c = Checklist(name: 'A', title: 'Alpha', items: [item]);
    expect(() => c.items.add(item), throwsUnsupportedError);
  });

  test('mutating the source list afterwards does not change the Checklist', () {
    final source = [item];
    final c = Checklist(name: 'A', title: 'Alpha', items: source);
    source.add(item);
    expect(c.items, hasLength(1));
  });
}
