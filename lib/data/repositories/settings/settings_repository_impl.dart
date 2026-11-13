import 'dart:async';
import 'dart:convert';

import '../../../domain/models/settings/appearance.dart';
import '../../../domain/models/settings/user_options.dart';
import '../../../utils/app_exception.dart';
import '../../../utils/ipv4.dart';
import '../../../utils/result.dart';
import '../../services/local/preferences_service.dart';
import 'settings_repository.dart';

const _manualIpKey = 'manual_ip';
const _appearanceKey = 'appearance';

/// [SettingsRepository] over a [PreferencesService].
class SettingsRepositoryImpl implements SettingsRepository {
  /// Creates the repository.
  SettingsRepositoryImpl({
    required this.preferences,
    this.extraOptions = const [],
  });

  /// Options beyond [UserOptions.definitions]; a test uses it to show that a
  /// new option needs only its definition (AC-40).
  final List<OptionDef<Object>> extraOptions;

  UserOptions _options = UserOptions.defaults;
  final _changes = StreamController<UserOptions>.broadcast();

  Iterable<OptionDef<Object>> get _definitions => [
    ...UserOptions.definitions,
    ...extraOptions,
  ];

  /// Where the values are kept.
  final PreferencesService preferences;

  @override
  Future<String?> manualIp() => preferences.getString(_manualIpKey);

  @override
  Future<Result<String>> saveManualIp(String input) async {
    final ip = input.trim();
    if (!isUsableIpv4(ip)) return Error(InvalidManualIp(input));
    await preferences.setString(_manualIpKey, ip);
    return Ok(ip);
  }

  @override
  Future<void> clearManualIp() => preferences.remove(_manualIpKey);

  @override
  UserOptions get options => _options;

  @override
  Stream<UserOptions> get optionsChanges => _changes.stream;

  @override
  Future<void> loadOptions() async {
    var loaded = UserOptions.defaults;
    for (final def in _definitions) {
      try {
        final text = await preferences.getString(def.key);
        if (text == null) continue;
        loaded = _setDecoded(loaded, def, text);
      } on Object {
        // An unreadable value keeps the default.
      }
    }
    _options = loaded;
  }

  UserOptions _setDecoded<T extends Object>(
    UserOptions options,
    OptionDef<T> def,
    String text,
  ) {
    final value = def.decode(text);
    return value == null ? options : options.set(def, value);
  }

  @override
  Future<UserOptions> update(UserOptions Function(UserOptions) change) async {
    final next = change(_options);
    if (next == _options) return _options;
    _options = next;
    for (final def in _definitions) {
      await _store(next, def);
    }
    _changes.add(next);
    return next;
  }

  Future<void> _store<T extends Object>(
    UserOptions options,
    OptionDef<T> def,
  ) async {
    final value = options.get(def);
    if (value == def.defaultValue) {
      await preferences.remove(def.key);
    } else {
      await preferences.setString(def.key, def.encode(value));
    }
  }

  @override
  Future<Result<Appearance>> appearance() async {
    try {
      final text = await preferences.getString(_appearanceKey);
      if (text == null) return const Ok(Appearance.defaults);
      final json = jsonDecode(text) as Map<String, dynamic>;
      final mode = AppearanceMode.values.asNameMap()[json['mode']];
      final colors = <String, int>{
        for (final e in (json['colors'] as Map<String, dynamic>? ?? {}).entries)
          if (e.value is int) e.key: e.value as int,
      };
      return Ok(
        Appearance(mode: mode ?? AppearanceMode.system, colors: colors),
      );
    } on Object {
      // A damaged value must not stop the app: use the defaults.
      return const Ok(Appearance.defaults);
    }
  }

  @override
  Future<Result<void>> saveAppearance(Appearance value) async {
    try {
      if (value == Appearance.defaults) {
        await preferences.remove(_appearanceKey);
      } else {
        await preferences.setString(
          _appearanceKey,
          jsonEncode({'mode': value.mode.name, 'colors': value.colors}),
        );
      }
      return const Ok(null);
    } on Object catch (e) {
      return Error(SourceReadFailure('Could not save the appearance: $e'));
    }
  }
}
