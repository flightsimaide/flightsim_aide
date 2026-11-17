import 'package:flightsim_aide/domain/models/voice/spoken_input.dart';
import 'package:flightsim_aide/domain/use_cases/voice/match_spoken_response_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

// Spoken answers (D-84, GRAMMAR.md section 5d).
// AC-59

void main() {
  const useCase = MatchSpokenResponseUseCase();

  group('exact answers', () {
    for (final word in ['check', 'set', 'on', 'off', 'closed']) {
      test('"$word" is an answer, in any case and with punctuation', () {
        expect(useCase.match(word), SpokenAnswer(word));
        expect(useCase.match('  ${word.toUpperCase()}! '), SpokenAnswer(word));
      });
    }

    test('the item result is an answer too', () {
      expect(
        useCase.match('as required', itemResult: 'AS REQUIRED'),
        const SpokenAnswer('as required'),
      );
      expect(
        useCase.match('Available.', itemResult: 'AVAILABLE'),
        const SpokenAnswer('available'),
      );
    });

    test('a result is not an answer for an item that does not have it', () {
      expect(useCase.match('available'), const SpokenUnknown());
    });
  });

  group('commands', () {
    test('skip skips', () {
      expect(useCase.match('skip'), const SpokenSkip());
    });

    test('pause checklist pauses', () {
      expect(useCase.match('Pause checklist'), const SpokenPause());
      expect(useCase.match('hold checklist'), const SpokenPause());
    });

    test('resume checklist and continue checklist resume', () {
      expect(useCase.match('resume checklist'), const SpokenResume());
      expect(useCase.match('continue checklist'), const SpokenResume());
      expect(useCase.match('unpause checklist'), const SpokenResume());
    });

    test('a bare continue or pause is not a command', () {
      expect(useCase.match('continue'), const SpokenUnknown());
      expect(useCase.match('pause'), isNot(isA<SpokenPause>()));
    });

    test('yes and no answer a question', () {
      expect(useCase.match('yes'), const SpokenYes());
      expect(useCase.match('Yeah'), const SpokenYes());
      expect(useCase.match('no'), const SpokenNo());
      expect(useCase.match('negative'), const SpokenNo());
    });
  });

  group('did you mean', () {
    test('one slip in a short word is a close match', () {
      expect(
        useCase.match('chek'),
        const SpokenCloseMatch('check', SpokenAnswer('check')),
      );
      expect(
        useCase.match('closd'),
        const SpokenCloseMatch('closed', SpokenAnswer('closed')),
      );
    });

    test('a close command is offered with what it would do', () {
      expect(
        useCase.match('pause checkist'),
        const SpokenCloseMatch('pause checklist', SpokenPause()),
      );
      expect(
        useCase.match('skp'),
        const SpokenCloseMatch('skip', SpokenSkip()),
      );
    });

    test('a close result is offered', () {
      expect(
        useCase.match('as requird', itemResult: 'AS REQUIRED'),
        const SpokenCloseMatch('as required', SpokenAnswer('as required')),
      );
    });

    test('a word under three letters must be exact', () {
      expect(useCase.match('of'), const SpokenUnknown());
      expect(useCase.match('n'), const SpokenUnknown());
    });

    test('two slips in a short word are not close', () {
      expect(useCase.match('chunk'), const SpokenUnknown());
    });

    test('the closest phrase wins', () {
      expect(
        useCase.match('sit'),
        const SpokenCloseMatch('set', SpokenAnswer('set')),
      );
    });
  });

  group('nothing understood', () {
    test('an empty phrase or noise is unknown', () {
      expect(useCase.match(''), const SpokenUnknown());
      expect(useCase.match('  ...  '), const SpokenUnknown());
      expect(useCase.match('banana split'), const SpokenUnknown());
    });
  });
}
