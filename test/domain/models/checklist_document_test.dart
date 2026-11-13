import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final checklist = Checklist(name: 'A', title: 'Alpha', items: const []);

  test('lists are unmodifiable', () {
    final d = ChecklistDocument(checklists: [checklist], warnings: ['w']);
    expect(() => d.checklists.add(checklist), throwsUnsupportedError);
    expect(() => d.warnings.add('x'), throwsUnsupportedError);
  });

  test('copyWith changes only sourceName', () {
    final d = ChecklistDocument(
      checklists: [checklist],
      warnings: ['Line 1: oops'],
      sourceName: 'old.txt',
    );
    final c = d.copyWith(sourceName: 'new.txt');
    expect(c.sourceName, 'new.txt');
    expect(c.checklists, d.checklists);
    expect(c.warnings, d.warnings);
    expect(d.sourceName, 'old.txt');
  });

  test('copyWith with no argument keeps sourceName', () {
    final d = ChecklistDocument(
      checklists: [checklist],
      warnings: const [],
      sourceName: 'old.txt',
    );
    expect(d.copyWith().sourceName, 'old.txt');
  });

  test('documents with equal fields are equal', () {
    ChecklistDocument make(String name) => ChecklistDocument(
      checklists: [checklist],
      warnings: const ['w'],
      sourceName: name,
    );
    expect(make('a.txt'), make('a.txt'));
    expect(make('a.txt'), isNot(make('b.txt')));
  });

  test('empty document has no checklists', () {
    final d = ChecklistDocument(checklists: const [], warnings: const []);
    expect(d.checklists, isEmpty);
    expect(d.warnings, isEmpty);
    expect(d.sourceName, '');
  });
}
