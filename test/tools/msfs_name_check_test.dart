import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tools/msfs_name_check.dart';

void main() {
  test('finds the quoted A:, L: and B: names once each, in order', () {
    const text = '''
sw_item:Parking brake|SET:"A:BRAKE PARKING POSITION, bool":1
sw_item:Battery|ON:"L:Battery_1":1&&"L:Battery_1":>0
sw_item:Other|ON:'B:ELECTRICAL_BATTERY_2':1
sw_item:Pilot's seat|CHECK:sim/some/dataref:1
''';
    expect(msfsNamesIn(text), [
      'A:BRAKE PARKING POSITION, bool',
      'L:Battery_1',
      'B:ELECTRICAL_BATTERY_2',
    ]);
  });

  test('a file with none says so and succeeds', () async {
    final dir = Directory.systemTemp.createTempSync('msfs_name_check');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/x_clist.txt')
      ..writeAsStringSync('sw_item:A|B:x:1\n');
    final lines = <String>[];
    final code = await msfsNameCheck([
      'http://127.0.0.1:1',
      file.path,
    ], out: lines.add);
    expect(code, 0);
    expect(lines, ['no A:, L: or B: names found']);
  });

  test('a wrong usage is exit code 2', () async {
    expect(await msfsNameCheck([], out: (_) {}), 2);
    expect(await msfsNameCheck(['http://x', 'missing.txt'], out: (_) {}), 2);
  });
}
