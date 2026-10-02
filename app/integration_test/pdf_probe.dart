import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sogda/services/pdf_text.dart';

/// #1228 (ADR 31): `PdfText.kt` on a release build, where R8 runs, before D1
/// calls it. The app's own external files folder must be the app's: start
/// the probe once to create it, push the PDFs into it, start it again, and
/// read the log:
///
///     flutter build apk --release --target-platform android-x64 \
///         -t integration_test/pdf_probe.dart -P allowDebugSigning=true
///     adb shell monkey -p de.sogda.app 1   # creates the folder
///     adb push text_layer.pdf scanned.pdf /sdcard/Android/data/de.sogda.app/files/
///     adb shell monkey -p de.sogda.app 1
///     adb logcat -s flutter | grep PDFPROBE
///
/// It reads every PDF there, page by page, as D1 does: its page count,
/// whether it's a scan, each page's length and its first line; or the error.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: Center(child: Text('PDF probe', textDirection: TextDirection.ltr)),
    ),
  );
  final folder = (await getExternalStorageDirectory())!;
  final files =
      folder.listSync().whereType<File>().map((file) => file.path).toList()
        ..sort();
  debugPrint('PDFPROBE ${folder.path}: ${files.length} files');
  for (final path in files) {
    final name = path.split('/').last;
    final watch = Stopwatch()..start();
    try {
      final read = await readPdf(const PlatformPdfText(), path);
      final first = read!.pages.first.trim().split('\n').first;
      debugPrint(
        'PDFPROBE $name: ${read.pageCount} pages, ${read.pages.length} read, '
        'scan ${read.scan}, chars ${[for (final p in read.pages) p.length]}, '
        '${watch.elapsedMilliseconds} ms, umlauts '
        '${RegExp('[äöüßÄÖÜ]').allMatches(read.pages.join()).length}, '
        'first «$first»',
      );
    } on Object catch (error) {
      debugPrint('PDFPROBE $name: $error (${watch.elapsedMilliseconds} ms)');
    }
  }
  debugPrint('PDFPROBE done');
}
