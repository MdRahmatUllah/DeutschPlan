import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// Runs once for every test suite under `test/`, before any test.
///
/// Fonts are loaded here rather than inside a test body: a `testWidgets`
/// callback runs in a fake-async zone, and awaiting real file I/O there never
/// completes — the first golden attempt hung for five minutes without
/// producing a frame.
///
/// Without them every glyph is the test framework's placeholder box, which
/// makes goldens useless for judging type and hides the Bangla step-up
/// entirely.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadFontsFromManifest();
  await testMain();
}

/// Loads every family in `FontManifest.json`.
///
/// Reading the manifest rather than naming families keeps this honest in two
/// ways: a font added to `pubspec.yaml` is picked up without touching this
/// file, and **MaterialIcons** is included — it is in the manifest because
/// `uses-material-design: true`, and without it every icon renders as an empty
/// square. The first golden shipped with exactly that, a box where the speaker
/// should have been.
Future<void> _loadFontsFromManifest() async {
  final manifest = jsonDecode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<dynamic>;

  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    final fonts = (entry['fonts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    final loader = FontLoader(family);
    for (final font in fonts) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}
