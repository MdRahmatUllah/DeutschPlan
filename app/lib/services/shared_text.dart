import 'package:flutter/services.dart';

/// Text another app shared with Sogda (#1227, FR-D1-01): "Share → Sogda"
/// opens D1 through the `sogda://import` link, and D1 takes the text.
abstract interface class SharedText {
  /// The shared text, once: a second call answers null, as does a phone
  /// with none.
  Future<String?> take();
}

/// Android's `MainActivity`, which keeps what `ShareActivity` passed on. iOS
/// has no share target yet (#1227 is Android's), so it answers null.
class PlatformSharedText implements SharedText {
  const PlatformSharedText();

  static const MethodChannel _channel = MethodChannel('sogda/share');

  @override
  Future<String?> take() async {
    try {
      return await _channel.invokeMethod<String>('take');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
