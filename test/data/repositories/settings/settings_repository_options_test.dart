import 'package:flightsim_aide/data/repositories/settings/settings_repository_impl.dart';
import 'package:flightsim_aide/domain/models/settings/user_options.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../testing/fakes/services/in_memory_preferences_service.dart';

// AC-39: the stream rate option: default 5, clamped to 1 to 60, persisted, observable
// AC-40: the options mechanism is general; a corrupt stored value gives the default

void main() {
  late InMemoryPreferencesService prefs;
  late SettingsRepositoryImpl repo;

  setUp(() {
    prefs = InMemoryPreferencesService();
    repo = SettingsRepositoryImpl(preferences: prefs);
  });

  group('defaults and clamping', () {
    test('the defaults are 5 Hz and auto mode on', () {
      expect(repo.options.streamRateHz, 5);
      expect(repo.options.autoMode, isTrue);
      expect(repo.options, UserOptions.defaults);
    });

    test('a rate is clamped to 1 to 60', () async {
      var o = await repo.update(
        (o) => o.set(UserOptions.streamRateHzOption, 500),
      );
      expect(o.streamRateHz, 60);
      o = await repo.update((o) => o.set(UserOptions.streamRateHzOption, 0));
      expect(o.streamRateHz, 1);
      o = await repo.update((o) => o.set(UserOptions.streamRateHzOption, -3));
      expect(o.streamRateHz, 1);
    });

    test('setting the default equals the defaults', () {
      expect(
        UserOptions.defaults.set(UserOptions.streamRateHzOption, 5),
        UserOptions.defaults,
      );
    });
  });

  group('optionsChanges', () {
    test('emits the new options on an update that changes something', () async {
      final seen = <UserOptions>[];
      final sub = repo.optionsChanges.listen(seen.add);
      await repo.update((o) => o.set(UserOptions.streamRateHzOption, 10));
      await repo.update((o) => o.set(UserOptions.autoModeOption, false));
      await Future<void>.delayed(Duration.zero);
      expect(seen.map((o) => o.streamRateHz), [10, 10]);
      expect(seen.last.autoMode, isFalse);
      await sub.cancel();
    });

    test('an update that changes nothing emits nothing', () async {
      final seen = <UserOptions>[];
      final sub = repo.optionsChanges.listen(seen.add);
      await repo.update((o) => o);
      await repo.update((o) => o.set(UserOptions.streamRateHzOption, 5));
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);
      await sub.cancel();
    });
  });

  group('persistence', () {
    test('a round trip through the store', () async {
      await repo.update(
        (o) => o
            .set(UserOptions.streamRateHzOption, 20)
            .set(UserOptions.autoModeOption, false),
      );
      expect(prefs.values['stream_rate_hz'], '20');
      expect(prefs.values['auto_mode'], 'false');
      final again = SettingsRepositoryImpl(preferences: prefs);
      await again.loadOptions();
      expect(again.options.streamRateHz, 20);
      expect(again.options.autoMode, isFalse);
    });

    test('back to the default removes the key', () async {
      await repo.update((o) => o.set(UserOptions.streamRateHzOption, 20));
      await repo.update((o) => o.set(UserOptions.streamRateHzOption, 5));
      expect(prefs.values.containsKey('stream_rate_hz'), isFalse);
    });

    test('a corrupt value gives the default', () async {
      prefs.values['stream_rate_hz'] = 'fast';
      prefs.values['auto_mode'] = 'maybe';
      await repo.loadOptions();
      expect(repo.options, UserOptions.defaults);
    });

    test(
      'an out-of-range value gives the default, not the nearest end',
      () async {
        prefs.values['stream_rate_hz'] = '500';
        await repo.loadOptions();
        expect(repo.options.streamRateHz, 5);
        prefs.values['stream_rate_hz'] = '0';
        await repo.loadOptions();
        expect(repo.options.streamRateHz, 5);
      },
    );

    test('a valid value is read', () async {
      prefs.values['stream_rate_hz'] = '30';
      await repo.loadOptions();
      expect(repo.options.streamRateHz, 30);
    });
  });

  group('the mechanism is general (AC-40)', () {
    // A third option, defined only here: a field, a default, a range and a key.
    const threshold = IntOption('test_threshold', 7, 0, 10);
    const flag = BoolOption('test_flag', true);

    test('needs nothing but its definition', () async {
      final repo = SettingsRepositoryImpl(
        preferences: prefs,
        extraOptions: const [threshold, flag],
      );
      expect(repo.options.get(threshold), 7);
      expect(repo.options.get(flag), isTrue);
      await repo.update((o) => o.set(threshold, 99).set(flag, false));
      expect(repo.options.get(threshold), 10);
      expect(prefs.values['test_threshold'], '10');
      expect(prefs.values['test_flag'], 'false');

      final again = SettingsRepositoryImpl(
        preferences: prefs,
        extraOptions: const [threshold, flag],
      );
      await again.loadOptions();
      expect(again.options.get(threshold), 10);
      expect(again.options.get(flag), isFalse);
    });

    test(
      'a corrupt stored value of the new option gives its default',
      () async {
        prefs.values['test_threshold'] = 'abc';
        final repo = SettingsRepositoryImpl(
          preferences: prefs,
          extraOptions: const [threshold],
        );
        await repo.loadOptions();
        expect(repo.options.get(threshold), 7);
      },
    );

    test('options with the same values are equal', () {
      expect(
        UserOptions.defaults.set(threshold, 3),
        UserOptions.defaults.set(threshold, 3),
      );
      expect(
        UserOptions.defaults.set(threshold, 3),
        isNot(UserOptions.defaults.set(threshold, 4)),
      );
    });
  });
}
