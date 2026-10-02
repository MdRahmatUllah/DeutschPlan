import 'dart:io';

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

  /// The photos at [paths] are done with: the app's own copies (the camera's
  /// file, the picker's), with their metadata, never the gallery's. Best
  /// effort.
  Future<void> discard(List<String> paths);
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

  /// The folder image_picker copies a gallery photo into: a random UUID.
  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// The path D1 holds is image_picker's resized `cache/scaled_<name>`.
  /// Its copy from before the resize, with the camera's EXIF, goes too
  /// (#1298): the camera's `cache/<name>` beside it, or the gallery's
  /// `cache/<uuid>/<name>`. A photo never resized is the copy itself, in its
  /// UUID folder.
  @override
  Future<void> discard(List<String> paths) async {
    for (final path in paths) {
      final file = File(path);
      final cache = file.parent;
      final name = file.uri.pathSegments.last;
      await _delete(file);
      if (_uuid.hasMatch(cache.uri.pathSegments.lastWhere((s) => s != ''))) {
        await _delete(cache);
        continue;
      }
      if (!name.startsWith('scaled_') || !cache.existsSync()) continue;
      final original = name.substring('scaled_'.length);
      await _delete(File('${cache.path}/$original'));
      for (final entry in cache.listSync().whereType<Directory>()) {
        final folder = entry.uri.pathSegments.lastWhere((s) => s != '');
        if (_uuid.hasMatch(folder) &&
            File('${entry.path}/$original').existsSync()) {
          await _delete(entry);
        }
      }
    }
  }

  static Future<void> _delete(FileSystemEntity entity) async {
    try {
      await entity.delete(recursive: true);
    } on FileSystemException {
      // Gone already, or never written: nothing left to drop.
    }
  }

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
