@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color, Size;

import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

/// The native launch screens — #85, and iOS's in #238.
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

    test('and neither theme draws a system title bar', () {
      // The template used `Theme.Light.NoTitleBar`. Moving to DayNight for the
      // splash dropped that, and Android drew its own bar with the package
      // name across the top of every screen. No widget test can see a bar the
      // platform draws; the first device screenshot showed it immediately.
      for (final path in const <String>[
        'android/app/src/main/res/values-v31/styles.xml',
        'android/app/src/main/res/values-night-v31/styles.xml',
      ]) {
        final xml = read(path);

        expect(xml, contains('windowNoTitle">true'), reason: path);
        expect(xml, contains('windowActionBar">false'), reason: path);
      }
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

  group('the iOS launch screen', () {
    const assets = 'ios/Runner/Assets.xcassets';
    const imageSet = '$assets/LaunchImage.imageset';

    Map<String, dynamic> contents(String path) {
      final file = File('$path/Contents.json');
      expect(file.existsSync(), isTrue, reason: '$path is missing');
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }

    bool isDark(Map<String, dynamic> entry) =>
        (entry['appearances'] as List<dynamic>? ?? const <dynamic>[]).any(
          (a) => (a as Map<String, dynamic>)['value'] == 'dark',
        );

    /// A PNG's pixel size, from its IHDR chunk.
    Size pngSize(String path) {
      final bytes = File(path).readAsBytesSync();
      final data = ByteData.sublistView(bytes, 16, 24);
      return Size(data.getUint32(0).toDouble(), data.getUint32(4).toDouble());
    }

    String storyboard() =>
        File('ios/Runner/Base.lproj/LaunchScreen.storyboard')
            .readAsStringSync()
            .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

    test('the field is Lagoon, and the dark palette at night', () {
      final colours = <bool, Color>{
        for (final entry
            in (contents('$assets/SplashField.colorset')['colors']
                    as List<dynamic>)
                .cast<Map<String, dynamic>>())
          isDark(entry): () {
            final c =
                (entry['color'] as Map<String, dynamic>)['components']
                    as Map<String, dynamic>;
            int channel(String name) => int.parse(c[name] as String);
            return Color.fromARGB(
              255,
              channel('red'),
              channel('green'),
              channel('blue'),
            );
          }(),
      };

      expect(colours[false], DpPalette.light.primary);
      expect(colours[true], DpPalette.dark.primary);
    });

    test('the storyboard paints it, not the template white', () {
      final xml = storyboard();

      expect(
        xml,
        contains('<color key="backgroundColor" name="SplashField"/>'),
      );
      expect(xml, isNot(contains('<color key="backgroundColor" red=')));
      expect(xml, contains('image="LaunchImage"'));
    });

    test('the mark is there at every scale, light and dark', () {
      final images = (contents(imageSet)['images'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final listed = <String>{
        for (final image in images)
          '${isDark(image) ? 'dark' : 'any'} ${image['scale']}',
      };

      expect(listed, <String>{
        for (final look in const <String>['any', 'dark'])
          for (final scale in const <String>['1x', '2x', '3x']) '$look $scale',
      });
      for (final image in images) {
        // The file the golden writes for that look and scale: a dark entry
        // naming the light PNG would show the light mark on a dark phone.
        final scale = image['scale'] as String;
        final expected =
            'LaunchImage${isDark(image) ? '-dark' : ''}'
            '${scale == '1x' ? '' : '@$scale'}.png';
        expect(image['filename'], expected, reason: '${image['scale']}');
        final path = '$imageSet/$expected';
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    });

    test('and each scale is the 1x image, scaled', () {
      // The storyboard lays the image out at its 1x size in points; a 2x
      // that is not twice that is drawn blurred or cropped.
      final base = pngSize('$imageSet/LaunchImage.png');
      for (final look in const <String>['', '-dark']) {
        for (final scale in const <int>[1, 2, 3]) {
          final name = 'LaunchImage$look${scale == 1 ? '' : '@${scale}x'}.png';
          expect(
            pngSize('$imageSet/$name'),
            base * scale.toDouble(),
            reason: name,
          );
        }
      }

      final declared = RegExp(
        r'<image name="LaunchImage" width="(\d+)" height="(\d+)"/>',
      ).firstMatch(storyboard());
      expect(declared, isNotNull);
      expect(
        Size(
          double.parse(declared!.group(1)!),
          double.parse(declared.group(2)!),
        ),
        base,
      );
    });
  });
}
