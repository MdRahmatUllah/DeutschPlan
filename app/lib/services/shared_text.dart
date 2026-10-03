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

  /// Photos shared (#1332), once: their copies in the cache in the order
  /// shared, at most D1's 30, and how many were shared ([of]); null when the
  /// share was none.
  Future<({List<String> pages, int of})?> takeImages();

  /// How many shared photos are still being copied, 0 when none (#1386):
  /// D1 says so at once, as [takeImages] waits for the copies.
  Future<int> receiving();
}

/// Android's `MainActivity`, which keeps what `ShareActivity` passed on. iOS
/// has no share target yet (#1227 is Android's), so it answers null.
class PlatformSharedText implements SharedText {
  const PlatformSharedText();

  static const MethodChannel _channel = MethodChannel('sogda/share');

  @override
  Future<String?> take() async => await _take('take') as String?;

  @override
  Future<String?> takePdf() async => await _take('takePdf') as String?;

  @override
  Future<({List<String> pages, int of})?> takeImages() async =>
      switch (await _take('takeImages')) {
        {'pages': final List<Object?> pages, 'of': final int of} => (
          pages: pages.cast<String>(),
          of: of,
        ),
        _ => null,
      };

  @override
  Future<int> receiving() async => await _take('receiving') as int? ?? 0;

  static Future<Object?> _take(String method) async {
    try {
      return await _channel.invokeMethod<Object?>(method);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
