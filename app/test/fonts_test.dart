import 'dart:convert';
import 'dart:io';

import 'package:deutschplan/core/typography/app_fonts.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Inter and Noto Sans Bengali ship with the app (docs/01-architecture/theming.md).
/// Inter carries no Bangla glyphs, so mixed German/Bangla copy - the headword
/// caption, meanings, the widget's Wort des Tages - only renders if the fallback
/// is wired. These tests check that, not just that the files are present.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fontDir = 'assets/fonts';

  test(
    'every bundled font file is declared in pubspec.yaml, and vice versa',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      final onDisk =
          Directory(fontDir)
              .listSync()
              .whereType<File>()
              .map((f) => f.uri.pathSegments.last)
              .toList()
            ..sort();

      expect(onDisk, isNotEmpty, reason: 'no fonts under $fontDir');
      for (final name in onDisk) {
        expect(
          pubspec.contains('$fontDir/$name'),
          isTrue,
          reason: '$name is in $fontDir but not declared in pubspec.yaml',
        );
      }

      const prefix = '- asset: $fontDir/';
      final declared =
          const LineSplitter()
              .convert(pubspec)
              .map((l) => l.trim())
              .where((l) => l.startsWith(prefix))
              .map((l) => l.substring(prefix.length).trim())
              .toList()
            ..sort();

      expect(
        declared,
        onDisk,
        reason: 'pubspec.yaml and $fontDir disagree about which fonts ship',
      );
    },
  );

  test('the bundled files are real TrueType fonts, not error pages', () {
    for (final file in Directory(fontDir).listSync().whereType<File>()) {
      final bytes = file.readAsBytesSync();
      expect(
        bytes.length,
        greaterThan(50000),
        reason: '${file.path} is suspiciously small',
      );
      final head = bytes.sublist(0, 4);
      final isTrueType =
          head[0] == 0 && head[1] == 1 && head[2] == 0 && head[3] == 0;
      final tag = String.fromCharCodes(head);
      expect(
        isTrueType || tag == 'true' || tag == 'OTTO',
        isTrue,
        reason: '${file.path} is not a font (leading bytes: $head)',
      );
    }
  });

  test('the OFL 1.1 licence text ships for every family', () {
    for (final name in ['Inter-OFL.txt', 'NotoSansBengali-OFL.txt']) {
      final file = File('assets/licences/$name');
      expect(file.existsSync(), isTrue, reason: '$name is missing');
      expect(
        file.readAsStringSync(),
        contains('SIL OPEN FONT LICENSE Version 1.1'),
        reason: '$name is not the OFL 1.1 text',
      );
    }
  });

  group('rendering', () {
    setUpAll(() async {
      await _load(AppFonts.latin, ['Inter-Variable.ttf']);
      await _load(AppFonts.bengali, ['NotoSansBengali-Variable.ttf']);
    });

    // Bangla is not in Inter, so laying it out in Inter alone yields notdef
    // glyphs. With the fallback the same string measures differently.
    test('Bangla in a mixed string resolves through the fallback', () {
      const mixed = 'die Wohnung · ফ্ল্যাট';

      final withoutFallback = _width(
        const TextStyle(fontFamily: AppFonts.latin),
        mixed,
      );
      final withFallback = _width(
        const TextStyle(
          fontFamily: AppFonts.latin,
          fontFamilyFallback: AppFonts.fallback,
        ),
        mixed,
      );

      expect(withoutFallback, greaterThan(0));
      expect(
        withFallback,
        isNot(closeTo(withoutFallback, 0.01)),
        reason: 'the fallback changed nothing — Bangla is rendering as notdef boxes',
      );
    });

    test('German-only text is unaffected by the fallback', () {
      const german = 'die Wohnung';
      expect(
        _width(
          const TextStyle(
            fontFamily: AppFonts.latin,
            fontFamilyFallback: AppFonts.fallback,
          ),
          german,
        ),
        closeTo(
          _width(const TextStyle(fontFamily: AppFonts.latin), german),
          0.01,
        ),
      );
    });

    test('the wght axis of the variable font actually varies', () {
      const word = 'Wohnung';
      final light = _width(
        TextStyle(
          fontFamily: AppFonts.latin,
          fontVariations: AppFonts.weight(100),
        ),
        word,
      );
      final black = _width(
        TextStyle(
          fontFamily: AppFonts.latin,
          fontVariations: AppFonts.weight(900),
        ),
        word,
      );

      expect(
        black,
        greaterThan(light),
        reason: 'wght 100 and 900 measure the same — the variable axis is not applied',
      );
    });

    test('German diacritics and ß render as glyphs, not notdef', () {
      const plain = 'Strasse';
      const umlauts = 'Straße';
      expect(
        _width(const TextStyle(fontFamily: AppFonts.latin), umlauts),
        greaterThan(0),
      );
      expect(
        _width(const TextStyle(fontFamily: AppFonts.latin), umlauts),
        isNot(
          closeTo(
            _width(const TextStyle(fontFamily: AppFonts.latin), plain),
            0.01,
          ),
        ),
      );
    });
  });
}

Future<void> _load(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final name in files) {
    loader.addFont(
      File('assets/fonts/$name')
          .readAsBytes()
          .then((b) => b.buffer.asByteData()),
    );
  }
  await loader.load();
}

double _width(TextStyle style, String text) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style.copyWith(fontSize: 32)),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}
