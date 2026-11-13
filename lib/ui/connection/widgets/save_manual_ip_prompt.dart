import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/connection_cubit.dart';

/// Asks, on any screen, whether to keep a typed IP address once it has
/// connected, so only addresses that work are saved. Needs a
/// [ConnectionCubit] above it.
class SaveManualIpPrompt extends StatefulWidget {
  /// Creates the prompt around [child].
  const SaveManualIpPrompt({required this.child, super.key});

  /// The routed screen.
  final Widget child;

  @override
  State<SaveManualIpPrompt> createState() => _SaveManualIpPromptState();
}

class _SaveManualIpPromptState extends State<SaveManualIpPrompt> {
  StreamSubscription<String>? _offers;
  late ConnectionCubit _cubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cubit = context.read<ConnectionCubit>();
    if (_offers != null && identical(cubit, _cubit)) return;
    _cubit = cubit;
    _offers?.cancel();
    _offers = cubit.saveOffers.listen(_ask);
  }

  @override
  void dispose() {
    _offers?.cancel();
    super.dispose();
  }

  Future<void> _ask(String address) async {
    if (!mounted) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Save IP address?'),
        content: Text(
          'FlightSim Aide connected to X-Plane at $address. '
          'Save this IP address to use it every time?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save == true) await _cubit.saveManualIp(address);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
