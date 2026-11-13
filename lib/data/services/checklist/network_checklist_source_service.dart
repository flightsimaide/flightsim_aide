import 'dart:async';
import 'dart:typed_data';

import '../../../utils/app_exception.dart';
import '../../../utils/result.dart';
import '../../../utils/text_decoding.dart';
import '../flight_sim/companion_plugin_service.dart';
import '../flight_sim/model/plugin_endpoint.dart';
import '../flight_sim/model/plugin_session.dart';
import '../flight_sim/model/raw_aircraft_info.dart';
import '../flight_sim/model/raw_checklist_response.dart';
import '../flight_sim/plugin_session_source.dart';
import '../local/checklist_cache_service.dart';
import '../local/model/cached_checklist.dart';
import 'checklist_source_service.dart';
import 'model/raw_checklist_document.dart';

/// How many times a load may start over because the aircraft or its file
/// changed between reading the session and fetching the checklist.
const _maxAttempts = 3;

/// [ChecklistSourceService] that gets the loaded aircraft's checklist from the
/// companion plugin, through a per-aircraft cache.
///
/// It never fetches `/v1/aircraft` itself (D-15): the aircraft comes from
/// the [PluginSessionSource]. It never returns `SourceCancelled`, because
/// there is nothing for the user to cancel.
class NetworkChecklistSourceService implements ChecklistSourceService {
  /// Creates the source.
  ///
  /// After a response that does not match the session (the aircraft or file
  /// changed in between), the source waits up to [sessionWait] for the next
  /// session and then asks the session source to reload.
  NetworkChecklistSourceService({
    required this.sessions,
    required this.companion,
    required this.cache,
    this.sessionWait = const Duration(seconds: 3),
  });

  /// Where the current aircraft comes from.
  final PluginSessionSource sessions;

  /// The plugin's HTTP API (checklist only).
  final CompanionPluginService companion;

  /// Where checklist text is kept between runs.
  final ChecklistCacheService cache;

  /// How long to wait for the next session after a mismatch.
  final Duration sessionWait;

  @override
  Future<Result<RawChecklistDocument>> load() async {
    var session = sessions.current;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      if (session == null) return Error(PluginNotDetected());
      final aircraft = session.aircraft;
      final modified = aircraft.checklistModified;
      final size = aircraft.checklistSize;
      final path = aircraft.checklistPath;
      if (modified == null || size == null || path == null) {
        return Error(NoChecklistForAircraft());
      }

      final cached = await cache.read(aircraft.aircraftPath);
      if (cached != null && cached.mtime == modified && cached.size == size) {
        return Ok(_document(aircraft, cached.bytes));
      }

      final fetched = await companion.getChecklist(
        PluginEndpoint(host: session.host, port: session.port),
        ifNoneMatch: cached == null ? null : '"${cached.mtime}-${cached.size}"',
      );
      switch (fetched) {
        case Error(:final error):
          return Error(error);
        case Ok(value: NotModified()):
          return cached == null
              ? Error(
                  ProtocolError('the plugin answered 304 to a plain request'),
                )
              : Ok(_document(aircraft, cached.bytes));
        case Ok(value: final RawChecklistResponse response):
          if (response.etag == '"$modified-$size"' &&
              response.generation == session.generation) {
            await cache.write(
              aircraft.aircraftPath,
              CachedChecklist(
                bytes: response.bytes,
                checklistPath: path,
                mtime: modified,
                size: size,
              ),
            );
            return Ok(_document(aircraft, response.bytes));
          }
      }

      if (attempt == _maxAttempts) break;
      final next = await _nextSession(session);
      switch (next) {
        case Error(:final error):
          return Error(error);
        case Ok(:final value):
          session = value;
      }
    }
    return Error(ProtocolError('the aircraft or its checklist kept changing'));
  }

  RawChecklistDocument _document(RawAircraftInfo aircraft, Uint8List bytes) {
    final name = aircraft.description.isNotEmpty
        ? aircraft.description
        : aircraft.icao.isNotEmpty
        ? aircraft.icao
        : 'checklist';
    return RawChecklistDocument(name: name, text: decodeChecklistText(bytes));
  }

  /// The session that follows [old]: one that is already there, one that
  /// arrives within [sessionWait], or the result of a reload.
  Future<Result<PluginSession>> _nextSession(PluginSession old) async {
    final now = sessions.current;
    if (now != null && now != old) return Ok(now);
    final arrived = Completer<PluginSession?>();
    final subscription = sessions.changes.listen((s) {
      if (s != null && s != old && !arrived.isCompleted) arrived.complete(s);
    });
    final timer = Timer(sessionWait, () {
      if (!arrived.isCompleted) arrived.complete(null);
    });
    final next = await arrived.future;
    timer.cancel();
    await subscription.cancel();
    if (next != null) return Ok(next);
    return sessions.reload();
  }
}
