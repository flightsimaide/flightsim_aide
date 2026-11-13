import '../../../domain/models/settings/appearance.dart';
import '../../../domain/models/settings/user_options.dart';
import '../../../utils/result.dart';

/// The user's connection choices, kept between runs.
abstract class SettingsRepository {
  /// The manually entered sim address, or null for automatic discovery.
  Future<String?> manualIp();

  /// Validates and stores [input] (a dotted IPv4 address, spaces trimmed) and
  /// returns the stored form. A bad value is an `InvalidManualIp` and leaves
  /// the old one in place.
  Future<Result<String>> saveManualIp(String input);

  /// Goes back to automatic discovery.
  Future<void> clearManualIp();

  /// The saved Appearance choices; the defaults when nothing is saved or the
  /// stored value cannot be read.
  Future<Result<Appearance>> appearance();

  /// Stores [value]. The defaults erase what was stored.
  Future<Result<void>> saveAppearance(Appearance value);

  /// The current options: the defaults until [loadOptions] has run.
  UserOptions get options;

  /// Emits the new options after every [update] that changed them.
  Stream<UserOptions> get optionsChanges;

  /// Reads the stored options. A missing, corrupt or out-of-range value gives
  /// that option's default. Call once at start.
  Future<void> loadOptions();

  /// Applies [change] to the current options, stores the result (one key per
  /// option) and emits it when it differs. Returns the new options.
  Future<UserOptions> update(UserOptions Function(UserOptions) change);
}
