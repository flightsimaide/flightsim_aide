import 'package:flutter/material.dart';

import '../../../domain/models/checklist/checklist_colour.dart';
import '../../../domain/models/checklist/checklist_item.dart';
import '../../../domain/models/checklist/colour_run.dart';
import '../../core/themes/status_colors.dart';
import 'run_colours.dart';

/// Finds the marker of an auto-checked row, for tests.
const autoMarkerKey = ValueKey<String>('auto-checked-marker');

/// Finds the red marker of a row ticked against the aircraft, for tests.
const disagreedMarkerKey = ValueKey<String>('disagreed-marker');

/// One checklist line: a tappable check row, or a note shown as a header.
class ChecklistItemTile extends StatelessWidget {
  /// Creates a tile for [item].
  ///
  /// [onTap] is used by check rows only. [colours] is the document palette
  /// used for coloured text.
  const ChecklistItemTile({
    required this.item,
    required this.checked,
    required this.onTap,
    this.colours = const {},
    this.skipped = false,
    this.first = false,
    this.autoChecked = false,
    this.disagreed = false,
    super.key,
  });

  /// The line to show.
  final ChecklistItem item;

  /// Whether a check row is checked.
  final bool checked;

  /// Called when a check row is tapped.
  final VoidCallback onTap;

  /// The document's colour palette, keyed by name.
  final Map<String, ChecklistColour> colours;

  /// Whether a check row was skipped: an amber ring. (The
  /// app has no way to skip an item yet; the look is ready for it.)
  final bool skipped;

  /// Whether this is the first row of the list, which also gets a line above.
  final bool first;

  /// Whether the app checked this row from a sim value. It gets a small
  /// "auto" icon; tapping works as for any row.
  final bool autoChecked;

  /// Whether the user ticked this row while the aircraft said it was not set
  /// (D-71): the marker is the red `error` icon instead of the green check.
  /// Only meaningful for a checked row.
  final bool disagreed;

  @override
  Widget build(BuildContext context) {
    return switch (item.type) {
      ChecklistItemType.note => _note(context),
      ChecklistItemType.heading => _heading(context),
      ChecklistItemType.details => _details(context),
      ChecklistItemType.check => _check(context),
    };
  }

  Widget _text(
    BuildContext context,
    TextStyle? style,
    bool isLabel, {
    Color? background,
    bool capitals = false,
    TextAlign? align,
    Color? force,
  }) {
    final base = background ?? Theme.of(context).colorScheme.surface;
    var parts = isLabel ? item.labelParts : item.resultParts;
    if (capitals) {
      parts = [
        for (final part in parts)
          ColourRun(part.text.toUpperCase(), part.colour),
      ];
    }
    // A status colour (skipped, overridden) replaces every colour of the text.
    if (force != null) {
      parts = [for (final part in parts) ColourRun(part.text, null)];
    }
    return Text.rich(
      TextSpan(children: runSpans(parts, colours, base)),
      style: force == null ? style : style?.copyWith(color: force),
      textAlign: align ?? (isLabel ? TextAlign.start : TextAlign.end),
    );
  }

  /// A section heading: bold, aligned left, centre or right, no marker.
  Widget _heading(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );
    final align = switch (item.justify) {
      ChecklistJustify.left => TextAlign.start,
      ChecklistJustify.center => TextAlign.center,
      ChecklistJustify.right => TextAlign.end,
    };
    return Semantics(
      header: true,
      child: Container(
        width: double.infinity,
        color: Color.alphaBlend(
          Colors.black.withValues(alpha: 0.2),
          theme.colorScheme.surface,
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: _text(context, style, true, align: align),
      ),
    );
  }

