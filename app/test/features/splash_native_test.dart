@TestOn('vm')
library;

import 'dart:io';
import 'dart:ui' show Color;

import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

/// The native launch screens — #85.
///
/// "Native launch screen and the first Flutter frame are visually identical."
/// The Android window is painted before any Dart runs, so its colours cannot
/// be read from the tokens and have to be written out in `colors.xml`. That is
/// two copies of the same value, and this is what stops them drifting.
void main() {
  /// `#RRGGBB` as an opaque [Color].
  Color hex(String value) =>
      Color(int.parse(value.replaceFirst('#', 'ff'), radix: 16));

  /// The `<color name="…">#…</color>` entries of one resource file.
  Map<String, Color> coloursIn(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path is missing');

    final pattern = RegExp(r'<color name="(\w+)">(#[0-9A-Fa-f]{6})</color>');
    return <String, Color>{
      for (final match in pattern.allMatches(file.readAsStringSync()))
        match.group(1)!: hex(match.group(2)!),
    };
  }

  group('the Android launch colours match the palette', () {
    test('light is the light palette', () {
      final colours = coloursIn('android/app/src/main/res/values/colors.xml');
      const palette = DpPalette.light;

      expect(colours['splash_field'], palette.primary);
      expect(colours['splash_mark'], palette.accent);
      expect(colours['splash_ink'], palette.ink);
    });

    test('and night is the dark palette', () {
      final colours = coloursIn(
        'android/app/src/main/res/values-night/colors.xml',
      );
      const palette = DpPalette.dark;

      expect(colours['splash_field'], palette.primary);
      expect(colours['splash_mark'], palette.accent);
      expect(colours['splash_ink'], palette.ink);
    });

    test('every name is defined in both', () {
      // A name in one file and not the other is a colour that falls back to
      // the light value at night, which is only visible on a dark phone.
      expect(
        coloursIn('android/app/src/main/res/values/colors.xml').keys.toSet(),
        coloursIn('android/app/src/main/res/values-night/colors.xml').keys
            .toSet(),
      );
    });
  });

  group('the launch theme', () {
    /// The file with its comments stripped.
    ///
    /// Every one of these files explains itself, and those explanations name
    /// the very attributes being asserted about — so a check against the raw
    /// text passes or fails on prose. That has now caught me three times in
    /// this session; the markup is what ships, so the markup is what is read.
    String read(String path) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is missing');

      return file.readAsStringSync().replaceAll(
        RegExp(r'<!--.*?-->', dotAll: true),
        '',
      );
    }

    test('Android 12 draws the field and the mark', () {
      for (final path in const <String>[
        'android/app/src/main/res/values-v31/styles.xml',
        'android/app/src/main/res/values-night-v31/styles.xml',
      ]) {
        final xml = read(path);

        expect(
          xml,
          contains('windowSplashScreenBackground">@color/splash_field'),
          reason: path,
        );
        expect(
          xml,
          contains('windowSplashScreenAnimatedIcon">@drawable/splash_icon'),
          reason: path,
        );
      }
    });

    test('and no circle is drawn behind the mark', () {
      // `windowSplashScreenIconBackgroundColor` would put a filled disc under
      // the speech bubble, which is not in any artboard.
      expect(
        read('android/app/src/main/res/values-v31/styles.xml'),
        isNot(contains('windowSplashScreenIconBackgroundColor')),
      );
    });

    test('pre-12 draws the same field and mark', () {
      final xml = read(
        'android/app/src/main/res/drawable/launch_background.xml',
      );

      expect(xml, contains('@color/splash_field'));
      expect(xml, contains('@drawable/splash_mark'));
    });

    test('the theme is still the one the manifest names', () {
      // Renaming the style silently drops the whole launch screen: the
      // manifest keeps pointing at a LaunchTheme that no longer exists in
      // v31, so Android falls back to the pre-12 one.
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('@style/LaunchTheme'));

      for (final path in const <String>[
        'android/app/src/main/res/values/styles.xml',
        'android/app/src/main/res/values-v31/styles.xml',
      ]) {
        expect(read(path), contains('name="LaunchTheme"'), reason: path);
      }
    });
  });

  group('the mark drawable', () {
    String mark(String name) =>
        File('android/app/src/main/res/drawable/$name.xml')
            .readAsStringSync()
            .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

    test('is a vector, so it stays sharp at every density', () {
      for (final name in const <String>['splash_mark', 'splash_icon']) {
        expect(mark(name), contains('<?xml'), reason: name);
        expect(mark(name), contains('<vector'), reason: name);
      }
    });

    test('carries the bubble, the tail and the letter', () {
      // Three paths. The tail is the piece Android 12 cropped when the icon
      // was drawn at its own size, so its presence is worth asserting.
      expect(RegExp('<path').allMatches(mark('splash_icon')).length, 3);
      expect(RegExp('<path').allMatches(mark('splash_mark')).length, 3);
    });

    test('and the Android 12 icon leaves room for the circular mask', () {
      // Android masks the splash icon into a circle and shows roughly the
      // inner two thirds. Drawing the mark at 120 x 104 on a 120 x 104 canvas
      // loses the corners and the whole tail — which is what happened before
      // this canvas existed.
      final icon = mark('splash_icon');

      expect(icon, contains('android:viewportWidth="288"'));
      expect(icon, contains('android:viewportHeight="288"'));
      expect(icon, contains('<group'), reason: 'the art is not inset');
    });

    test('the colours come from the resources, never inline', () {
      // An inline hex here would not follow the night qualifier.
      for (final name in const <String>['splash_mark', 'splash_icon']) {
        expect(
          RegExp(r'(fill|stroke)Color="#').hasMatch(mark(name)),
          isFalse,
          reason: name,
        );
      }
    });
  });
}
