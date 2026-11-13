/// The absolute tolerance of "equal" in a condition (`GRAMMAR.md` O1, decision
/// D-64).
const double equalityTolerance = 1e-6;

/// Whether [a] and [b] are equal in a condition: `abs(a - b) < 1e-6`.
///
/// Only equal and not equal use it; `<`, `>`, `<=`, `>=` and the range compare
/// the doubles exactly. Every value is a double (a float dataref is widened),
/// which is why integers and floats need no separate rule. NaN is never equal
/// to anything, and two equal infinities are equal.
bool numbersEqual(double a, double b) {
  if (a == b) return true;
  return (a - b).abs() < equalityTolerance;
}
