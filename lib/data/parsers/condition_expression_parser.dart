import '../../domain/models/flight_sim/dataref.dart';
import '../../domain/models/flight_sim/item_condition.dart';

/// What [ConditionExpressionParser.parse] found.
class ConditionParseResult {
  const ConditionParseResult._(this.condition, this.reason);

  /// No condition in the text (it was empty): not an error.
  static const none = ConditionParseResult._(null, null);

  /// The parsed condition, or null when there is none or it is malformed.
  final ItemCondition? condition;

  /// Why the text could not be parsed (`GRAMMAR.md` M2), or null.
  final String? reason;

  /// Whether the text was malformed.
  bool get failed => reason != null;
}

/// What [ConditionExpressionParser.parseValue] found.
class ValueParseResult {
  const ValueParseResult._(this.value, this.reason);

  /// The parsed expression, or null when the text is malformed.
  final ValueExpr? value;

  /// Why the text could not be parsed, or null.
  final String? reason;

  /// Whether the text was malformed.
  bool get failed => value == null;
}

class _ParseError implements Exception {
  _ParseError(this.reason);
  final String reason;
}

/// Turns the condition text of an item, `sw_show` or `sw_continue` line into
/// an [ItemCondition] (`GRAMMAR.md` section 8). Pure; never throws and never
/// loops: a malformed text gives a reason.
class ConditionExpressionParser {
  /// Creates the parser.
  const ConditionExpressionParser();

  /// Parses [text], the part of the line after the first condition colon.
  ConditionParseResult parse(String text) {
    if (text.trim().isEmpty) return ConditionParseResult.none;
    try {
      final scan = _Scan(text);
      final condition = scan.parseTop();
      return ConditionParseResult._(condition, null);
    } on _ParseError catch (e) {
      return ConditionParseResult._(null, e.reason);
    } on Object {
      return const ConditionParseResult._(null, 'unreadable condition');
    }
  }

  /// Parses [text] as one arithmetic expression (`GRAMMAR.md` section 8.4):
  /// a number, `{dataref}`, the operators, parentheses and the functions. A
  /// bare dataref name (`sim/foo` or `sim/foo[2]`) is also read, as that
  /// dataref. Used for the input columns of `sw_table` (section 5c).
  ValueParseResult parseValue(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const ValueParseResult._(null, 'missing value');
    if (!trimmed.contains('{') && RegExp(r'^[A-Za-z_]').hasMatch(trimmed)) {
      final dataref = Dataref.tryParse(trimmed);
      if (dataref != null &&
          RegExp(r'^[A-Za-z0-9_/.\[\]]+$').hasMatch(trimmed)) {
        return ValueParseResult._(DatarefExpr(dataref), null);
      }
    }
    try {
      final scan = _Scan(trimmed);
      final value = scan.parseExpr();
      scan.skipBlanks();
      if (!scan.atEnd) {
        if (scan.peek(')')) throw _ParseError('unbalanced parentheses');
        throw scan.unexpected();
      }
      return ValueParseResult._(value, null);
    } on _ParseError catch (e) {
      return ValueParseResult._(null, e.reason);
    } on Object {
      return const ValueParseResult._(null, 'unreadable value');
    }
  }
}

final _numberAt = RegExp(r'(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?');
final _castAt = RegExp(r'\(\s*(int|float|double)\s*\)');

/// `name[a..b]`, an array range on the left side of an atom.
final _rangeAt = RegExp(r'^(.+?)\[(\d{1,6})\.\.(\d{1,6})\]$');

/// The most elements one range may cover: the plugin's subscription cap.
const maxRangeElements = 128;
final _wordAt = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');

class _Scan {
  _Scan(this.s);

  final String s;
  int i = 0;

  bool get atEnd => i >= s.length;

  bool peek(String t) => s.startsWith(t, i);

  void skipBlanks() {
    while (i < s.length && (s[i] == ' ' || s[i] == '\t')) {
      i++;
    }
  }

  /// The text from here to the next blank or structure character.
  String token() {
    final start = i;
    var j = i;
    while (j < s.length && !' \t&|()'.contains(s[j])) {
      j++;
    }
    if (j == start) j = start + 1;
    return s.substring(start, j);
  }

  _ParseError unexpected() => _ParseError('unexpected text "${token()}"');

  ItemCondition parseTop() {
    skipBlanks();
    final ItemCondition c;
    if (peek(':')) {
      i++;
      c = parseRelationalOr();
    } else {
      c = parseOr();
    }
    skipBlanks();
    if (!atEnd) {
      if (peek(')')) throw _ParseError('unbalanced parentheses');
      throw unexpected();
    }
    return c;
  }

  // ---- logic ----

  ItemCondition parseOr() => _join('||', parseAnd, OrCondition.new);

