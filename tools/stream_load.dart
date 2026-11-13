// Subscribes to N signals at a given rate on one connection and counts the
// frames received, to put load on the plugin's flight loop.
//
//   dart run tools/stream_load.dart <baseUrl> [--subs 100] [--hz 60] [--seconds 70]
//
// The names are the flap handle plus array elements `acf_tank_rat[0..]`
// (out-of-range elements read null, which still costs a lookup).
// Then read the plugin's "flight loop: N calls, average .. us" lines in Log.txt.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  var subs = 100;
  var hz = 60;
  var seconds = 70;
  final positional = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--subs':
        subs = int.parse(args[++i]);
      case '--hz':
        hz = int.parse(args[++i]);
      case '--seconds':
        seconds = int.parse(args[++i]);
      default:
        positional.add(args[i]);
    }
  }
  if (positional.length != 1) {
    stdout.writeln(
      'usage: stream_load.dart <baseUrl> [--subs N] [--hz N] [--seconds N]',
    );
    exitCode = 2;
    return;
  }
  final url = Uri.parse(positional[0])
      .replace(scheme: 'ws', path: '/v1/stream');
  final socket = await WebSocket.connect(url.toString());
  var frames = 0;
  var errors = 0;
  final sub = socket.listen((m) {
    final s = m as String;
    if (s.contains('"error"')) {
      errors++;
      if (errors <= 3) stdout.writeln('error frame: $s');
    } else {
      frames++;
    }
  });
  for (var i = 0; i < subs; i++) {
    final name = i == 0
        ? 'sim/cockpit2/controls/flap_handle_deploy_ratio'
        : 'sim/aircraft/overflow/acf_tank_rat[${i - 1}]';
    socket.add(
      jsonEncode({'op': 'subscribe', 'id': i + 1, 'name': name, 'hz': hz}),
    );
  }
  stdout.writeln('subscribed $subs at $hz Hz for $seconds s ...');
  await Future<void>.delayed(Duration(seconds: seconds));
  await sub.cancel();
  await socket.close();
  stdout.writeln(
    'frames=$frames errorFrames=$errors perSecond=${(frames / seconds).toStringAsFixed(1)}',
  );
}
