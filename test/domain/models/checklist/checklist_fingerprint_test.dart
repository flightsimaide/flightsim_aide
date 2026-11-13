import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_fingerprint.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/checklist/colour_run.dart';
import 'package:flutter_test/flutter_test.dart';

const _check = ChecklistItemType.check;
const _note = ChecklistItemType.note;

Checklist list(List<ChecklistItem> items) =>
    Checklist(name: 'n', title: 't', items: items);

void main() {
  final base = list(const [
    ChecklistItem(_check, 'Battery'),
    ChecklistItem(_note, 'Note'),
    ChecklistItem(_check, 'Fuel'),
  ]);

  test('same checklist same fingerprint', () {
    expect(fingerprintOf(base), fingerprintOf(list(base.items)));
  });

  test('known input gives a known value', () {
    expect(fingerprintOf(base), '2a63c01a-3');
  });

  test('changed label changes it', () {
    final other = list(const [
      ChecklistItem(_check, 'Battery'),
      ChecklistItem(_note, 'Note'),
      ChecklistItem(_check, 'Fuel pump'),
    ]);
    expect(fingerprintOf(other), isNot(fingerprintOf(base)));
  });

  test('changed type changes it', () {
    final other = list(const [
      ChecklistItem(_check, 'Battery'),
      ChecklistItem(_check, 'Note'),
      ChecklistItem(_check, 'Fuel'),
    ]);
    expect(fingerprintOf(other), isNot(fingerprintOf(base)));
  });

  test('inserted item changes it', () {
    final other = list(const [
      ChecklistItem(_check, 'Battery'),
      ChecklistItem(_check, 'Master'),
      ChecklistItem(_note, 'Note'),
      ChecklistItem(_check, 'Fuel'),
    ]);
    expect(fingerprintOf(other), isNot(fingerprintOf(base)));
  });

  test('reordered items change it', () {
    final other = list(const [
      ChecklistItem(_check, 'Fuel'),
      ChecklistItem(_note, 'Note'),
      ChecklistItem(_check, 'Battery'),
    ]);
    expect(fingerprintOf(other), isNot(fingerprintOf(base)));
  });

  test('moving text between neighbouring labels changes it', () {
    final a = list(const [
      ChecklistItem(_check, 'ab'),
      ChecklistItem(_check, 'c'),
    ]);
    final b = list(const [
      ChecklistItem(_check, 'a'),
      ChecklistItem(_check, 'bc'),
    ]);
    expect(fingerprintOf(a), isNot(fingerprintOf(b)));
  });

  test('result text or colour runs do not matter (only type and label)', () {
    final other = list(const [
      ChecklistItem(_check, 'Battery', 'ON', [], [ColourRun('ON')]),
      ChecklistItem(_note, 'Note'),
      ChecklistItem(_check, 'Fuel', 'Open'),
    ]);
    expect(fingerprintOf(other), fingerprintOf(base));
  });

  test('empty checklist has a value', () {
    expect(fingerprintOf(list(const [])), '811c9dc5-0');
  });
}
