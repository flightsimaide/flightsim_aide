import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each exception has a non-empty message', () {
    final exceptions = <AppException>[
      ParseFailure('bad line'),
      SourceCancelled(),
      SourceReadFailure('disk error'),
      PluginNotDetected(),
      PluginVersionMismatch(found: 2, required: 1),
      PluginUnreachable(),
      NoChecklistForAircraft(),
      ProtocolError('bad json'),
      InvalidManualIp('abc'),
    ];
    for (final e in exceptions) {
      expect(e.message, isNotEmpty);
    }
  });

  test('SourceCancelled is AppException', () {
    expect(SourceCancelled(), isA<AppException>());
  });

  test('toString includes the type name', () {
    expect(ParseFailure('x').toString(), contains('ParseFailure'));
    expect(SourceCancelled().toString(), contains('SourceCancelled'));
    expect(SourceReadFailure('x').toString(), contains('SourceReadFailure'));
  });

  test('the plugin exceptions are AppExceptions with useful text', () {
    expect(PluginNotDetected(), isA<AppException>());
    expect(PluginVersionMismatch(found: 2, required: 1).message, contains('2'));
    expect(PluginVersionMismatch(found: 2, required: 1).message, contains('1'));
    expect(ProtocolError('bad json').message, contains('bad json'));
    expect(InvalidManualIp('abc').message, contains('abc'));
    expect(PluginUnreachable().toString(), contains('PluginUnreachable'));
    expect(NoChecklistForAircraft().message, isNotEmpty);
    expect(SpeechUnavailable().message, isNotEmpty);
  });

  test('AppException switch is exhaustive without default', () {
    String name(AppException e) => switch (e) {
      ParseFailure() => 'parse',
      SourceCancelled() => 'cancelled',
      SourceReadFailure() => 'read',
      PluginNotDetected() => 'notDetected',
      PluginVersionMismatch() => 'mismatch',
      PluginUnreachable() => 'unreachable',
      NoChecklistForAircraft() => 'noChecklist',
      ProtocolError() => 'protocol',
      InvalidManualIp() => 'ip',
      SpeechUnavailable() => 'speech',
    };
    expect(name(PluginUnreachable()), 'unreachable');
  });
}
