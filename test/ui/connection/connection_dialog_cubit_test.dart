import 'package:flightsim_aide/data/repositories/flight_sim/flight_sim_repository_local.dart';
import 'package:flightsim_aide/domain/models/aircraft/aircraft_identity.dart';
import 'package:flightsim_aide/domain/models/flight_sim/connection_status.dart';
import 'package:flightsim_aide/domain/models/flight_sim/discovered_sim.dart';
import 'package:flightsim_aide/domain/models/flight_sim/switch_offer.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_cubit.dart';
import 'package:flightsim_aide/ui/connection/cubit/connection_dialog_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../testing/fakes/repositories/fake_settings_repository.dart';
import '../../../testing/fakes/services/manual_clock.dart';

// Task 0.14: the connection dialog and the Continue / Yes / No flow.

const _cessna = AircraftIdentity(
  icao: 'C172',
  description: 'Cessna 172',
  aircraftPath: 'a.acf',
  checklistPath: 'clist.txt',
  generation: 1,
);

const _offer = SwitchOffer(
  from: DiscoveredSim(host: '192.168.1.10', name: 'WIN'),
  to: DiscoveredSim(host: '192.168.1.117', name: 'MAC'),
);
const _none = ConnectionDialogState(ConnectionDialogKind.none);
const _ask = ConnectionDialogState(ConnectionDialogKind.askNotify);
const _blocking = ConnectionDialogState(ConnectionDialogKind.connection);
const _optional = ConnectionDialogState(
  ConnectionDialogKind.connection,
  canContinue: true,
);