  ItemCondition parseAnd() => _join('&&', parsePrimary, AndCondition.new);

  ItemCondition _join(
    String op,
    ItemCondition Function() part,
    ItemCondition Function(List<ItemCondition>) make,
  ) {
    final parts = [part()];
    while (true) {
      skipBlanks();
      if (!peek(op)) break;
      i += 2;
      skipBlanks();
      if (atEnd) throw _ParseError('missing condition after "$op"');
      parts.add(part());
    }
    return parts.length == 1 ? parts.single : make(parts);
  }

  ItemCondition parsePrimary() {
    skipBlanks();
    if (atEnd) throw _ParseError('missing condition');
    if (peek(')')) throw _ParseError('unexpected ")"');
    if (peek('(')) {
      i++;
      final c = parseOr();
      skipBlanks();
      if (!peek(')')) throw _ParseError('unbalanced parentheses');
      i++;
      return c;
    }
    return parseAtom();
  }

  // ---- the relational form ":(a OP b)" ----

  ItemCondition parseRelationalOr() =>
      _join('||', parseRelationalAnd, OrCondition.new);

  ItemCondition parseRelationalAnd() =>
      _join('&&', parseRelationalPrimary, AndCondition.new);

  ItemCondition parseRelationalPrimary() {
    skipBlanks();
    if (atEnd) throw _ParseError('missing condition');
    if (peek(')')) throw _ParseError('unexpected ")"');
    if (!peek('(')) throw unexpected();
    final start = i;
    i++;
    try {
      // "(expr OP expr)"
      final left = parseExpr();
      skipBlanks();
      final op = parseCompareOp();
      if (op == null) throw _ParseError('missing value');
      final right = parseExpr();
      skipBlanks();
      if (!peek(')')) throw _ParseError('unbalanced parentheses');
      i++;
      return CompareCondition(left, op, right);
    } on _ParseError {
      // "((a OP b) && (c OP d))"
      i = start + 1;
      final c = parseRelationalOr();
      skipBlanks();
      if (!peek(')')) throw _ParseError('unbalanced parentheses');
      i++;
      return c;
    }
  }

  // ---- atoms ----

  ItemCondition parseAtom() {
    final start = i;
    while (i < s.length && !':|()&'.contains(s[i])) {
      i++;
    }
    final nameText = s.substring(start, i).trim();
    if (!peek(':')) throw _ParseError('missing ":" after the name');
    if (nameText.isEmpty) {
      i = start;
      throw unexpected();
    }
    final range = _rangeAt.firstMatch(nameText);
    if (range == null) {
      final left = _leftSide(nameText);
      i++; // ':'
      return _atomTail(left);
    }
    // name[a..b]: the tail is read once and applied to each element, joined
    // with "and" (all elements; an app extension, GRAMMAR.md E2).
    final low = int.parse(range.group(2)!);
    final high = int.parse(range.group(3)!);
    final text = '$low..$high';
    if (low > high) throw _ParseError('range "$text" is backwards');
    if (high - low + 1 > maxRangeElements) {
      throw _ParseError(
        'range "$text" has more than $maxRangeElements elements',
      );
    }
    final name = range.group(1)!.trim();
    i++; // ':'
    final tailStart = i;
    final parts = <ItemCondition>[];
    for (var n = low; n <= high; n++) {
      i = tailStart;
      parts.add(_atomTail(DatarefExpr(Dataref(name, n))));
    }
    return parts.length == 1 ? parts.single : AndCondition(parts);
  }

  /// The part after the colon of an atom, for the already parsed [left].
  ItemCondition _atomTail(ValueExpr left) {
    skipBlanks();

    final change = _changeOp();
    if (change != null) {
      return ChangeCondition(left, change, parseExpr());
    }
    final op = parseCompareOp() ?? CompareOp.equal;
    final first = parseExpr();
    skipBlanks();
    if (peek('|') && !peek('||')) {
      i++;
      return RangeCondition(left, first, parseExpr());
    }
    if (peek(':')) {
      i++;
      return CrossingCondition(left, first, parseExpr());
    }
    return CompareCondition(left, op, first);
  }

  ValueExpr _leftSide(String nameText) {
    final number = double.tryParse(nameText);
    if (number != null && RegExp(r'^[+-]?[0-9.]').hasMatch(nameText)) {
      return NumberExpr(number);
    }
    final dataref = Dataref.tryParse(nameText);
    if (dataref == null) throw _ParseError('unexpected text "$nameText"');
    return DatarefExpr(dataref);
  }

  ChangeOp? _changeOp() {
    for (final (text, op) in const [
      ('+>', ChangeOp.rise),
      ('-<', ChangeOp.fall),
      ('><', ChangeOp.either),
    ]) {
      if (peek(text)) {
        i += 2;
        return op;
      }
    }
    return null;
  }

