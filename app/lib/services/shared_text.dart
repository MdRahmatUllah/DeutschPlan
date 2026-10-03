import 'package:flutter/services.dart';

/// Text another app shared with Sogda (#1227, FR-D1-01): "Share → Sogda"
/// opens D1 through the `sogda://import` link, and D1 takes the text.
abstract interface class SharedText {
  /// The shared text, once: a second call answers null, as does a phone
  /// with none.
  Future<String?> take();

  /// A PDF shared (#1228), as the path of its copy in the cache, once; null
  /// when the share was text, or there is none.
  Future<String?> takePdf();
}

/// Android's `MainActivity`, which keeps what `ShareActivity` passed on. iOS
/// has no share target yet (#1227 is Android's), so it answers null.
class PlatformSharedText implements SharedText {
  const PlatformSharedText();

  static const MethodChannel _channel = MethodChannel('sogda/share');

  @override
  Future<String?> take() => _take('take');

  @override
  Future<String?> takePdf() => _take('takePdf');

  static Future<String?> _take(String method) async {
    try {
      return await _channel.invokeMethod<String>(method);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
