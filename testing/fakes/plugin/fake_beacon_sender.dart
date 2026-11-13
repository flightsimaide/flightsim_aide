import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Builds and sends X-Plane `BECN` multicast beacon packets for tests, so
/// discovery can be exercised on a machine without X-Plane.
///
/// Layout (little endian, as in `testing/fixtures/protocol/becn_xp12.bin`):
/// `BECN\0`, major u8, minor u8, host id i32, sim version i32, role u32,
/// port u16, computer name (NUL terminated), then two trailing bytes.
class FakeBeaconSender {
  const FakeBeaconSender._();

  /// X-Plane's beacon group and port.
  static final multicastGroup = InternetAddress('239.255.1.1');
  static const multicastPort = 49707;

  /// One beacon packet. Defaults reproduce the captured XP12 packet.
  static Uint8List build({
    String name = 'SIMPC',
    int port = 49000,
    int hostId = 1,
    int version = 124417,
    int role = 1,
    int major = 1,
    int minor = 2,
    List<int> trailing = const [0x72, 0xbf],
  }) {
    final nameBytes = [...utf8.encode(name), 0];
    final bytes = BytesBuilder()
      ..add(const [0x42, 0x45, 0x43, 0x4e, 0x00])
      ..addByte(major)
      ..addByte(minor);
    final fixed = ByteData(14)
      ..setInt32(0, hostId, Endian.little)
      ..setInt32(4, version, Endian.little)
      ..setUint32(8, role, Endian.little)
      ..setUint16(12, port, Endian.little);
    bytes
      ..add(fixed.buffer.asUint8List())
      ..add(nameBytes)
      ..add(trailing);
    return bytes.toBytes();
  }

  /// The first [length] bytes of [packet], as a cut-off datagram.
  static Uint8List truncated(Uint8List packet, int length) =>
      Uint8List.sublistView(packet, 0, length);

  /// Sends [packet] to [to]:[port] from a socket bound to [from], so a test
  /// can make one sim appear from several source addresses.
  static Future<void> send(
    Uint8List packet, {
    required InternetAddress to,
    int port = multicastPort,
    InternetAddress? from,
  }) async {
    final socket = await RawDatagramSocket.bind(
      from ?? InternetAddress.loopbackIPv4,
      0,
    );
    try {
      socket.send(packet, to, port);
    } finally {
      socket.close();
    }
  }
}
