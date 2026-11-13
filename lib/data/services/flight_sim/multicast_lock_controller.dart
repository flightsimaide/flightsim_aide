import 'dart:io';

import 'package:flutter/services.dart';

/// Holds the Wi-Fi multicast lock while the beacon listener runs. Android
/// drops multicast packets for apps that do not hold it.
abstract class MulticastLockController {
  /// Takes the lock; harmless when already held.
  Future<void> acquire();

  /// Gives the lock back; harmless when not held.
  Future<void> release();
}

/// Does nothing: desktop and iOS need no lock.
class NoopMulticastLockController implements MulticastLockController {
  /// Creates the controller.
  const NoopMulticastLockController();

  @override
  Future<void> acquire() async {}

  @override
  Future<void> release() async {}
}

/// Talks to the Android side through the `flightsim_aide/multicast` channel. A
/// missing or failing platform side is tolerated: the lock is an aid, and the
/// manual IP still works without it.
class MethodChannelMulticastLockController implements MulticastLockController {
  /// Creates the controller.
  const MethodChannelMulticastLockController();

  static const _channel = MethodChannel('flightsim_aide/multicast');

  Future<void> _call(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No platform side: nothing to hold.
    } on PlatformException {
      // The lock could not be changed; discovery may be deaf, manual IP works.
    }
  }

  @override
  Future<void> acquire() => _call('acquire');

  @override
  Future<void> release() => _call('release');
}

/// The controller for this platform: the channel on Android, else a no-op.
MulticastLockController defaultMulticastLockController({bool? isAndroid}) =>
    (isAndroid ?? Platform.isAndroid)
    ? const MethodChannelMulticastLockController()
    : const NoopMulticastLockController();
