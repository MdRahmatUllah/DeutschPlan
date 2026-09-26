import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:material_ui/material_ui.dart' show Brightness;

/// Turns the stored `theme_mode` into the mode the theme actually renders.
///
/// There are two enums because they answer different questions:
/// [ThemeModeSetting] is what the learner chose, including "follow the
/// platform"; [SgMode] is what `AppTheme` builds, which can never be "system".
/// The mapping between them lives here so `themeProvider` (FR-M3-02) and
/// anything else that needs it use the same one — a wrong pairing would be a
/// silently wrong theme, not a compile error.
///
/// It sits in `core/theme/` rather than beside the setting because [SgMode] and
/// [Brightness] do, and the data layer has no business importing either.
extension ThemeModeResolution on ThemeModeSetting {
  /// [platform] is only read for [ThemeModeSetting.system].
  ///
  /// Glass is a deliberate choice, never inferred: `theming.md` gives it a
  /// light and a dark variant of its own, and which one shows is the
  /// platform's call inside `AppTheme.glass`, not this one's.
  SgMode resolve(Brightness platform) => switch (this) {
    ThemeModeSetting.system =>
      platform == Brightness.dark ? SgMode.dark : SgMode.light,
    ThemeModeSetting.light => SgMode.light,
    ThemeModeSetting.dark => SgMode.dark,
    ThemeModeSetting.glass => SgMode.glass,
  };

  /// True when the platform's brightness decides what is drawn.
  bool get followsPlatform => this == ThemeModeSetting.system;
}
