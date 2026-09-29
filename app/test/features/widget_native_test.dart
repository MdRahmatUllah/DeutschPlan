@TestOn('vm')
library;

import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/services/widget_snapshot.dart';

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

  Map<String, Color> expected(SgPalette palette, SgSurfaceTokens surface) =>
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
      expected(SgPalette.light, SgSurfaceTokens.light),
    );
  });

  test('FR-X1-04 and night is the dark tokens', () {
    expect(
      widgetColoursIn('android/app/src/main/res/values-night/colors.xml'),
      expected(SgPalette.dark, SgSurfaceTokens.dark),
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
      'SogdaWidget.kt',
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

  const widgetKotlin =
      'android/app/src/main/kotlin/de/sogda/app/widget/SogdaWidget.kt';

  // The small size's own body, up to the medium's.
  String small() {
    final kotlin = File(widgetKotlin).readAsStringSync();
    final start = kotlin.indexOf('private fun Small(');
    return kotlin.substring(
      start,
      kotlin.indexOf('private fun Medium(', start),
    );
  }

  test("#1069 FR-X1-02 the small widget's tomorrow line runs under the ring, "
      "the widget's width, not in the column beside it", () {
    final body = small();
    final ringRow = body.indexOf('Ring(snapshot, 48)');
    final tomorrow = body.indexOf('copy.text("tomorrow")');
    expect(ringRow, isNonNegative);
    expect(tomorrow, isNonNegative);
    // After the ring's row closes: the text sits in the outer Column.
    final rowEnd = body.indexOf('\n        }', ringRow);
    expect(tomorrow, greaterThan(rowEnd));
    // And nothing beside the ring says it.
    expect(body.substring(ringRow, rowEnd), isNot(contains('"tomorrow"')));
  });

  test('#1070 the widget picker shows a preview of the widget, not a '
      'placeholder tile', () {
    final info = File('android/app/src/main/res/xml/sogda_widget_info.xml')
        .readAsStringSync();
    final layout = RegExp(r'android:previewLayout="@layout/(\w+)"')
        .firstMatch(info)
        ?.group(1);
    expect(layout, isNotNull);
    expect(
      File('android/app/src/main/res/layout/$layout.xml').existsSync(),
      isTrue,
    );
  });

  test('#1090 the widget\'s own layouts use only the classes RemoteViews '
      'inflates, so the picker never says "Couldn\'t add widget."', () {
    // developer.android.com/develop/ui/views/appwidgets/layouts: anything
    // else, a plain View included, fails LayoutInflater's filter.
    // The last four since Android 12.
    const allowed =
        'FrameLayout LinearLayout RelativeLayout GridLayout AnalogClock Button '
        'Chronometer ImageButton ImageView ProgressBar TextClock TextView '
        'ViewStub AdapterViewFlipper GridView ListView StackView ViewFlipper '
        'CheckBox RadioButton RadioGroup Switch';
    final info = File('android/app/src/main/res/xml/sogda_widget_info.xml')
        .readAsStringSync();
    // initialLayout is Glance's own; only the layouts in res/ are ours.
    final ours = [
      for (final m in RegExp(r'@layout/(\w+)').allMatches(info))
        File('android/app/src/main/res/layout/${m.group(1)}.xml'),
    ].where((f) => f.existsSync()).toList();
    expect(ours, isNotEmpty);
    for (final file in ours) {
      final tags = RegExp(r'<([A-Za-z][\w.]*)')
          .allMatches(file.readAsStringSync())
          .map((m) => m.group(1));
      expect(
        tags.where((t) => !allowed.split(' ').contains(t)),
        isEmpty,
        reason: file.path,
      );
    }
  });
}