  /// A line of details under the item above: indented to start under that
  /// item's label, in a darker band, in a dimmer text colour.
  Widget _details(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final band = Color.alphaBlend(
      Colors.black.withValues(alpha: 0.25),
      rowColour(scheme),
    );
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        color: band,
        padding: const EdgeInsets.fromLTRB(
          18 + ChecklistMarker.size + 10,
          8,
          16,
          10,
        ),
        child: _text(
          context,
          theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          true,
          background: band,
        ),
      ),
    );
  }

  Widget _note(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _text(context, style, true)),
            if (item.result.isNotEmpty) ...[
              const SizedBox(width: 12),
              Expanded(flex: 2, child: _text(context, style, false)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _check(BuildContext context) {
    final theme = Theme.of(context);
    final status = theme.extension<StatusColors>();
    final scheme = theme.colorScheme;
    // The marker carries the state (green checked, amber skipped, red
    // overridden); skipped and overridden rows also colour their text. A
    // checked row has a tinted background.
    final showRed = checked && disagreed;
    // The row background carries the status: red when overridden (ticked
    // against the aircraft), amber when skipped. Text and marker keep the
    // normal colours, or black/white when those would be hard to read.
    final statusBackground = showRed
        ? (status?.error ?? scheme.error)
        : (skipped && !checked
              ? (status?.cautionBackground ?? scheme.error)
              : null);
    // An open check row with no condition can never be ticked by auto: a
    // slightly darker fill and a small "manual item" line mark it.
    final manual =
        item.condition == null &&
        !checked &&
        !skipped &&
        statusBackground == null;
    final tint =
        statusBackground ??
        (checked
            ? scheme.primaryContainer
            : manual
            ? manualRowColour(scheme)
            : rowColour(scheme));
    final normal = scheme.onSurface;
    final foreground = statusBackground == null
        ? normal
        : contrastRatio(normal, statusBackground) >= minRunContrast
        ? normal
        : (contrastRatio(Colors.black, statusBackground) >=
                  contrastRatio(Colors.white, statusBackground)
              ? Colors.black
              : Colors.white);
    final style = theme.textTheme.bodyLarge?.copyWith(
      color: statusBackground == null ? null : foreground,
    );
    final resultStyle = style?.copyWith(
      color: statusBackground == null ? scheme.onSurfaceVariant : foreground,
    );
    final side = BorderSide(color: scheme.outlineVariant);
    final spoken = [
      item.label,
      if (item.result.isNotEmpty) item.result,
      checked
          ? (showRed
                ? 'checked, but the aircraft says it is not set'
                : autoChecked
                ? 'checked automatically'
                : 'checked')
          : skipped
          ? 'skipped'
          : 'unchecked',
      if (manual) 'manual item',
    ].join(', ');
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: spoken,
      onTap: onTap,
      child: Material(
        color: tint,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (first) _hairline(side),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 58),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 16, 8),
                  child: LayoutBuilder(
                    builder: (context, box) => Row(
                      children: [
                        if (showRed)
                          Icon(
                            Icons.error,
                            key: disagreedMarkerKey,
                            size: ChecklistMarker.size,
                            color: foreground,
                          )
                        else
                          ChecklistMarker(
                            checked: checked,
                            skipped: skipped,
                            checkedColour: status?.success ?? scheme.primary,
                            skippedColour: foreground,
                            openColour: scheme.outline,
                            checkColour: scheme.surface,
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _text(context, style, true, background: tint),
                        ),
                        if (autoChecked) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.auto_mode,
                            key: autoMarkerKey,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                            semanticLabel: 'Checked automatically',
                          ),
                        ],
                        if (item.result.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          // At most 45% of the row, so a long label still wraps.
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: box.maxWidth * 0.45,
                            ),
                            child: _text(
                              context,
                              resultStyle,
                              false,
                              background: tint,
                              capitals: true,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (manual)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'manual item',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              _hairline(side),
            ],
          ),
        ),
      ),
    );
  }

  /// The background of an open row: a shade lighter than the page.
  static Color rowColour(ColorScheme scheme) => Color.alphaBlend(
    Colors.white.withValues(
      alpha: scheme.brightness == Brightness.light ? 0.45 : 0.07,
    ),
    scheme.surface,
  );

  /// The background of an open manual item: [rowColour] with a faint shade of
  /// the text colour, so it reads as slightly different in both themes.
  static Color manualRowColour(ColorScheme scheme) => Color.alphaBlend(
    scheme.onSurface.withValues(alpha: 0.07),
    rowColour(scheme),
  );

  /// A line inset 16 on both sides.
  Widget _hairline(BorderSide side) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Divider(height: 1, thickness: 1, color: side.color),
  );
}

/// The round marker: a grey ring when open, solid green with a check when
/// checked, a solid amber disc when skipped.
class ChecklistMarker extends StatelessWidget {
  /// Creates a marker in the given state and colours.
  const ChecklistMarker({
    required this.checked,
    required this.skipped,
    required this.checkedColour,
    required this.skippedColour,
    required this.openColour,
    required this.checkColour,
    super.key,
  });

  /// Solid, with a check.
  final bool checked;

  /// An amber ring (when not checked).
  final bool skipped;

  /// Fill of a checked marker.
  final Color checkedColour;

  /// Ring of a skipped marker.
  final Color skippedColour;

  /// Ring of an open marker.
  final Color openColour;

  /// Colour of the check mark.
  final Color checkColour;

  /// Diameter in logical pixels.
  static const double size = 22;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked
            ? checkedColour
            : skipped
            ? skippedColour
            : null,
        border: checked || skipped
            ? null
            : Border.all(color: openColour, width: 2),
      ),
      child: checked ? Icon(Icons.check, size: 16, color: checkColour) : null,
    );
  }
}
