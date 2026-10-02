import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
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
/// recognition, Latin, its model bundled (#1220): nothing is downloaded and
/// nothing leaves the phone (BR-DOC-01).
class PlatformPagePhotos implements PagePhotos {
  PlatformPagePhotos();

  final ImagePicker _picker = ImagePicker();

  /// Big enough for a page's small print, small enough to keep: about 1 MB
  /// a page while *Save original images* is on (BR-DOC-05).
  static const double _width = 2400;
  static const int _quality = 90;

  @override
  Future<String?> take() async => (await _picker.pickImage(
    source: ImageSource.camera,
    maxWidth: _width,
    imageQuality: _quality,
  ))?.path;

  @override
  Future<List<String>> choose() async => <String>[
    for (final photo in await _picker.pickMultiImage(
      maxWidth: _width,
      imageQuality: _quality,
    ))
      photo.path,
  ];

  @override
  Future<OcrPage> read(String path) async {
    final recognizer = TextRecognizer();
    try {
      final text = await recognizer.processImage(InputImage.fromFilePath(path));
      return OcrPage(<List<OcrWord>>[
        for (final block in text.blocks)
          for (final line in block.lines)
            <OcrWord>[
              for (final element in line.elements)
                (text: element.text, confidence: element.confidence),
            ],
      ]);
    } finally {
      await recognizer.close();
    }
  }
}
