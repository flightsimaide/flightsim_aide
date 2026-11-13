import 'package:equatable/equatable.dart';

/// A named number in the simulator: a dataref, or one element of an array
/// dataref. Immutable.
class Dataref extends Equatable {
  /// A scalar dataref, or element [index] (zero-based) of an array dataref.
  const Dataref(this.name, [this.index]) : assert(index == null || index >= 0);

  /// Reads `name` or `name[n]`; null when the text has any other bracket use.
  /// The one place that turns wire text into a [Dataref] (`PROTOCOL.md` 9).
  static Dataref? tryParse(String wireName) {
    final text = wireName.trim();
    if (text.isEmpty) return null;
    final open = text.indexOf('[');
    final close = text.indexOf(']');
    if (open < 0 && close < 0) return Dataref(text);
    if (open <= 0 || close != text.length - 1 || close < open) return null;
    final digits = text.substring(open + 1, close);
    if (digits.isEmpty ||
        digits.length > 6 ||
        !RegExp(r'^[0-9]+$').hasMatch(digits)) {
      return null;
    }
    final base = text.substring(0, open).trim();
    if (base.isEmpty || base.contains('[') || base.contains(']')) return null;
    return Dataref(base, int.parse(digits));
  }

  /// The dataref name without any index.
  final String name;

  /// The array element, or null for a scalar.
  final int? index;

  /// The name as it goes on the wire: `name` or `name[index]`.
  String get wireName => index == null ? name : '$name[$index]';

  @override
  List<Object?> get props => [name, index];

  @override
  String toString() => wireName;
}
