import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/connection_cubit.dart';
import 'manual_ip_dialog.dart';

/// What happens when the user presses Cancel while waiting for the aircraft:
/// a question whether to keep waiting. Yes keeps waiting; No stops and opens
/// the IP address dialog, and cancelling that goes back to waiting. Needs a
/// [ConnectionCubit] above [context].
Future<void> showCancelConnectingFlow(BuildContext context) async {
  final cubit = context.read<ConnectionCubit>();
  final stop = await showDialog<bool>(
    context: context,
    builder: (_) => const _KeepWaitingDialog(),
  );
  if (stop != true || !context.mounted) return;
  await cubit.cancelConnecting();
  if (!context.mounted) return;
  final changed = await showManualIpDialog(context);
  if (!changed) await cubit.resumeConnecting();
}

class _KeepWaitingDialog extends StatelessWidget {
  const _KeepWaitingDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: const Text(
        'FlightSim Aide is waiting for the aircraft to load. '
        'Continue waiting on aircraft.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('No'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Yes'),
        ),
      ],
    );
  }
}
