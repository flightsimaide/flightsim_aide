import 'package:flightsim_aide/config/network_link.dart';
import 'package:flightsim_aide/domain/models/settings/user_options.dart';
import 'package:flutter_test/flutter_test.dart';

// AC-39: --dart-define STREAM_RATE_HZ sets the option

void main() {
  test('no defines leave the options alone', () {
    const stored = UserOptions.defaults;
    expect(optionsWithOverrides(stored), stored);
  });

  test('a rate define replaces the stored rate, clamped', () {
    expect(
      optionsWithOverrides(UserOptions.defaults, streamRateHz: 20).streamRateHz,
      20,
    );
    expect(
      optionsWithOverrides(
        UserOptions.defaults,
        streamRateHz: 900,
      ).streamRateHz,
      60,
    );
  });
}
