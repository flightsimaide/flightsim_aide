import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../utils/app_exception.dart';
import '../../../utils/result.dart';
import 'model/plugin_endpoint.dart';
import 'model/raw_aircraft_info.dart';
import 'model/raw_checklist_response.dart';
import 'model/raw_hello.dart';

/// The protocol version this app speaks.
const requiredProtocolVersion = 1;

/// The companion plugin's plain-HTTP API (`plugin/PROTOCOL.md` sections 2, 4
/// and 5). Every method returns a [Result]; nothing throws.
abstract class CompanionPluginService {
  /// `GET /v1/hello` on [host]:[port]. Returns the answer whatever protocol
  /// version it carries; the caller decides what a mismatch means.
  Future<Result<RawHello>> getHello(String host, int port);

  /// `GET /v1/aircraft`. A protocol version other than
  /// [requiredProtocolVersion] is a [PluginVersionMismatch].
  Future<Result<RawAircraftInfo>> getAircraft(PluginEndpoint endpoint);

  /// `GET /v1/checklist`, sending `If-None-Match` when [ifNoneMatch] is given.
  /// A `404` is [NoChecklistForAircraft].
  Future<Result<RawChecklistFetch>> getChecklist(
    PluginEndpoint endpoint, {
    String? ifNoneMatch,
  });
}

/// [CompanionPluginService] over `package:http`.
class HttpCompanionPluginService implements CompanionPluginService {
  /// Creates the service. [client] is injected so tests can stub it.
  HttpCompanionPluginService({
    required this.client,
    this.timeout = const Duration(seconds: 3),
  });

  /// The HTTP client; injected so tests can stub it.
  final http.Client client;

  /// How long one request may take before it counts as unreachable.
  final Duration timeout;

  /// Closes the HTTP client.
  void dispose() => client.close();

  @override
  Future<Result<RawHello>> getHello(String host, int port) async {
    final response = await _get(
      Uri(scheme: 'http', host: host, port: port, path: '/v1/hello'),
    );
    return switch (response) {
      Error(:final error) => Error(error),
      Ok(:final value) => _parse(value, _hello),
    };
  }

  @override
  Future<Result<RawAircraftInfo>> getAircraft(PluginEndpoint endpoint) async {
    final response = await _get(endpoint.baseUri.replace(path: '/v1/aircraft'));
    return switch (response) {
      Error(:final error) => Error(error),
      Ok(:final value) => _parse(value, _aircraft),
    };
  }

  @override
  Future<Result<RawChecklistFetch>> getChecklist(
    PluginEndpoint endpoint, {
    String? ifNoneMatch,
  }) async {
    final response = await _get(
      endpoint.baseUri.replace(path: '/v1/checklist'),
      headers: {'If-None-Match': ?ifNoneMatch},
    );
    return switch (response) {
      Error(:final error) => Error(error),
      Ok(:final value) => _checklist(value),
    };
  }

  Future<Result<http.Response>> _get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    try {
      final response = await client.get(uri, headers: headers).timeout(timeout);
      return Ok(response);
    } on TimeoutException {
      return Error(PluginUnreachable());
    } on SocketException catch (e) {
      return Error(PluginUnreachable(noRouteToHost: _isNoRoute(e)));
    } on http.ClientException catch (e) {
      return Error(PluginUnreachable(noRouteToHost: _isNoRoute(e)));
    } on HttpException {
      return Error(PluginUnreachable());
    }
  }

  /// errno 65 is `EHOSTUNREACH` on Apple platforms. `package:http` wraps the
  /// socket error in a `ClientException`, keeping only its text.
  static bool _isNoRoute(Object error) => switch (error) {
    SocketException(:final osError) => osError?.errorCode == 65,
    http.ClientException(:final message) => message.contains('errno = 65'),
    _ => false,
  };

  Result<T> _parse<T>(
    http.Response response,
    T Function(Map<String, Object?>) build,
  ) {
    if (response.statusCode != 200) {
      return Error(ProtocolError('HTTP ${response.statusCode}'));
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return Error(ProtocolError('the body is not valid JSON'));
    }
    if (json is! Map<String, Object?>) {
      return Error(ProtocolError('the body is not a JSON object'));
    }
    try {
      return Ok(build(json));
    } on AppException catch (e) {
      return Error(e);
    }
  }

  RawHello _hello(Map<String, Object?> json) {
    final version = _int(json, 'protocolVersion');
    final port = _int(json, 'port');
    final streamPath = _string(json, 'streamPath');
    final sim = json['sim'];
    final simMap = sim is Map<String, Object?>
        ? sim
        : const <String, Object?>{};
    return RawHello(
      protocolVersion: version,
      port: port,
      streamPath: streamPath,
      runId: _string(json, 'runId'),
      simKind: _optString(simMap['kind']),
      simVersion: _optString(simMap['version']),
      os: _optString(json['os']),
      pluginVersion: _optString(json['pluginVersion']),
    );
  }

  RawAircraftInfo _aircraft(Map<String, Object?> json) {
    final version = _int(json, 'protocolVersion');
    if (version != requiredProtocolVersion) {
      throw PluginVersionMismatch(
        found: version,
        required: requiredProtocolVersion,
      );
    }
    return RawAircraftInfo(
      protocolVersion: version,
      generation: _int(json, 'generation'),
      icao: _optString(json['icao']) ?? '',
      description: _optString(json['description']) ?? '',
      aircraftPath: _string(json, 'aircraftPath'),
      checklistPath: _optString(json['checklistPath']),
      checklistModified: _optInt(json['checklistModified']),
      checklistSize: _optInt(json['checklistSize']),
    );
  }

  Result<RawChecklistFetch> _checklist(http.Response response) {
    switch (response.statusCode) {
      case 304:
        return const Ok(NotModified());
      case 404:
        return Error(NoChecklistForAircraft());
      case 200:
        final etag = response.headers['etag'];
        final generation = int.tryParse(
          response.headers['x-aircraft-generation'] ?? '',
        );
        if (etag == null || generation == null) {
          return Error(
            ProtocolError('the checklist answer lacks ETag or generation'),
          );
        }
        return Ok(
          RawChecklistResponse(
            bytes: response.bodyBytes,
            etag: etag,
            generation: generation,
          ),
        );
      default:
        return Error(ProtocolError('HTTP ${response.statusCode}'));
    }
  }

  static int _int(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is int) return value;
    throw ProtocolError('"$key" is missing or not an integer');
  }

  static String _string(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is String) return value;
    throw ProtocolError('"$key" is missing or not a string');
  }

  static String? _optString(Object? value) => value is String ? value : null;

  static int? _optInt(Object? value) => value is int ? value : null;
}
