import 'dart:math' as math;

import 'package:flutter/services.dart';

/// The phone's storage, free and in all, in bytes (M4's storage card).
typedef StorageSpace = ({int free, int total});

/// How much room the phone has (#156): M4's storage card, and the space check
/// before a model download.
abstract interface class DeviceStorage {
  /// Null when the phone won't say.
  Future<StorageSpace?> space();
}

/// Asks the platform: Android's `StatFs` over the app's files, iOS's
/// capacity available for important usage.
class PlatformDeviceStorage implements DeviceStorage {
  const PlatformDeviceStorage();

  static const MethodChannel _channel = MethodChannel('deutschplan/storage');

  @override
  Future<StorageSpace?> space() async {
    try {
      final answer = await _channel.invokeMapMethod<String, Object?>('space');
      final free = answer?['free'];
      final total = answer?['total'];
      if (free is! int || total is! int || total <= 0) return null;
      return (free: free, total: total);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// FR-M4 *Not enough space*: the bytes a download of [needed] more bytes is
/// short of, and 0 when it fits. The button is disabled and says this much.
/// Also 0 when the phone won't say: a guess must not block a download.
int shortfall({required int needed, required StorageSpace? space}) =>
    space == null ? 0 : math.max(0, needed - space.free);