void main() {
  late FlightSimRepositoryLocal sim;
  late ConnectionCubit connection;
  late ConnectionDialogCubit cubit;

  /// Lets the streams deliver.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> status(ConnectionStatus s) async {
    sim.setStatus(s);
    await settle();
  }

  Future<void> connect() async {
    sim.setAircraft(_cessna);
    await status(const ConnectionConnected());
  }

  setUp(() {
    sim = FlightSimRepositoryLocal();
    connection = ConnectionCubit(
      flightSim: sim,
      settings: FakeSettingsRepository(),
      clock: ManualClock(),
    );
    cubit = ConnectionDialogCubit(
      connection: connection,
      runId: () => sim.runId,
    );
  });
  tearDown(() async {
    await cubit.close();
    await connection.close();
    await sim.dispose();
  });

  test('at start, with no checklist, the dialog is up and cannot be left', () {
    expect(cubit.state, _blocking);
  });

  test('connecting closes the dialog', () async {
    await connect();
    expect(cubit.state, _none);
  });

  test(
    'a lost connection with no checklist shows the blocking dialog',
    () async {
      await connect();
      await status(const ConnectionNoNetwork());
      expect(cubit.state, _blocking);
    },
  );

  test('with a checklist the dialog offers Continue', () async {
    await connect();
    cubit.setChecklist(hasChecklist: true, prompting: false);
    await status(const ConnectionSimUnreachable());
    expect(cubit.state, _optional);
  });

  test('Continue removes the dialog and asks the question', () async {
    await connect();
    cubit.setChecklist(hasChecklist: true, prompting: false);
    await status(const ConnectionNoNetwork());
    cubit.continueManually();
    expect(cubit.state, _ask);
  });

  test(
    'Yes: the dialog stays away while down, and opens after a recovery',
    () async {
      await connect();
      cubit.setChecklist(hasChecklist: true, prompting: false);
      await status(const ConnectionNoNetwork());
      cubit.continueManually();
      cubit.answerNotify(notify: true);
      expect(cubit.state, _none);
      await status(const ConnectionSimUnreachable());
      expect(cubit.state, _none);
      await connect();
      await status(const ConnectionNoNetwork());
      expect(cubit.state, _optional);
    },
  );

  test('No: the dialog never opens again for a lost connection', () async {
    await connect();
    cubit.setChecklist(hasChecklist: true, prompting: false);
    await status(const ConnectionNoNetwork());
    cubit.continueManually();
    cubit.answerNotify(notify: false);
    await connect();
    await status(const ConnectionNoNetwork());
    expect(cubit.state, _none);
    expect(cubit.notify, isFalse);
  });

  test('Continue does nothing without a checklist', () {
    cubit.continueManually();
    expect(cubit.state, _blocking);
  });

  test('a new run id asks again after No', () async {
    sim.runId = 'aaaa';
    await connect();
    cubit.setChecklist(hasChecklist: true, prompting: false);
    await status(const ConnectionNoNetwork());
    cubit.continueManually();
    cubit.answerNotify(notify: false);
    await status(const ConnectionSimUnreachable());
    sim.runId = 'bbbb';
    await connect();
    expect(cubit.state, _ask);
    cubit.answerNotify(notify: true);
    expect(cubit.state, _none);
    expect(cubit.notify, isTrue);
  });

  test('the same run id does not ask again', () async {
    sim.runId = 'aaaa';
    await connect();
    cubit.setChecklist(hasChecklist: true, prompting: false);
    await status(const ConnectionNoNetwork());
    cubit.continueManually();
    cubit.answerNotify(notify: false);
    await connect();
    expect(cubit.state, _none);
  });

  test('a new run id does not ask when notification is on', () async {
    sim.runId = 'aaaa';
    await connect();
    cubit.setChecklist(hasChecklist: true, prompting: false);
    await status(const ConnectionNoNetwork());
    sim.runId = 'bbbb';
    await connect();
    expect(cubit.state, _none);
  });

  test('the question waits for the restore question', () async {
    sim.runId = 'aaaa';
    await connect();
    cubit.setChecklist(hasChecklist: true, prompting: false);
    await status(const ConnectionNoNetwork());
    cubit.continueManually();
    cubit.answerNotify(notify: false);
    sim.runId = 'bbbb';
    cubit.setChecklist(hasChecklist: true, prompting: true);
    await connect();
    expect(cubit.state, _none);
    cubit.setChecklist(hasChecklist: true, prompting: false);
    expect(cubit.state, _ask);
  });

  group('aircraft changed', () {
    const boeing = AircraftIdentity(
      icao: 'B738',
      description: 'Boeing 737',
      aircraftPath: 'b.acf',
      checklistPath: 'b.txt',
      generation: 2,
    );
    const piper = AircraftIdentity(
      icao: 'PA28',
      description: 'Piper Archer',
      aircraftPath: 'p.acf',
      generation: 3,
    );

    Future<void> changeTo(AircraftIdentity aircraft) async {
      sim.setAircraft(aircraft);
      await settle();
    }

    Future<void> loadedCessna() async {
      await connect();
      connection.setLoadedAircraft(_cessna);
      cubit.setChecklist(hasChecklist: true, prompting: false);
      await settle();
    }

    test('another aircraft opens the dialog, connected', () async {
      await loadedCessna();
      await changeTo(boeing);
      expect(
        cubit.state,
        const ConnectionDialogState(
          ConnectionDialogKind.aircraftChanged,
          live: boeing,
        ),
      );
    });

    test('Continue closes it for that aircraft only', () async {
      await loadedCessna();
      await changeTo(boeing);
      cubit.continueWithCurrentChecklist();
      expect(cubit.state, _none);
      await changeTo(piper);
      expect(cubit.state.kind, ConnectionDialogKind.aircraftChanged);
      expect(cubit.state.live, piper);
    });

    test('going back to the loaded aircraft forgets the Continue', () async {
      await loadedCessna();
      await changeTo(boeing);
      cubit.continueWithCurrentChecklist();
      await changeTo(_cessna);
      expect(cubit.state, _none);
      await changeTo(boeing);
      expect(cubit.state.kind, ConnectionDialogKind.aircraftChanged);
    });

    test('loading the new checklist closes it', () async {
      await loadedCessna();
      await changeTo(boeing);
      connection.setLoadedAircraft(boeing);
      await settle();
      expect(cubit.state, _none);
    });
  });

  group('switch computer question (task 0.16)', () {
    test('lost connection with an offer asks instead of the panel', () async {
      await connect();
      await status(const ConnectionSimUnreachable());
      sim.setSwitchOffer(_offer);
      await settle();
      expect(
        cubit.state,
        const ConnectionDialogState(
          ConnectionDialogKind.switchComputer,
          offer: _offer,
        ),
      );
    });

    test('an offer while connected shows nothing', () async {
      await connect();
      sim.setSwitchOffer(_offer);
      await settle();
      expect(cubit.state, _none);
    });

    test('answering No returns to the connection dialog', () async {
      await connect();
      await status(const ConnectionSimUnreachable());
      sim.setSwitchOffer(_offer);
      await settle();
      await connection.answerSwitch(accept: false);
      await settle();
      expect(cubit.state, _blocking);
      expect(sim.switchAnswers, [false]);
    });

    test('after Continue in manual mode there is no dialog', () async {
      await connect();
      cubit.setChecklist(hasChecklist: true, prompting: false);
      await status(const ConnectionSimUnreachable());
      cubit.continueManually();
      cubit.answerNotify(notify: false);
      sim.setSwitchOffer(_offer);
      await settle();
      expect(cubit.state, _none);
    });

    test('with a checklist and notification on, the question opens', () async {
      await connect();
      cubit.setChecklist(hasChecklist: true, prompting: false);
      await status(const ConnectionSimUnreachable());
      sim.setSwitchOffer(_offer);
      await settle();
      expect(cubit.state.kind, ConnectionDialogKind.switchComputer);
    });
  });
}
