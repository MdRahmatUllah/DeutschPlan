import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/domain/documents/ocr.dart';
import 'package:sogda/services/page_photos.dart';

import '../test/db/content_fixture.dart' show tempDir;

/// FR-D1-03 (#1229): ML Kit's bundled Latin recognition, on the phone, reads
/// a letter's photo sharp and lightly blurred above [ocrCheckBelow], and a
/// heavily blurred one below it, which opens *Check the text*. The pages are
/// drawn here, so no image ships with the app or the test.
///
///     flutter test integration_test/ocr_threshold_test.dart -d emulator-5558
///
/// A release build matters too: R8 broke ML Kit where a debug run can't
/// show it (`proguard-rules.pro`), so the device check is a release APK.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const letter = <String>[
    'Hausverwaltung Becker GmbH',
    '',
    'Sehr geehrte Frau Okafor,',
    '',
    'am Dienstag kommt der Hausmeister. Er will die',
    'Heizkörper kontrollieren und den Wasserzähler',
    'ablesen. Bitte seien Sie zwischen 9 und 12 Uhr',
    'erreichbar. Die Nebenkostenabrechnung für das',
    'Jahr 2025 schicken wir Ihnen im März.',
    '',
    'Mit freundlichen Grüßen',
    'Ihre Hausverwaltung',
  ];

  /// The letter as a 1500 × 1100 photo, blurred by [sigma].
  Future<String> photo(String name, double sigma) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(
        const Rect.fromLTWH(0, 0, 1500, 1100),
        Paint()..color = const Color(0xFFFAF8F0),
      );
    if (sigma > 0) {
      canvas.saveLayer(
        null,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      );
    }
    for (final (i, line) in letter.indexed) {
      (TextPainter(
        text: TextSpan(
          text: line,
          style: const TextStyle(fontSize: 46, color: Color(0xFF19191E)),
        ),
        textDirection: TextDirection.ltr,
      )..layout()).paint(canvas, Offset(90, 80.0 + i * 72));
    }
    if (sigma > 0) canvas.restore();
    final image = await recorder.endRecording().toImage(1500, 1100);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${tempDir('sg_ocr').path}/$name.png');
    await file.writeAsBytes(png!.buffer.asUint8List());
    return file.path;
  }

  testWidgets('FR-D1-03 a sharp and a lightly blurred page read above the '
      'line; a heavily blurred one below it', (tester) async {
    final photos = PlatformPagePhotos();
    final sharp = await photos.read(await photo('sharp', 0));
    final light = await photos.read(await photo('light', 3.2));
    final heavy = await photos.read(await photo('heavy', 5.5));

    expect(sharp.text, contains('Nebenkostenabrechnung'));
    expect(sharp.confidence, greaterThanOrEqualTo(ocrCheckBelow));
    expect(needsCheck(<OcrPage>[sharp, light]), isFalse);
    expect(needsCheck(<OcrPage>[heavy]), isTrue);
    expect(unsureWords(<OcrPage>[heavy]), isNotEmpty);
  });
}
