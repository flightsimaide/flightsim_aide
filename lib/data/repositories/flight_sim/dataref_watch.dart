import '../../../domain/models/flight_sim/dataref.dart';
import '../../../domain/models/flight_sim/dataref_value.dart';

/// A live view of some datarefs, from `FlightSimRepository.watch`. It stays
/// open until [release]; the repository subscribes each name once however
/// many watches ask for it (task 5.6).
abstract interface class DatarefWatch {
  /// The datarefs that changed since the last batch, with their new values, at
  /// most as often as the stream rate option allows. The latest value wins.
  Stream<Map<Dataref, DatarefValue>> get batches;

  /// The latest value of every watched dataref now. A name with no value yet
  /// is [DatarefValue.unknown], never zero.
  Map<Dataref, DatarefValue> get current;

  /// The watched datarefs the plugin cannot serve (unknown name, unsupported,
  /// or past the subscription limit). Their values stay unknown.
  Set<Dataref> get unavailable;

  /// Emitted with the new [unavailable] set whenever it changes.
  Stream<Set<Dataref>> get unavailableChanges;

  /// Stops watching. The names nobody else watches are unsubscribed shortly
  /// after. Calling it twice is harmless.
  void release();
}
