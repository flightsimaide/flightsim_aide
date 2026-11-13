// Reads every condition of a checklist file from a running sim and says, for
// each check item, whether the condition holds now.
//
//   dart run tools/clist_snapshot.dart <baseUrl> <checklist file> [--out FILE]
//
// It uses the app's own parser and evaluator, so what it prints is what the
// app would decide on the first evaluation. It subscribes through the
// companion plugin's stream (one connection, every name of the file once), so
// a name the plugin cannot resolve is listed as UNKNOWN NAME and a name whose
// value is null (an array index past the end, a value the plugin cannot give)
// as NO VALUE (PAST END when other elements of that array answered, so a
// range `name[a..b]` reaches beyond the array). Items with no condition are MANUAL. Change and crossing forms
// (`+>`, `-<`, `><`, `a:b`) need two readings and are listed as NEEDS HISTORY.
//
// Exit code: 0 after a report, 1 when the sim cannot be reached, 2 on a usage
// error.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_item.dart';
import 'package:flightsim_aide/domain/models/flight_sim/dataref.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/condition_evaluator.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/evaluate_item_conditions_use_case.dart';
import 'package:flightsim_aide/domain/use_cases/autocheck/signals_for.dart';

Future<int> main(List<String> args) async {
  String? out;
  final positional = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--out' && i + 1 < args.length) {
      out = args[++i];
    } else {
      positional.add(args[i]);
    }
  }
  if (positional.length != 2) {
    stderr.writeln(
      'usage: dart run tools/clist_snapshot.dart <baseUrl> <file> [--out FILE]',
    );
    return 2;
  }
  final document = const AircraftWorkflowParser().parse(
    File(positional[1]).readAsStringSync(),
  );

  final refs = <String, Dataref>{};
  for (final checklist in document.checklists) {
    for (final d in signalsFor(checklist)) {
      refs[d.wireName] = d;
    }
  }
  final names = refs.keys.toList();
  final ids = {for (var i = 0; i < names.length; i++) names[i]: i + 1};

  final url = Uri.parse(positional[0])
      .replace(scheme: 'ws', path: '/v1/stream');
  final unknownNames = <String>{};
  final otherErrors = <String, String>{};
  final values = <String, double?>{};
  final got = <String>{};
  final idToName = {for (final e in ids.entries) e.value: e.key};

  // The plugin takes at most 128 subscriptions and 4 clients, so the names go
  // out in groups of 100, one connection each.
  final sockets = <WebSocket>[];
  final subs = <StreamSubscription<dynamic>>[];
  for (var start = 0; start < names.length; start += 100) {
    final WebSocket socket;
    try {
      socket = await WebSocket.connect(url.toString());
    } on Object catch (e) {
      stderr.writeln('cannot connect to $url: $e');
      return 1;
    }
    sockets.add(socket);
    subs.add(
      socket.listen((message) {
        final frame = jsonDecode(message as String) as Map<String, dynamic>;
        if (frame['op'] == 'error' && frame['id'] is int) {
          final name = idToName[frame['id'] as int];
          if (name == null) return;
          if (frame['code'] == 'unknown_name') {
            unknownNames.add(name);
          } else {
            otherErrors[name] = '${frame['code']}';
          }
        } else if (frame['op'] == 'values') {
          (frame['v'] as Map<String, dynamic>).forEach((id, v) {
            final name = idToName[int.parse(id)];
            if (name == null) return;
            got.add(name);
            values[name] = v is num ? v.toDouble() : null;
          });
        }
      }),
    );
    for (var i = start; i < start + 100 && i < names.length; i++) {
      socket.add(
        jsonEncode({
          'op': 'subscribe',
          'id': ids[names[i]],
          'name': names[i],
          'hz': 2,
        }),
      );
    }
  }
  // Wait until every name has answered (a value or an error), at most 8 s.
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(deadline) &&
      got.length + unknownNames.length + otherErrors.length < names.length) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  await Future<void>.delayed(const Duration(milliseconds: 600));
  for (final sub in subs) {
    await sub.cancel();
  }
  for (final socket in sockets) {
    await socket.close();
  }

  final useCase = EvaluateItemConditionsUseCase();
  final lookup = MapValues(values);
  final lines = <String>[];
  final counts = <String, int>{};
  void count(String k) => counts[k] = (counts[k] ?? 0) + 1;

  for (final checklist in document.checklists) {
    lines.add('');
    lines.add('== ${checklist.title}');
    for (var i = 0; i < checklist.items.length; i++) {
      final item = checklist.items[i];
      if (item.type != ChecklistItemType.check) continue;
      final condition = item.condition;
      String status;
      String detail = '';
      if (condition == null) {
        status = 'MANUAL';
      } else {
        final signals = condition.signals.map((d) => d.wireName).toList();
        final bad = signals
            .where(
              (n) => unknownNames.contains(n) || otherErrors.containsKey(n),
            )
            .toList();
        final empty = signals
            .where((n) => !unknownNames.contains(n) && values[n] == null)
            .toList();
        if (bad.isNotEmpty) {
          status = 'UNKNOWN NAME';
          detail = bad.join(', ');
        } else if (empty.isNotEmpty) {
          // An index past the end of an array: another element of the same
          // array answered with a number, so the array is shorter than the
          // checklist assumes (a range name[a..b] reaches too far).
          final past = empty.where((n) {
            final d = refs[n];
            return d != null &&
                d.index != null &&
                values.entries.any(
                  (e) =>
                      e.value != null &&
                      refs[e.key]?.name == d.name &&
                      refs[e.key]?.index != null,
                );
          }).toList();
          status = past.isEmpty ? 'NO VALUE' : 'PAST END';
          detail = empty.join(', ');
        } else if (condition.needsMemory) {
          status = 'NEEDS HISTORY';
          detail = signals.map((n) => '$n=${values[n]}').join(', ');
        } else {
          final tri = useCase.conditionOf(
            checklist: checklist,
            index: i,
            values: lookup,
          );
          status = switch (tri) {
            Tri.met => 'TRUE',
            Tri.notMet => 'false',
            Tri.unknown => 'UNKNOWN',
          };
          detail = signals.map((n) => '$n=${values[n]}').join(', ');
        }
      }
      count(status);
      lines.add('${status.padRight(14)} ${item.label}  [$detail]');
    }
  }
  lines.add('');
  lines.add(
    'SUMMARY ${counts.entries.map((e) => '${e.key}=${e.value}').join('  ')}  '
    '(names asked: ${names.length}, answered: ${got.length}, '
    'unknown: ${unknownNames.length}, other errors: ${otherErrors.length})',
  );
  final text = lines.join('\n');
  if (out != null) File(out).writeAsStringSync(text);
  stdout.writeln(text);
  return 0;
}
