import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_sequence.dart';
import 'package:flightsim_aide/domain/models/checklist/continue_link.dart';
import 'package:flutter_test/flutter_test.dart';

Checklist c(String name, [List<ContinueLink> continues = const []]) =>
    Checklist(
      name: name,
      title: name,
      items: const [ChecklistItem(ChecklistItemType.check, 'K', 'V')],
      continues: continues,
    );

const next = ContinueLink.next();
ContinueLink to(String name) => ContinueLink.named(name);

List<String> names(Iterable<Checklist> list) => [for (final x in list) x.name];

void main() {
  test('the file order is not the flight order', () {
    final landing = c('Landing');
    final cruise = c('Cruise', [to('Landing')]);
    final takeoff = c('Takeoff', [to('Cruise')]);
    final sequence = ChecklistSequence([landing, takeoff, cruise]);
    expect(names(sequence.ordered), ['Takeoff', 'Cruise', 'Landing']);
    expect(names(sequence.checklists), ['Landing', 'Takeoff', 'Cruise']);
  });

  test('a bare link goes to the next checklist in file order', () {
    final sequence = ChecklistSequence([
      c('A', [next]),
      c('B', [next]),
      c('C'),
    ]);
    expect(names(sequence.successors(sequence.checklists[0])), ['B']);
    expect(names(sequence.ordered), ['A', 'B', 'C']);
  });

  test('a named link goes to the checklist with that name', () {
    final sequence = ChecklistSequence([
      c('A', [to('C')]),
      c('B'),
      c('C'),
    ]);
    expect(names(sequence.successors(sequence.checklists[0])), ['C']);
  });

  test('a bare link on the last checklist goes nowhere', () {
    final sequence = ChecklistSequence([
      c('A'),
      c('B', [next]),
    ]);
    expect(sequence.successors(sequence.checklists[1]), isEmpty);
  });

  test('a link to a missing checklist is skipped', () {
    final sequence = ChecklistSequence([
      c('A', [to('Nope'), to('B')]),
      c('B'),
    ]);
    expect(names(sequence.successors(sequence.checklists[0])), ['B']);
  });

  test('repeated links give one successor', () {
    final sequence = ChecklistSequence([
      c('A', [to('B'), next, to('B')]),
      c('B'),
    ]);
    expect(names(sequence.successors(sequence.checklists[0])), ['B']);
  });

  test('a checklist that is not in the sequence has no successors', () {
    final sequence = ChecklistSequence([c('A')]);
    expect(sequence.successors(c('Other', [next])), isEmpty);
  });

  test('without links the order is the file order', () {
    final sequence = ChecklistSequence([c('A'), c('B'), c('C')]);
    expect(names(sequence.ordered), ['A', 'B', 'C']);
  });

  test('link order decides the order of branches', () {
    final sequence = ChecklistSequence([
      c('A', [to('C'), to('B')]),
      c('B'),
      c('C'),
    ]);
    expect(names(sequence.ordered), ['A', 'C', 'B']);
  });

  test('separate chains start in file order', () {
    final sequence = ChecklistSequence([
      c('X1', [to('X2')]),
      c('Y1', [to('Y2')]),
      c('X2'),
      c('Y2'),
    ]);
    expect(names(sequence.ordered), ['X1', 'X2', 'Y1', 'Y2']);
  });

  test('a loop ends and every checklist appears once', () {
    final sequence = ChecklistSequence([
      c('A', [to('B')]),
      c('B', [to('A')]),
    ]);
    expect(names(sequence.ordered), ['A', 'B']);
  });

  test('a loop after an entry point appears once', () {
    final sequence = ChecklistSequence([
      c('Start', [to('A')]),
      c('A', [to('B')]),
      c('B', [to('A')]),
    ]);
    expect(names(sequence.ordered), ['Start', 'A', 'B']);
  });

  test('a link to itself is harmless', () {
    final sequence = ChecklistSequence([
      c('A', [to('A')]),
      c('B'),
    ]);
    expect(names(sequence.ordered), ['A', 'B']);
  });

  test('an empty sequence is empty', () {
    final sequence = ChecklistSequence(const []);
    expect(sequence.ordered, isEmpty);
  });

  test('a checklist with no links ends the chain', () {
    final sequence = ChecklistSequence([
      c('A', [to('B')]),
      c('B'),
      c('C'),
    ]);
    expect(names(sequence.chainFrom(sequence.checklists[0])), ['A', 'B']);
    expect(names(sequence.chainFrom(sequence.checklists[2])), ['C']);
  });

  test('the chain follows the first link and stops at a loop', () {
    final sequence = ChecklistSequence([
      c('A', [to('B'), to('C')]),
      c('B', [to('A')]),
      c('C'),
    ]);
    expect(names(sequence.chainFrom(sequence.checklists[0])), ['A', 'B']);
  });

  test('the checklists list is unmodifiable', () {
    final sequence = ChecklistSequence([c('A')]);
    expect(() => sequence.checklists.add(c('B')), throwsUnsupportedError);
  });
}
