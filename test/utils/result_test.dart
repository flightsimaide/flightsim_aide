import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flightsim_aide/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ok exposes value', () {
    const Result<int> r = Ok(42);
    expect(r.isOk, isTrue);
    expect(r.valueOrNull, 42);
    expect(r.errorOrNull, isNull);
  });

  test('Error exposes error', () {
    final error = ParseFailure('bad');
    final Result<int> r = Error(error);
    expect(r.isOk, isFalse);
    expect(r.errorOrNull, same(error));
  });

  test('pattern match is exhaustive', () {
    const Result<int> r = Ok(1);
    final text = switch (r) {
      Ok(:final value) => 'ok $value',
      Error(:final error) => 'error ${error.message}',
    };
    expect(text, 'ok 1');
  });

  test('valueOrNull is null on Error', () {
    final Result<int> r = Error(SourceCancelled());
    expect(r.valueOrNull, isNull);
  });
}
