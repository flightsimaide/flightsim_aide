import 'package:flutter/material.dart';

import '../../core/widgets/status_pill.dart';
import '../cubit/checklist_list_state.dart';

/// One row of the checklist list: title, progress and a completion marker.
class ChecklistListTile extends StatelessWidget {
  /// Creates a tile for [summary]; [onTap] opens the checklist.
  const ChecklistListTile({
    required this.summary,
    required this.onTap,
    super.key,
  });

  /// The checklist shown by this tile.
  final ChecklistSummary summary;

  /// Called when the tile is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label:
          '${summary.title}, ${summary.done} of ${summary.total} complete'
          '${summary.skipped > 0 ? ', ${summary.skipped} skipped' : ''}'
          '${summary.overridden > 0 ? ', ${summary.overridden} overridden' : ''}',
      onTap: onTap,
      child: ListTile(
        minTileHeight: 48,
        title: Text(summary.title),
        subtitle: Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${summary.done} / ${summary.total}'),
            if (summary.isComplete)
              const StatusPill(status: PillStatus.good, text: 'Complete'),
            if (summary.skipped > 0)
              StatusPill(
                status: PillStatus.caution,
                text: '${summary.skipped} skipped',
              ),
            if (summary.overridden > 0)
              StatusPill(
                status: PillStatus.warning,
                text: '${summary.overridden} overridden',
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
