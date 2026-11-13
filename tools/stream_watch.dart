// Subscribes to one signal on a companion plugin (or the Dart fake) and prints
// every frame it receives, one line each, with the local time.
//
//   dart run tools/stream_watch.dart <baseUrl> <name> [hz] [--count N]
//
// hz defaults to 2. With --count the tool stops after N frames; otherwise it
// runs until the connection closes or you press Ctrl+C.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Returns the exit code: 0 after at least one frame, 1 on a connection
/// failure, 2 on a usage error.
Future<int> streamWatch(List<String> args, {void Function(String)? out}) async {
  final void Function(String) write = out ?? (s) => stdout.writeln(s);
  final positional = <String>[];
  int? count;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--count') {
      if (++i >= args.length) return _usage(write);
      count = int.tryParse(args[i]);
      if (count == null || count < 1) return _usage(write);
    } else if (args[i].startsWith('--')) {
      return _usage(write);
    } else {
      positional.add(args[i]);
    }
  }
  if (positional.length < 2 || positional.length > 3) return _usage(write);
  final hz = positional.length == 3 ? int.tryParse(positional[2]) : 2;
  if (hz == null || hz < 1 || hz > 60) return _usage(write);

  final base = Uri.parse(positional[0]);
  final url = base.replace(scheme: 'ws', path: '/v1/stream');
  final WebSocket socket;
  try {
    socket = await WebSocket.connect(url.toString());
  } on Object catch (e) {
    write('cannot connect to $url: $e');
    return 1;
  }
  socket.add(
    jsonEncode({'op': 'subscribe', 'id': 1, 'name': positional[1], 'hz': hz}),
  );

  var frames = 0;
  final done = Completer<void>();
  final sub = socket.listen(
    (message) {
      write('${DateTime.now().toIso8601String()} $message');
      frames++;
      if (count != null && frames >= count && !done.isCompleted) {
        done.complete();
      }
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
    onError: (Object _) {
      if (!done.isCompleted) done.complete();
    },
  );
  await done.future;
  await sub.cancel();
  await socket.close();
  return frames > 0 ? 0 : 1;
}

int _usage(void Function(String) write) {
  write('usage: stream_watch.dart <baseUrl> <name> [hz] [--count N]');
  return 2;
}

Future<void> main(List<String> args) async {
  exitCode = await streamWatch(args);
}
