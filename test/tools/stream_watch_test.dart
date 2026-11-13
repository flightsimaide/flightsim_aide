import 'package:flutter_test/flutter_test.dart';

import '../../testing/fakes/plugin/fake_companion_plugin_server.dart';
import '../../tools/stream_watch.dart';

void main() {
  late FakeCompanionPluginServer server;

  setUp(() async {
    server = await FakeCompanionPluginServer.start();
  });

  tearDown(() async {
    await server.close();
  });

  test('prints the frames of one signal and stops after --count', () async {
    final lines = <String>[];
    final code = await streamWatch([
      server.baseUri.toString(),
      'sim/flightmodel/failures/onground_any',
      '20',
      '--count',
      '4',
    ], out: lines.add);
    expect(code, 0);
    expect(lines, hasLength(4));
    expect(lines.first, contains('"op":"subscribed"'));
    expect(lines.skip(1).every((l) => l.contains('"op":"values"')), isTrue);
    expect(lines[1], contains('"v":{"1":1}'));
  });

  test('an unknown name prints the error frame', () async {
    final lines = <String>[];
    final code = await streamWatch([
      server.baseUri.toString(),
      'no/such/name',
      '--count',
      '1',
    ], out: lines.add);
    expect(code, 0);
    expect(lines.single, contains('unknown_name'));
  });

  test('usage errors exit 2', () async {
    expect(await streamWatch([], out: (_) {}), 2);
    expect(await streamWatch(['http://x', 'n', '0'], out: (_) {}), 2);
    expect(await streamWatch(['http://x', 'n', '--bogus'], out: (_) {}), 2);
  });

  test('a server that is not there exits 1', () async {
    final lines = <String>[];
    final code = await streamWatch([
      'http://127.0.0.1:1',
      'n',
      '--count',
      '1',
    ], out: lines.add);
    expect(code, 1);
    expect(lines.single, startsWith('cannot connect'));
  });
}