  CompareOp? parseCompareOp() {
    skipBlanks();
    for (final (text, op) in const [
      ('==', CompareOp.equal),
      ('!=', CompareOp.notEqual),
      ('<=', CompareOp.lessOrEqual),
      ('>=', CompareOp.greaterOrEqual),
      ('=', CompareOp.equal),
      ('!', CompareOp.notEqual),
      ('<', CompareOp.less),
      ('>', CompareOp.greater),
    ]) {
      if (peek(text)) {
        i += text.length;
        return op;
      }
    }
    return null;
  }

  // ---- arithmetic: + - then * / then ** then unary ----

  ValueExpr parseExpr() {
    var left = parseTerm();
    while (true) {
      skipBlanks();
      if (peek('+') && !peek('+>')) {
        i++;
        left = BinaryExpr(ArithmeticOp.add, left, parseTerm());
      } else if (peek('-') && !peek('-<')) {
        i++;
        left = BinaryExpr(ArithmeticOp.subtract, left, parseTerm());
      } else {
        return left;
      }
    }
  }

  ValueExpr parseTerm() {
    var left = parseUnary();
    while (true) {
      skipBlanks();
      if (peek('*') && !peek('**')) {
        i++;
        left = BinaryExpr(ArithmeticOp.multiply, left, parseUnary());
      } else if (peek('/')) {
        i++;
        left = BinaryExpr(ArithmeticOp.divide, left, parseUnary());
      } else {
        return left;
      }
    }
  }

  ValueExpr parseUnary() {
    skipBlanks();
    if (peek('-')) {
      final start = i;
      i++;
      skipBlanks();
      final m = _numberAt.matchAsPrefix(s, i);
      if (m != null) {
        final after = m.end;
        var j = after;
        while (j < s.length && (s[j] == ' ' || s[j] == '\t')) {
          j++;
        }
        if (!s.startsWith('**', j)) {
          i = after;
          return NumberExpr(-double.parse(m.group(0)!));
        }
      }
      i = start + 1;
      return NegateExpr(parseUnary());
    }
    if (peek('+')) {
      i++;
      return parseUnary();
    }
    return parsePower();
  }

  ValueExpr parsePower() {
    final base = parsePrimaryValue();
    skipBlanks();
    if (peek('**')) {
      i += 2;
      return BinaryExpr(ArithmeticOp.power, base, parseUnary());
    }
    return base;
  }

  ValueExpr parsePrimaryValue() {
    skipBlanks();
    if (atEnd) throw _ParseError('missing value');
    final cast = _castAt.matchAsPrefix(s, i);
    if (cast != null) {
      i = cast.end;
      final type = switch (cast.group(1)!) {
        'int' => CastType.integer,
        'float' => CastType.single,
        _ => CastType.double,
      };
      return CastExpr(type, parseUnary());
    }
    final c = s[i];
    if (c == '(') {
      i++;
      final e = parseExpr();
      skipBlanks();
      if (!peek(')')) throw _ParseError('unbalanced parentheses');
      i++;
      return e;
    }
    if (c == '{') {
      final end = s.indexOf('}', i);
      if (end < 0) throw unexpected();
      final text = s.substring(i + 1, end);
      final d = Dataref.tryParse(text);
      if (d == null) throw _ParseError('unexpected text "{$text}"');
      i = end + 1;
      return DatarefExpr(d);
    }
    final number = _numberAt.matchAsPrefix(s, i);
    if (number != null) {
      i = number.end;
      return NumberExpr(double.parse(number.group(0)!));
    }
    final word = _wordAt.matchAsPrefix(s, i);
    if (word != null) {
      final name = word.group(0)!;
      var j = word.end;
      while (j < s.length && (s[j] == ' ' || s[j] == '\t')) {
        j++;
      }
      if (j < s.length && s[j] == '(') {
        return _call(name, j + 1);
      }
      throw unexpected();
    }
    if ('&|):'.contains(c)) throw _ParseError('missing value');
    throw unexpected();
  }

  ValueExpr _call(String name, int argsStart) {
    final (function, arity) = switch (name) {
      'round' => (ConditionFunction.round, 1),
      'step' => (ConditionFunction.step, 1),
      'closer_than' => (ConditionFunction.closerThan, 3),
      _ => throw _ParseError('unknown function "$name"'),
    };
    i = argsStart;
    final args = <ValueExpr>[];
    skipBlanks();
    if (!peek(')')) {
      while (true) {
        args.add(parseExpr());
        skipBlanks();
        if (peek(',')) {
          i++;
          continue;
        }
        break;
      }
    }
    if (!peek(')')) throw _ParseError('unbalanced parentheses');
    i++;
    if (args.length != arity) {
      throw _ParseError('wrong number of arguments for "$name"');
    }
    return CallExpr(function, args);
  }
}
