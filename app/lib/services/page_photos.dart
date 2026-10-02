import 'package:sogda/domain/documents/ocr.dart';

/// D1's photos (#1229, FR-D1-01, FR-D1-03): pages from the camera or the
/// gallery, read on the phone (BR-DOC-01). Nothing leaves it.
abstract interface class PagePhotos {
  /// One page from the camera; null when the learner backs out.
  Future<String?> take();

  /// Pages already on the phone, in the order chosen; empty when none.
  Future<List<String>> choose();

  /// The text on the photo at [path], word by word, with how sure the
  /// reading was.
  Future<OcrPage> read(String path);
}

/// The camera and the gallery through `image_picker`, and ML Kit's text
/// recognition, Latin, its model bundled (#1220).
// ponytail: a stand-in until agent-0 approves the two packages (#1229).
class PlatformPagePhotos implements PagePhotos {
  const PlatformPagePhotos();

  @override
  Future<String?> take() => throw UnimplementedError();

  @override
  Future<List<String>> choose() => throw UnimplementedError();

  @override
  Future<OcrPage> read(String path) => throw UnimplementedError();
}
