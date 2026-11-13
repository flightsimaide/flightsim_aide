import 'package:flightsim_aide/domain/models/checklist/progress_restore_policy.dart';
import 'package:flutter_test/flutter_test.dart';

RestoreAction decide({
  bool hasSaved = true,
  String? savedRunId = 'run-1',
  String? runId = 'run-1',
}) => ProgressRestorePolicy.decide(
  hasSaved: hasSaved,
  savedRunId: savedRunId,
  runId: runId,
);

void main() {
  test('no saved marks gives nothing, whatever the run ids', () {
    expect(decide(hasSaved: false), RestoreAction.nothing);
    expect(decide(hasSaved: false, runId: 'run-2'), RestoreAction.nothing);
  });

  test('the same run id restores silently', () {
    expect(decide(), RestoreAction.restore);
  });

  test('a different run id asks', () {
    expect(decide(runId: 'run-2'), RestoreAction.prompt);
  });

  test('an unknown run id, saved or current, asks', () {
    expect(decide(runId: null), RestoreAction.prompt);
    expect(decide(savedRunId: null), RestoreAction.prompt);
    expect(decide(savedRunId: null, runId: null), RestoreAction.prompt);
  });

  group('reconnect', () {
    ReconnectAction r(String? last, String? now) =>
        ProgressRestorePolicy.decideReconnect(lastRunId: last, runId: now);

    test('the same run id keeps', () {
      expect(r('run-1', 'run-1'), ReconnectAction.keep);
    });

    test('a different run id asks', () {
      expect(r('run-1', 'run-2'), ReconnectAction.prompt);
    });

    test('an unknown run id asks', () {
      expect(r('run-1', null), ReconnectAction.prompt);
      expect(r(null, 'run-1'), ReconnectAction.prompt);
    });
  });
}
