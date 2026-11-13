import 'dart:convert';
import 'dart:io';

final _checklistLine = RegExp(
  r'^\s*@?sw_checklist:([^:\r\n]*)',
  caseSensitive: false,
);
final _checkItemLine = RegExp(r'^\s*@?sw_item(_c)?:', caseSensitive: false);

/// One condition fixture: a checklist, the dataref values to feed it and the
/// result the evaluator must give (`testing/fixtures/conditions/README.md`).
class ConditionFixture {
  ConditionFixture._({
    required this.name,
    required this.text,
    required this.steps,
    required this.expected,
  });

  /// Base name of the three files, for example `plain_equal`.
  final String name;

  /// The checklist in XChecklist format.
  final String text;

  /// The value maps in the order they are applied. A flat values file is one
  /// step. A `null` value means the dataref has no value from that step on.
  final List<Map<String, num?>> steps;

  /// The parsed `.expected.json`.
  final Map<String, Object?> expected;

  /// Names of the checklists in file order.
  late final List<String> checklists = [
    for (final line in const LineSplitter().convert(text))
      if (_checklistLine.firstMatch(line) case final m?) m.group(1)!.trim(),
  ];

  /// How many `sw_item` and `sw_item_c` lines the file has.
  late final int checkItemCount = const LineSplitter()
      .convert(text)
      .where(_checkItemLine.hasMatch)
      .length;

  /// Where the expected results come from.
  String get source => expected['source']! as String;

  /// Indexes of check items whose condition is met.
  List<int> get met => _ints('met');

  /// Indexes of check items whose condition is not met.
  List<int> get notMet => _ints('not_met');

  /// Indexes of check items whose condition is unknown.
  List<int> get unknown => _ints('unknown');

  /// Target checklist name, or null, per checklist with `sw_continue`.
  Map<String, String?> get continueTargets => {
    for (final e in ((expected['continue'] ?? const {}) as Map).entries)
      e.key as String: e.value as String?,
  };

  /// Warnings the parser must add, in file order.
  List<String> get warnings => [
    for (final w in (expected['warnings']! as List)) w as String,
  ];

  List<int> _ints(String key) => [
    for (final i in (expected[key]! as List)) i as int,
  ];
}

/// Reads the condition fixtures from `testing/fixtures/conditions`.
abstract final class ConditionFixtures {
  /// Every case in [directory] (relative to the repository root, where the
  /// tests run), sorted by name. Throws a [StateError] when a `.txt` has no
  /// `.values.json` or `.expected.json`, or the folder is missing.
  static List<ConditionFixture> all({
    String directory = 'testing/fixtures/conditions',
  }) {
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      throw StateError('Condition fixture folder not found: $directory');
    }
    final names =
        dir
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .where((n) => n.endsWith('.txt'))
            .map((n) => n.substring(0, n.length - 4))
            .toList()
          ..sort();
    return [for (final name in names) _load(dir.path, name)];
  }

  static ConditionFixture _load(String dir, String name) {
    final text = File('$dir/$name.txt');
    final values = File('$dir/$name.values.json');
    final expected = File('$dir/$name.expected.json');
    for (final f in [values, expected]) {
      if (!f.existsSync()) {
        throw StateError(
          'Condition fixture $name has no ${f.uri.pathSegments.last}',
        );
      }
    }
    final v = jsonDecode(values.readAsStringSync()) as Map<String, Object?>;
    final raw = v['steps'] is List ? v['steps']! as List : [v];
    final steps = <Map<String, num?>>[
      for (final step in raw)
        {
          for (final e in (step as Map).entries)
            e.key as String: e.value as num?,
        },
    ];
    return ConditionFixture._(
      name: name,
      text: text.readAsStringSync(),
      steps: steps,
      expected: jsonDecode(expected.readAsStringSync()) as Map<String, Object?>,
    );
  }
}
