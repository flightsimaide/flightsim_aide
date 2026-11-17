import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/repositories/checklist/checklist_progress_repository_impl.dart';
import '../data/repositories/flight_sim/flight_sim_repository.dart';
import '../data/repositories/settings/settings_repository.dart';
import '../data/repositories/voice/voice_repository.dart';
import '../data/repositories/voice/voice_repository_impl.dart';
import '../data/services/local/progress_storage_service.dart';
import '../data/services/voice/flutter_tts_speech_output_service.dart';
import '../data/services/voice/speech_to_text_input_service.dart';
import 'dependencies.dart';
import 'network_link.dart';

/// Builds the network services behind the checklist source: the companion
/// plugin at [simIp] when [discover] is false, else found by beacon.
///
/// Nothing is started here; see [productionProviders].
NetworkLink productionLink({
  String simIp = '127.0.0.1',
  bool discover = false,
}) => NetworkLink(simIp: simIp, discover: discover);

/// Production wiring: the companion plugin, with the sim's address from
/// `--dart-define=SIM_IP=192.168.x.y`, or found by beacon when that is left
/// empty. The link starts when the providers are built unless [startLink] is
/// false. Progress is saved per aircraft with the plugin's run id (D-35).
List<RepositoryProvider<dynamic>> productionProviders({
  String simIp = const String.fromEnvironment('SIM_IP', defaultValue: ''),
  bool startLink = true,
}) {
  final link = productionLink(
    simIp: simIp.isEmpty ? '127.0.0.1' : simIp,
    discover: simIp.isEmpty,
  );
  return [
    RepositoryProvider<FlightSimRepository>.value(
      value: link.flightSimRepository,
    ),
    RepositoryProvider<SettingsRepository>.value(value: link.settings),
    RepositoryProvider<VoiceRepository>(
      create: (_) => VoiceRepositoryImpl(
        output: FlutterTtsSpeechOutputService(),
        input: SpeechToTextInputService(),
      ),
    ),
    RepositoryProvider<NetworkLink>(
      lazy: false,
      create: (_) {
        if (startLink) link.start();
        return link;
      },
      dispose: (link) => link.dispose(),
    ),
    ...sharedProviders(
      link.source,
      progress: () => ChecklistProgressRepositoryImpl(
        storage: FileProgressStorageService.inApplicationSupport(),
      ),
    ),
  ];
}
