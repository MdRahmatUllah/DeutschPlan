@TestOn('vm')
library;

import 'dart:io';
import 'dart:ui' show Color;

import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/services/widget_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// X1's native side (#160), which Dart can't reach at run time: this stops it
/// drifting from the app, as `splash_native_test.dart` does for the launch
/// screen.
void main() {
  /// `#RRGGBB` or `#AARRGGBB`.
  Color hex(String value) {
    final digits = value.substring(1);
    return Color(
      int.parse(digits.length == 6 ? 'ff$digits' : digits, radix: 16),
    );
  }

  Map<String, Color> widgetColoursIn(String path) {
    final pattern = RegExp(
      r'<color name="(widget_\w+)">(#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?)</color>',
    );
    return <String, Color>{
      for (final match in pattern.allMatches(File(path).readAsStringSync()))
        match.group(1)!: hex(match.group(2)!),
    };
  }

  Map<String, Color> expected(DpPalette palette, DpSurfaceTokens surface) =>
      <String, Color>{
        'widget_card': surface.card,
        'widget_track': surface.track,
        'widget_outline': surface.outline,
        'widget_ink': palette.ink,
        'widget_secondary': palette.textSecondary,
        'widget_primary': palette.primary,
        'widget_accent': palette.accent,
        'widget_on_accent': palette.onAccent,
        'widget_easy': palette.easy,
        'widget_der': palette.der,
        'widget_die': palette.die,
        'widget_das': palette.das,
      };

  // The colours are the tokens, written out in `colors.xml` because Glance
  // can't read Dart. Glass draws as the opaque light or dark, so those are the
  // two.
  test('FR-X1-04 light is the light tokens', () {
    expect(
      widgetColoursIn('android/app/src/main/res/values/colors.xml'),
      expected(DpPalette.light, DpSurfaceTokens.light),
    );
  });

  test('FR-X1-04 and night is the dark tokens', () {
    expect(
      widgetColoursIn('android/app/src/main/res/values-night/colors.xml'),
      expected(DpPalette.dark, DpSurfaceTokens.dark),
    );
  });

  // A redraw sent to a name nothing answers to fails silently: the widget
  // would keep the last snapshot until the launcher's next update.
  test('FR-X1-01 the redraw names the receiver the manifest declares', () {
    const name = HomeWidgetStore.androidReceiver;
    final dot = name.lastIndexOf('.');
    final package = name.substring(0, dot);
    final kotlin = File(
      'android/app/src/main/kotlin/${package.replaceAll('.', '/')}/'
      'DeutschPlanWidget.kt',
    ).readAsStringSync();
    // Line by line: git may check it out with CRLF endings.
    expect(kotlin.split(RegExp(r'\r?\n')), contains('package $package'));
    expect(kotlin, contains('class ${name.substring(dot + 1)} '));

    // `.widget.X` in the manifest is relative to the namespace.
    final namespace = RegExp(r'namespace = "([\w.]+)"')
        .firstMatch(File('android/app/build.gradle.kts').readAsStringSync())!
        .group(1)!;
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('android:name="${name.replaceFirst(namespace, '')}"'),
    );
  });
}
