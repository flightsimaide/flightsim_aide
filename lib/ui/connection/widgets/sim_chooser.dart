import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/models/flight_sim/discovered_sim.dart';
import '../cubit/connection_cubit.dart';
import 'connection_messages.dart';

/// A list of the simulators seen on the network; tapping one connects to it.
/// Shown only when there are two or more, so there is a real choice.
class SimChooser extends StatefulWidget {
  /// Creates the list. [selectedHost] is marked as the chosen sim.
  const SimChooser({
    required this.sims,
    this.selectedHost,
    this.from,
    this.lost = false,
    super.key,
  });

  /// When set, the list is of the other computers while connected to [from]:
  /// one is enough to be listed, and a tap asks whether to switch to it.
  final DiscoveredSim? from;

  /// With [from]: the connection to it is lost, so the question says "were".
  final bool lost;

  /// The simulators to offer.
  final List<DiscoveredSim> sims;

  /// The host of the sim chosen earlier, if any.
  final String? selectedHost;

  @override
  State<SimChooser> createState() => _SimChooserState();
}

class _SimChooserState extends State<SimChooser> {
  late String? _selected = widget.selectedHost;

  @override
  Widget build(BuildContext context) {
    final sims = widget.sims;
    final others = widget.from != null;
    if (sims.length < (others ? 1 : 2)) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          others
              ? 'Other computers with X-Plane:'
              : 'Several X-Plane computers answered. Choose one:',
        ),
        for (final sim in sims) _entry(context, sim, others: others),
      ],
    );
  }

  /// One computer. Among the other computers it is a bordered rectangle with
  /// an empty circle in front, so it reads as a choice to tap.
  Widget _entry(
    BuildContext context,
    DiscoveredSim sim, {
    required bool others,
  }) {
    final tile = ListTile(
      minVerticalPadding: 12,
      leading: Icon(
        !others && sim.host == _selected
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
      ),
      title: Text(sim.name ?? sim.host),
      subtitle: _details(sim, tapped: sim.host == _selected),
      selected: sim.host == _selected,
      onTap: () => others ? _askSwitch(sim) : _choose(sim),
    );
    if (!others) return tile;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: tile,
      ),
    );
  }

  void _choose(DiscoveredSim sim) {
    setState(() => _selected = sim.host);
    context.read<ConnectionCubit>().selectSim(sim);
  }

  /// While connected, moving to another computer is asked first.
  Future<void> _askSwitch(DiscoveredSim sim) async {
    final cubit = context.read<ConnectionCubit>();
    final from = widget.from!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch computer?'),
        content: Text(
          'You ${widget.lost ? 'were' : 'are'} connected to ${computerLabel(from)}. '
          'Do you want to switch to ${computerLabel(sim)}?',
        ),
        actions: [
          TextButton(
            key: const Key('switch-from-list-no'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            key: const Key('switch-from-list-yes'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (yes ?? false) await cubit.selectSim(sim);
  }

  /// The address (when the name is the title) and the facts known about the
  /// computer. With no OS and no simulator known, only a status word: nothing
  /// is guessed.
  Widget? _details(DiscoveredSim sim, {required bool tapped}) {
    final facts = [?sim.os?.displayName, ?sim.simulator?.displayName];
    final lines = [
      if (sim.name != null) sim.host,
      if (facts.isNotEmpty)
        facts.join(' · ')
      else if (widget.from != null)
        sim.host
      else if (tapped)
        'Connecting'
      else
        'Waiting for connection',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final line in lines) Text(line)],
    );
  }
}
