import 'package:flutter_test/flutter_test.dart';

import '../../tools/msfs_snapshot.dart';

void main() {
  test('names skip blank lines and comments', () {
    expect(namesIn('# x\n\nA:ONE, bool\n  L:TWO  \n'), [
      'A:ONE, bool',
      'L:TWO',
    ]);
  });

  test('a reading is parsed with the last tab as the separator', () {
    expect(parseReading('A:X, bool\t1\nL:Y\t-\n'), {
      'A:X, bool': '1',
      'L:Y': '-',
    });
  });

  test('the diff lists only real changes, sorted, ignoring float noise', () {
    final a = {
      'B:ONE': '0',
      'L:TWO': '1',
      'L:THREE': '2.0000000001',
      'L:GONE': '5',
    };
    final b = {'B:ONE': '1', 'L:TWO': '1', 'L:THREE': '2', 'L:NEW': '7'};
    expect(diffReadings(a, b), [
      'B:ONE: 0 -> 1',
      'L:GONE: 5 -> missing',
      'L:NEW: missing -> 7',
    ]);
  });

  test('a wrong usage is exit code 2', () async {
    expect(await msfsSnapshot([], out: (_) {}), 2);
    expect(await msfsSnapshot(['diff', 'nope', 'nope2'], out: (_) {}), 2);
  });
}
