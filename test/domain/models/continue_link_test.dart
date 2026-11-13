import 'package:flightsim_aide/domain/models/checklist/continue_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('next has no target', () {
    const link = ContinueLink.next();
    expect(link.isNext, isTrue);
    expect(link.target, isNull);
  });

  test('named has its target', () {
    const link = ContinueLink.named('LANDING');
    expect(link.isNext, isFalse);
    expect(link.target, 'LANDING');
  });

  test('equality and hashCode', () {
    expect(const ContinueLink.next(), const ContinueLink.next());
    expect(const ContinueLink.named('A'), const ContinueLink.named('A'));
    expect(
      const ContinueLink.named('A').hashCode,
      const ContinueLink.named('A').hashCode,
    );
    expect(const ContinueLink.named('A'), isNot(const ContinueLink.named('B')));
    expect(const ContinueLink.named('A'), isNot(const ContinueLink.next()));
  });
}
