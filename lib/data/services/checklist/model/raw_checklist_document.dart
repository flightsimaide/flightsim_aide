/// A checklist file as read from a source: a display name and unparsed text.
class RawChecklistDocument {
  /// Creates a raw document.
  const RawChecklistDocument({required this.name, required this.text});

  /// File name for display.
  final String name;

  /// Undecoded-format text, exactly as read; parsing happens elsewhere.
  final String text;
}
