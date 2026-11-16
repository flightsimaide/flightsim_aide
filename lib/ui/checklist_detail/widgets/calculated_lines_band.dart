import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/checklist/calculate_line.dart';
import '../../../domain/models/checklist/calculated_value.dart';
import '../../core/widgets/status_pill.dart';
import 'checklist_item_tile.dart';

/// [value] with thousands separators and [decimals] decimals: `32,000`,
/// `34.6`, `-4`.
String formatNumber(double value, {int decimals = 0}) {
  final fixed = value.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final negative = value < 0 && double.parse(fixed) != 0;
  return '${negative ? '-' : ''}$grouped${parts.length > 1 ? '.${parts[1]}' : ''}';
}

/// How many decimals show a value rounded to [step]: `0.1` gives 1, `1` and
/// `10` give 0, `0.25` gives 2.
int decimalsForStep(double step) {
  for (var decimals = 0; decimals <= 6; decimals++) {
    final scaled = step * math.pow(10, decimals);
    if ((scaled - scaled.roundToDouble()).abs() < 1e-9) return decimals;
  }
  return 6;
}

/// A number written without a needless decimal: `30,000`, `4,717.5`.
String _plain(double value) =>
    formatNumber(value, decimals: value == value.roundToDouble() ? 0 : 1);

String _withUnit(String number, String unit) =>
    unit.isEmpty ? number : '$number $unit';

/// What a calculated line shows for [value]: the number rounded to [line]'s
/// step and its unit (`34.6 psi`), or null when there is no value.
String? calculatedText(CalculateLine line, CalculatedValue value) {
  final number = value.value;
  if (number == null) return null;
  return _withUnit(
    formatNumber(number, decimals: decimalsForStep(line.step)),
    line.unit,
  );
}

/// The warning for an input beyond the table: which input, how far, and the
/// value used instead (`Altitude 32,000 ft is above the 30,000 ft limit:
/// using 30,000 ft.`).
String limitMessage(LimitExceeded limit) {
  final actual = _withUnit(_plain(limit.actual), limit.unit);
  final edge = _withUnit(_plain(limit.limit), limit.unit);
  final side = limit.above ? 'above' : 'below';
  return '${limit.name} $actual is $side the $edge limit: using $edge.';
}

/// The `sw_calculate` lines of one item (D-83), shown under it in the band of
/// the details lines. Not an item: it is not counted, ticked or skipped.
///
/// A warning for each input beyond the table comes first, then the first line
/// large, then the others as plain rows. A line with no value says so.
class CalculatedLinesBand extends StatelessWidget {
  /// Creates the band; [values] has one entry per line, in order.
  const CalculatedLinesBand({
    required this.lines,
    required this.values,
    super.key,
  });

  /// The item's `sw_calculate` lines.
  final List<CalculateLine> lines;

  /// The live value of each line.
  final List<CalculatedValue> values;

  CalculatedValue _valueOf(int index) => index < values.length
      ? values[index]
      : const CalculatedValue.unavailable();

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final band = Color.alphaBlend(
      Colors.black.withValues(alpha: 0.25),
      ChecklistItemTile.rowColour(scheme),
    );
    final dim = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final strong = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    final limits = <LimitExceeded>{
      for (var i = 0; i < lines.length; i++) ..._valueOf(i).limits,
    };
    final first = lines.first;
    final firstText = calculatedText(first, _valueOf(0));
    final summary = [
      for (var i = 0; i < lines.length; i++)
        '${lines[i].label} ${calculatedText(lines[i], _valueOf(i)) ?? 'no data'}',
    ].join(', ');
    return Semantics(
      container: true,
      label: summary,
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          color: band,
          padding: const EdgeInsets.fromLTRB(
            18 + ChecklistMarker.size + 10,
            8,
            16,
            12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final limit in limits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: StatusPill(
                    status: PillStatus.caution,
                    text: limitMessage(limit),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: firstText == null
                          ? '— '
                          : '${formatNumber(_valueOf(0).value!, decimals: decimalsForStep(first.step))} ',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: firstText == null
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                    TextSpan(
                      text: firstText == null
                          ? '${first.label} · no data'
                          : [
                              if (first.unit.isNotEmpty) first.unit,
                              first.label,
                            ].join(' · '),
                      style: dim,
                    ),
                  ],
                ),
              ),
              for (var i = 1; i < lines.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(lines[i].label, style: dim)),
                      Text(
                        calculatedText(lines[i], _valueOf(i)) ?? 'no data',
                        style: calculatedText(lines[i], _valueOf(i)) == null
                            ? dim
                            : strong,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
