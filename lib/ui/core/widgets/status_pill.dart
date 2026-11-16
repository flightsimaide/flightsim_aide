import 'package:flutter/material.dart';

import '../themes/status_colors.dart';

/// Which status a [StatusPill] shows.
enum PillStatus {
  /// Good: green, a check mark (complete).
  good,

  /// Caution: yellow, a warning triangle (skipped).
  caution,

  /// Warning: red, the error icon (overridden).
  warning,

  /// Information: cyan, the info icon (a message that does not affect the
  /// operation of the aircraft, like "manual item" while auto is on).
  info,
}

/// A status message on a filled pill: the status icon and [text] in black or
/// white, whichever reads better on the fill. Used where coloured text on the
/// page would be hard to read or would look like another status (the
/// "Complete", "n skipped" and "n overridden" counts).
class StatusPill extends StatelessWidget {
  /// Creates a pill of [status] showing [text].
  const StatusPill({
    required this.status,
    required this.text,
    this.style,
    this.showIcon = true,
    super.key,
  });

  /// The status; sets the fill and the icon.
  final PillStatus status;

  /// What the pill says.
  final String text;

  /// Text style; the colour is replaced by the readable foreground.
  final TextStyle? style;

  /// Whether the status icon shows before the text. Turn it off only where
  /// the text alone says the status and space is tight.
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = theme.extension<StatusColors>();
    final (fill, icon) = switch (status) {
      PillStatus.good => (
        colours?.success ?? theme.colorScheme.primary,
        Icons.check_circle,
      ),
      PillStatus.caution => (
        colours?.cautionBackground ?? theme.colorScheme.error,
        Icons.warning,
      ),
      PillStatus.warning => (
        colours?.error ?? theme.colorScheme.error,
        Icons.error,
      ),
      PillStatus.info => (
        colours?.info ?? theme.colorScheme.secondary,
        Icons.info,
      ),
    };
    final foreground = readableOn(fill);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showIcon) ...[
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 4),
            ],
            // Flexible, so a long message wraps inside the pill.
            Flexible(
              child: Text(
                text,
                // Without a given style the text would keep the theme's
                // colour.
                style: (style ?? const TextStyle()).copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
