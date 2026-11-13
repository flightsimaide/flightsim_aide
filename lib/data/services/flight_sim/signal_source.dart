import 'model/raw_signal_message.dart';

/// The part of the live link the dataref watching needs: sampled values, the
/// names the plugin cannot serve, whether the stream is up, and a way to set
/// which names to receive. Raw types only.
abstract interface class SignalSource {
  /// Every sampled value, as the plugin sent it.
  Stream<RawSignalMessage> get signals;

  /// Names of subscribed signals the plugin cannot serve (`unknown_name`,
  /// `unsupported` or over its limit). Emitted once per name per connection.
  Stream<String> get unavailableSignals;

  /// Whether the stream is open and fresh. Emitted on change.
  Stream<bool> get streamConnected;

  /// Whether the stream is open and fresh right now.
  bool get isStreamConnected;

  /// How many names [watchSignals] can have at once: the plugin's limit
  /// (128 per connection) less the fixed signals.
  int get maxWatched;

  /// The longest leading part of [names] that fits within the plugin's
  /// subscription limit. Names may share a subscription (consecutive elements
  /// of one array go as one range), so this can be more than [maxWatched]
  /// names. The rest would be ignored by [watchSignals].
  List<String> fit(List<String> names);

  /// Sets the names to receive and their rates (values per second, 1 to 60).
  /// It replaces the previous set: new names are subscribed, gone ones are
  /// unsubscribed, a changed rate is re-subscribed, all without dropping the
  /// connection. The set is kept and sent again after a reconnect. Names past
  /// [maxWatched] are ignored.
  void watchSignals(Map<String, int> namesAtHz);
}
