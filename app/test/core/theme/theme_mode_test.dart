import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/theme/theme_mode.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Brightness;

/// The one mapping between what the learner chose and what `AppTheme` builds.
/// Written once so a silently wrong theme cannot come from two versions of it.
void main() {
  test('system follows the platform', () {
    expect(ThemeModeSetting.system.resolve(Brightness.light), DpMode.light);
    expect(ThemeModeSetting.system.resolve(Brightness.dark), DpMode.dark);
    expect(ThemeModeSetting.system.followsPlatform, isTrue);
  });

  test('an explicit choice ignores the platform', () {
    const explicit = <ThemeModeSetting, DpMode>{
      ThemeModeSetting.light: DpMode.light,
      ThemeModeSetting.dark: DpMode.dark,
      ThemeModeSetting.glass: DpMode.glass,
    };

    for (final MapEntry(key: setting, value: mode) in explicit.entries) {
      for (final platform in Brightness.values) {
        expect(
          setting.resolve(platform),
          mode,
          reason: '$setting on $platform',
        );
      }
      expect(setting.followsPlatform, isFalse);
    }
  });

  test('every setting resolves, so adding one cannot be forgotten', () {
    // The switch in resolve() is exhaustive, so a new value is a compile error
    // rather than a runtime one — this asserts the pairing stays total if that
    // switch ever gains a default.
    for (final setting in ThemeModeSetting.values) {
      expect(DpMode.values, contains(setting.resolve(Brightness.light)));
    }
  });

  test('glass is never inferred from the platform', () {
    // theming.md gives glass its own light and dark variants; which one shows
    // is AppTheme.glass's call, and nothing here should guess it.
    for (final platform in Brightness.values) {
      expect(ThemeModeSetting.system.resolve(platform), isNot(DpMode.glass));
    }
  });
}
