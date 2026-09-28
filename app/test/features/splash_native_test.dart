@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/theme/sg_brand.dart';
import 'package:sogda/core/theme/sg_tokens.dart';

/// The native launch screens — #85, iOS's in #238 — and the launcher icon,
/// with the brand kit's tiles (#602).
///
/// "Native launch screen and the first Flutter frame are visually identical."
/// The Android window is painted before any Dart runs, so its colours cannot
/// be read from the tokens and have to be written out in `colors.xml`. That is
/// two copies of the same value, and this is what stops them drifting.
void main() {
  /// `#RRGGBB` as an opaque [Color].
  Color hex(String value) =>
      Color(int.parse(value.replaceFirst('#', 'ff'), radix: 16));

  /// A PNG's pixel size, from its IHDR chunk.
  Size pngSize(String path) {
    final bytes = File(path).readAsBytesSync();
    final data = ByteData.sublistView(bytes, 16, 24);
    return Size(data.getUint32(0).toDouble(), data.getUint32(4).toDouble());
  }

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

  const res = 'android/app/src/main/res';

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
    /// The tiles are the kit's in both files: it never recolours them.
    void expectTheKitsTiles(Map<String, Color> colours) {
      expect(colours['splash_mark'], SgBrand.sun);
      expect(colours['splash_ink'], SgBrand.ink);
      expect(colours['splash_paper'], SgBrand.paper);
    }

    test('FR-S1-05 #602 light is the light field and the kit’s tiles', () {
      final colours = coloursIn('$res/values/colors.xml');

      expect(colours['splash_field'], SgPalette.light.primary);
      expectTheKitsTiles(colours);
    });

    test('FR-S1-05 #602 and night is the dark field and the same tiles', () {
      final colours = coloursIn('$res/values-night/colors.xml');

      expect(colours['splash_field'], SgPalette.dark.primary);
      expectTheKitsTiles(colours);
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
      // the tiles, which is not in any artboard.
      expect(
        read('android/app/src/main/res/values-v31/styles.xml'),
        isNot(contains('windowSplashScreenIconBackgroundColor')),
      );
    });

    test('pre-12 draws the same field and mark', () {
      final xml = read('$res/drawable/launch_background.xml');

      expect(xml, contains('@color/splash_field'));
      expect(xml, contains('@drawable/splash_mark'));
    });

    test('FR-S1-05 #602 and it is the one pre-12 phones read', () {
      // A `drawable-v21` copy wins over this file on every API the app runs
      // on (26+): the template's was there, and drew a plain window.
      expect(
        File('$res/drawable-v21/launch_background.xml').existsSync(),
        isFalse,
      );
      // The mark is a vector, which a `<bitmap>` cannot decode: the window
      // would fail to inflate.
      expect(
        read('$res/drawable/launch_background.xml'),
        isNot(contains('<bitmap')),
      );
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
    String mark(String name) => read('$res/drawable/$name.xml');

    /// dp per viewport unit, across and down.
    (double, double) scale(String name) {
      final xml = mark(name);
      double attr(String key) => double.parse(
        RegExp('android:$key="([0-9.]+)(?:dp)?"').firstMatch(xml)!.group(1)!,
      );
      return (
        attr('width') / attr('viewportWidth'),
        attr('height') / attr('viewportHeight'),
      );
    }

    test('is a vector, so it stays sharp at every density', () {
      for (final name in const <String>['splash_mark', 'splash_icon']) {
        expect(mark(name), contains('<?xml'), reason: name);
        expect(mark(name), contains('<vector'), reason: name);
      }
    });

    test('FR-S1-05 #602 carries the two tiles, their shadows and letters', () {
      for (final name in const <String>['splash_mark', 'splash_icon']) {
        final xml = mark(name);

        expect(RegExp('<path').allMatches(xml).length, 6, reason: name);
        // The kit's own letters, as SgMark draws them: one letterform.
        expect(xml, contains('android:pathData="M326 559'), reason: name);
        expect(xml, contains('android:pathData="M521 0'), reason: name);
        expect(xml, contains('@color/splash_paper'), reason: name);
        expect(xml, contains('@color/splash_mark'), reason: name);
      }
    });

    test('FR-S1-05 #602 the Android 12 icon keeps the kit’s 108 grid on the '
        '288 dp canvas', () {
      // Android draws the icon's canvas at 288 dp and masks it to the inner
      // two thirds, the adaptive icon's safe zone: the kit's art is inside.
      final icon = mark('splash_icon');

      expect(icon, contains('android:width="288dp"'));
      expect(icon, contains('android:viewportWidth="108"'));
      expect(icon, contains('android:viewportHeight="108"'));
      // Raised so the point S1's square centres on, (54, 56 - 2/1.32), is
      // the canvas's centre, where the platform centres the icon.
      expect(
        RegExp(r'<vector[^>]*>\s*<group android:translateY="([-0-9.]+)"')
            .firstMatch(icon)
            ?.group(1),
        (54 - (56 - 2 / 1.32)).toStringAsFixed(4),
      );
    });

    test('FR-S1-05 #602 and pre-12 draws the tiles at that scale too', () {
      // S1's Flutter frame draws them at 288 / 108 dp per unit as well.
      final (across, down) = scale('splash_mark');

      expect(across, moreOrLessEquals(288 / 108, epsilon: 1e-3));
      expect(down, moreOrLessEquals(288 / 108, epsilon: 1e-3));
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

  group('the launcher icon', () {
    const densities = <String, int>{
      'mdpi': 108,
      'hdpi': 162,
      'xhdpi': 216,
      'xxhdpi': 324,
      'xxxhdpi': 432,
    };

    test('#602 is adaptive, with a monochrome layer for the '
        'Android 13+ themed icon', () {
      final xml = read('$res/mipmap-anydpi-v26/ic_launcher.xml');

      expect(xml, contains('<adaptive-icon'));
      expect(
        xml,
        contains(
          '<background android:drawable="@color/ic_launcher_background"',
        ),
      );
      expect(
        xml,
        contains(
          '<foreground android:drawable="@mipmap/ic_launcher_foreground"',
        ),
      );
      expect(
        xml,
        contains(
          '<monochrome android:drawable="@mipmap/ic_launcher_monochrome"',
        ),
      );
      expect(
        read('android/app/src/main/AndroidManifest.xml'),
        contains('android:icon="@mipmap/ic_launcher"'),
      );
    });

    test('#602 its ground is Lagoon, day and night', () {
      for (final values in const <String>['values', 'values-night']) {
        expect(
          coloursIn('$res/$values/colors.xml')['ic_launcher_background'],
          SgBrand.lagoon,
          reason: values,
        );
      }
    });

    test('#602 every density has both layers, and the legacy icon', () {
      for (final MapEntry(key: density, value: px) in densities.entries) {
        for (final layer in const <String>[
          'ic_launcher_foreground',
          'ic_launcher_monochrome',
        ]) {
          final path = '$res/mipmap-$density/$layer.png';
          expect(File(path).existsSync(), isTrue, reason: path);
          expect(pngSize(path), Size.square(px.toDouble()), reason: path);
        }
        // 48 dp, where a layer is 108 dp.
        final legacy = '$res/mipmap-$density/ic_launcher.png';
        expect(pngSize(legacy), Size.square(px * 48 / 108), reason: legacy);
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

      expect(colours[false], SgPalette.light.primary);
      expect(colours[true], SgPalette.dark.primary);
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
