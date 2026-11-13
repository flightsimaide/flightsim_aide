import 'package:flightsim_aide/data/repositories/settings/settings_repository_impl.dart';
import 'package:flightsim_aide/data/services/local/preferences_service.dart';
import 'package:flightsim_aide/domain/models/settings/appearance.dart';
import 'package:flightsim_aide/utils/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsRepositoryImpl> create() async =>
      SettingsRepositoryImpl(preferences: SharedPreferencesService());

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('manual ip', () {
    test('valid ip is saved and read back', () async {
      final repo = await create();
      final saved = await repo.saveManualIp('192.168.1.10');
      expect(saved.valueOrNull, '192.168.1.10');
      expect(await repo.manualIp(), '192.168.1.10');
    });

    test('300.1.1.1 is rejected', () async {
      final repo = await create();
      expect(
        (await repo.saveManualIp('300.1.1.1')).errorOrNull,
        isA<InvalidManualIp>(),
      );
      expect(await repo.manualIp(), isNull);
    });

    test('abc is rejected', () async {
      final repo = await create();
      expect(
        (await repo.saveManualIp('abc')).errorOrNull,
        isA<InvalidManualIp>(),
      );
    });

    test('empty is rejected', () async {
      final repo = await create();
      expect((await repo.saveManualIp('')).errorOrNull, isA<InvalidManualIp>());
      expect(
        (await repo.saveManualIp('   ')).errorOrNull,
        isA<InvalidManualIp>(),
      );
    });

    test('leading/trailing spaces are trimmed', () async {
      final repo = await create();
      final saved = await repo.saveManualIp('  10.0.0.7 ');
      expect(saved.valueOrNull, '10.0.0.7');
      expect(await repo.manualIp(), '10.0.0.7');
    });

    test('0.0.0.0 is rejected', () async {
      final repo = await create();
      expect(
        (await repo.saveManualIp('0.0.0.0')).errorOrNull,
        isA<InvalidManualIp>(),
      );
    });

    test('broadcast and malformed forms are rejected', () async {
      final repo = await create();
      for (final bad in [
        '255.255.255.255',
        '1.2.3',
        '1.2.3.4.5',
        '1.2.3.',
        '1..3.4',
        '1.2.3.-4',
        '1.2.3.4a',
        '01.2.3.4',
        '::1',
        'localhost',
      ]) {
        expect(
          (await repo.saveManualIp(bad)).errorOrNull,
          isA<InvalidManualIp>(),
          reason: bad,
        );
      }
    });

    test('a rejected value keeps the old one', () async {
      final repo = await create();
      await repo.saveManualIp('10.0.0.7');
      await repo.saveManualIp('nonsense');
      expect(await repo.manualIp(), '10.0.0.7');
    });

    test('clear removes it', () async {
      final repo = await create();
      await repo.saveManualIp('10.0.0.7');
      await repo.clearManualIp();
      expect(await repo.manualIp(), isNull);
    });

    test('value survives re-creating the repository', () async {
      await (await create()).saveManualIp('10.0.0.7');
      expect(await (await create()).manualIp(), '10.0.0.7');
    });
  });

  group('appearance', () {
    test('nothing saved gives the defaults', () async {
      final repo = await create();
      expect((await repo.appearance()).valueOrNull, Appearance.defaults);
    });

    test('mode and changed colours are read back after a restart', () async {
      const value = Appearance(
        mode: AppearanceMode.dark,
        colors: {'dark.accent': 0xFF00FF00, 'light.error': 0xFF123456},
      );
      await (await create()).saveAppearance(value);
      expect((await (await create()).appearance()).valueOrNull, value);
    });

    test('saving the defaults erases the stored value', () async {
      final repo = await create();
      await repo.saveAppearance(const Appearance(mode: AppearanceMode.light));
      await repo.saveAppearance(Appearance.defaults);
      expect(await SharedPreferencesService().getString('appearance'), isNull);
    });

    test('a damaged stored value gives the defaults', () async {
      await SharedPreferencesService().setString('appearance', '{not json');
      expect(
        (await (await create()).appearance()).valueOrNull,
        Appearance.defaults,
      );
    });

    test('an unknown mode falls back to the system mode', () async {
      await SharedPreferencesService().setString(
        'appearance',
        '{"mode":"purple","colors":{"dark.accent":4278255360,"x":"no"}}',
      );
      final value = (await (await create()).appearance()).valueOrNull!;
      expect(value.mode, AppearanceMode.system);
      expect(value.colors, {'dark.accent': 0xFF00FF00});
    });
  });
}
