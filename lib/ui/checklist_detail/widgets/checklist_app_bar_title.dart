import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/models/aircraft/aircraft_identity.dart';
import '../../connection/cubit/connection_cubit.dart';
import '../../connection/cubit/connection_state.dart';

/// Finds the aircraft line under the checklist name, for tests.
const aircraftLineKey = ValueKey<String>('checklist-aircraft-line');

/// The aircraft as the home page shows it: `Pilatus PC-12/47 (PC12)`, or the
/// description alone when the ICAO code is empty.
String aircraftTitle(AircraftIdentity aircraft) => aircraft.icao.isEmpty
    ? aircraft.description
    : '${aircraft.description} (${aircraft.icao})';

/// The title of the checklist app bar: the checklist name centred, and under
/// it the aircraft in a smaller, fainter style. Both stay on one line and end
/// in an ellipsis when too long. Without a connection (file and sample
/// sources) or an aircraft, only the name shows.
class ChecklistAppBarTitle extends StatelessWidget {
  /// Creates the title for the checklist called [title].
  const ChecklistAppBarTitle({required this.title, super.key});

  /// The checklist name.
  final String title;

  @override
  Widget build(BuildContext context) {
    final ConnectionCubit cubit;
    try {
      cubit = context.read<ConnectionCubit>();
    } on ProviderNotFoundException {
      return _build(context, null);
    }
    return BlocBuilder<ConnectionCubit, ConnectionViewState>(
      bloc: cubit,
      builder: (context, state) => _build(context, switch (state) {
        LinkConnected(:final aircraft) => aircraft,
        // The checklist on screen belongs to the loaded aircraft.
        LinkAircraftChanged(:final loaded) => loaded,
        _ => null,
      }),
    );
  }

  Widget _build(BuildContext context, AircraftIdentity? aircraft) {
    final theme = Theme.of(context);
    final text = aircraft == null ? '' : aircraftTitle(aircraft);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        if (text.isNotEmpty)
          Text(
            text,
            key: aircraftLineKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
