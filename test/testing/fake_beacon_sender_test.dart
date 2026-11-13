import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../testing/fakes/plugin/fake_beacon_sender.dart';

/// What a beacon decoder must read out of a packet. The app's own decoder
/// arrives with discovery; this one pins the layout independently.
({String name, int port, int hostId, int version})? _decode(Uint8List b) {
  if (b.length < 21 || utf8.decode(b.sublist(0, 4)) != 'BECN') return null;
  final d = ByteData.sublistView(b);
  final end = b.indexOf(0, 21);
  if (end < 0) return null;
  return (
    name: utf8.decode(b.sublist(21, end)),
    port: d.getUint16(19, Endian.little),
    hostId: d.getInt32(7, Endian.little),
    version: d.getInt32(11, Endian.little),
  );
}

void main() {
  test('the default packet is byte for byte the captured XP12 beacon', () {
    final captured = File('testing/fixtures/protocol/becn_xp12.bin')
        .readAsBytesSync();
    expect(FakeBeaconSender.build(), captured);
    expect(captured, hasLength(29));
  });

  test('it decodes to the expected name, port and version', () {
    final d = _decode(FakeBeaconSender.build())!;
    expect(d.name, 'SIMPC');
    expect(d.port, 49000);
    expect(d.version, 124417);
  });

  test('several sims give distinct packets', () {
    final a = FakeBeaconSender.build(name: 'SIMPC', hostId: 1);
    final b = FakeBeaconSender.build(name: 'CABIN', port: 49001, hostId: 2);
    expect(a, isNot(b));
    expect(_decode(b)!.name, 'CABIN');
    expect(_decode(b)!.port, 49001);
    expect(_decode(b)!.hostId, 2);
  });

  test('a truncated packet is emitted as is and does not decode', () {
    final full = FakeBeaconSender.build();
    final cut = FakeBeaconSender.truncated(full, 12);
    expect(cut, hasLength(12));
    expect(cut, full.sublist(0, 12));
    expect(_decode(cut), isNull);
  });

  test(
    'the same sim can arrive from three source addresses',
    () async {
      final receiver = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(receiver.close);
      final got = <Datagram>[];
      final done = Completer<void>();
      receiver.listen((e) {
        if (e != RawSocketEvent.read) return;
        final dg = receiver.receive();
        if (dg == null) return;
        got.add(dg);
        if (got.length == 3 && !done.isCompleted) done.complete();
      });

      final packet = FakeBeaconSender.build();
      for (final last in [1, 2, 3]) {
        await FakeBeaconSender.send(
          packet,
          to: InternetAddress.loopbackIPv4,
          port: receiver.port,
          from: InternetAddress('127.0.0.$last'),
        );
      }
      await done.future.timeout(const Duration(seconds: 3));

      expect(got.map((d) => d.address.address).toSet(), {
        '127.0.0.1',
        '127.0.0.2',
        '127.0.0.3',
      });
      expect(got.every((d) => _decode(d.data)!.name == 'SIMPC'), isTrue);
    },
    // macOS has only 127.0.0.1 on loopback, so binding 127.0.0.2 fails.
    skip: Platform.isMacOS ? 'macOS has no 127.0.0.2 or 127.0.0.3' : false,
  );
}
