import 'package:flightsim_aide/data/parsers/aircraft_workflow_parser.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist.dart';
import 'package:flightsim_aide/domain/models/checklist/checklist_progress.dart';
import 'package:flightsim_aide/domain/models/voice/voice_prompt.dart';
import 'package:flightsim_aide/domain/models/voice/voice_settings.dart';
import 'package:flightsim_aide/domain/use_cases/voice/build_voice_prompt_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

// The prompt after a step (D-84, GRAMMAR.md section 5d).
// AC-60

const useCase = BuildVoicePromptUseCase();
const both = VoiceSettings(flows: true, challenges: true);

Checklist list(String body) => const AircraftWorkflowParser()
    .parse('sw_checklist:A\n$body')
    .checklists
    .single;

ChecklistProgress done(Iterable<int> indexes, {int cursor = 0}) =>
    ChecklistProgress.marks(
      checked: {'A': indexes.toSet()},
      cursor: {'A': cursor},
    );

VoicePrompt after(
  Checklist checklist,
  ChecklistProgress progress, {
  VoiceSettings settings = both,
  List<int> auto = const [],
}) => useCase.afterStep(
  checklist: checklist,
  progress: progress,
  settings: settings,
  autoChecked: auto,
);

void main() {
  const challenge = 'sw_challenge: ON\n';
  const flow = 'sw_challenge: OFF\n';

  group('the next row', () {
    test('a flow row is read as its label and result and waited for', () {
      final p = after(list('sw_item:Parking brake|SET'), done([]));
      expect(p.text, 'Parking brake, SET');
      expect(p.waitingFor, 0);
      expect(p.waitingForChallenge, isFalse);
    });

    test('a challenge row is read as its challenge only', () {
      final p = after(
        list('${challenge}sw_item:Parking brake|SET\n$flow'),
        done([]),
      );
      expect(p.text, 'Parking brake');
      expect(p.waitingFor, 0);
      expect(p.waitingForChallenge, isTrue);
    });

    test('headings, notes, details and ticked or skipped rows are passed', () {
      final c = list(
        'sw_item:One|ON\nsw_iteminfo:Note\nsw_item_heading:Head\n'
        'sw_item_details:More\nsw_item:Two|ON\nsw_item:Three|ON',
      );
      final progress = ChecklistProgress.marks(
        checked: {
          'A': {0},
        },
        skipped: {
          'A': {4},
        },
      );
      expect(after(c, progress).waitingFor, 5);
    });

    test('an item hidden by a switch is passed', () {
      final c = list(
        'sw_switch:GPU|gpu|OFF\nsw_item:Connect GPU|ON\nsw_else\n'
        'sw_item:Nothing|ON\nsw_end',
      );
      expect(after(c, done([0])).waitingFor, 2);
    });

    test('a row with no result is read as its label', () {
      expect(after(list('sw_item:Doors'), done([])).text, 'Doors');
    });

    test('long capital words are read as words, short ones are kept', () {
      final p = after(list('sw_item:ENG FIRE test|AVAILABLE'), done([]));
      expect(p.text, 'ENG fire test, available');
    });
  });

  group('the end', () {
    test('says the checklist is complete when every row is ticked', () {
      final c = list('sw_item:One|ON\nsw_item:Two|ON');
      final p = after(c, done([0, 1]));
      expect(p.text, 'Checklist complete');
      expect(p.complete, isTrue);
      expect(p.waitingFor, isNull);
    });

    test('a skipped row counts as done', () {
      final c = list('sw_item:One|ON\nsw_item:Two|ON');
      final progress = ChecklistProgress.marks(
        checked: {
          'A': {0},
        },
        skipped: {
          'A': {1},
        },
      );
      expect(after(c, progress).complete, isTrue);
    });
  });

  group('auto-checked challenge rows', () {
    final c = list(
      '${challenge}sw_item:Beacon|ON\nsw_item:Strobes|ON\nsw_item:Nav|ON\n'
      'sw_item:Taxi|ON\n${flow}sw_item:Flaps|SET',
    );

    test('one row is said as challenge, a pause, then the response', () {
      final p = after(c, done([0], cursor: 1), auto: [0]);
      expect(p.utterances.take(2), [
        const VoiceUtterance(
          'Beacon',
          pauseAfter: BuildVoicePromptUseCase.challengePause,
        ),
        const VoiceUtterance('ON'),
      ]);
      expect(p.waitingFor, 1);
      expect(p.text, 'Beacon ON Strobes');
    });

    test('two rows are both said in full', () {
      final p = after(c, done([0, 1], cursor: 2), auto: [0, 1]);
      expect(p.text, 'Beacon ON Strobes ON Nav');
    });

    test('three or more are counted, then the next is read', () {
      final p = after(c, done([0, 1, 2], cursor: 3), auto: [0, 1, 2]);
      expect(p.text, '3 verified Taxi');
      expect(p.waitingFor, 3);
      final four = after(c, done([0, 1, 2, 3], cursor: 4), auto: [0, 1, 2, 3]);
      expect(four.text, '4 verified Flaps, SET');
      expect(four.waitingForChallenge, isFalse);
    });

    test('flow rows ticked by auto are not spoken or counted', () {
      final f = list(
        'sw_item:One|ON\nsw_item:Two|ON\nsw_item:Three|ON\nsw_item:Four|ON',
      );
      final p = after(f, done([0, 1, 2], cursor: 3), auto: [0, 1, 2]);
      expect(p.text, 'Four, ON');
    });

    test('with challenges off nothing is said for them', () {
      final p = after(
        c,
        done([0], cursor: 1),
        auto: [0],
        settings: const VoiceSettings(flows: true),
      );
      expect(p.text, '');
      expect(p.waitingFor, isNull);
    });
  });

  group('the settings', () {
    test('both off is silent', () {
      final p = after(
        list('sw_item:One|ON'),
        done([]),
        settings: const VoiceSettings(),
      );
      expect(p, VoicePrompt.silent);
      expect(const VoiceSettings().any, isFalse);
    });

    test('flows off: a flow row is not spoken or waited for', () {
      final p = after(
        list('sw_item:One|ON'),
        done([]),
        settings: const VoiceSettings(challenges: true),
      );
      expect(p.utterances, isEmpty);
      expect(p.waitingFor, isNull);
    });

    test('challenges off: a challenge row is not spoken or waited for', () {
      final p = after(
        list('${challenge}sw_item:One|ON\n$flow'),
        done([]),
        settings: const VoiceSettings(flows: true),
      );
      expect(p.utterances, isEmpty);
      expect(p.waitingFor, isNull);
    });
  });

  group('the other prompts', () {
    test('double check names the item', () {
      final item = list('sw_item:Parking brake|SET').items.single;
      expect(useCase.doubleCheck(item).text, 'Double check Parking brake');
    });

    test('did you mean reads the phrase back', () {
      expect(useCase.didYouMean('check').text, 'Did you mean check?');
    });
  });
}
