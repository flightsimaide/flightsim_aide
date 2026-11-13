/// Whether [text] is a dotted IPv4 address a sim could have: four parts of
/// plain decimal digits (no sign, no leading zero), each 0 to 255, and neither
/// `0.0.0.0` nor the limited broadcast `255.255.255.255`.
bool isUsableIpv4(String text) {
  final parts = text.split('.');
  if (parts.length != 4) return false;
  final numbers = <int>[];
  for (final part in parts) {
    if (!RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(part)) return false;
    final n = int.parse(part);
    if (n > 255) return false;
    numbers.add(n);
  }
  if (numbers.every((n) => n == 0)) return false;
  if (numbers.every((n) => n == 255)) return false;
  return true;
}
