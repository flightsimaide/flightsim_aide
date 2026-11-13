import 'package:flutter/material.dart';

/// Tells the user that some lines of the checklist file were skipped, with
/// actions to list every warning or dismiss the banner. Renders nothing when
/// [warnings] is empty.
class WarningsBanner extends StatelessWidget {
  /// Creates a warnings banner.
  const WarningsBanner({
    required this.warnings,
    required this.onDismiss,
    super.key,
  });

  /// The parse warnings to summarise.
  final List<String> warnings;

  /// Called when **Dismiss** is tapped.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final count = warnings.length;
    final text = count == 1
        ? '1 line was skipped'
        : '$count lines were skipped';
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: scheme.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(color: scheme.onTertiaryContainer),
                  ),
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _showDetails(context),
                  child: const Text('Details'),
                ),
                TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skipped lines'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: warnings.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(warnings[i]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
