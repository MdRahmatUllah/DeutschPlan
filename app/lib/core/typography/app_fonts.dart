import 'package:material_ui/material_ui.dart';

/// The bundled font families.
///
/// Both are variable fonts with a `wght` axis spanning 100-900, so every weight
/// in the type scale of `docs/01-architecture/theming.md` comes out of one file
/// per family. The full scale itself lands with the theme in #36.
abstract final class AppFonts {
  /// Latin, German diacritics and punctuation. Axes: `opsz` 14-32, `wght` 100-900.
  static const String latin = 'Inter';

  /// Bangla. Axes: `wght` 100-900, `wdth` 62.5-100.
  static const String bengali = 'Noto Sans Bengali';

  /// Inter contains no Bangla glyphs, so any string that mixes German and Bangla
  /// - which is most of this app's content - needs Bangla resolved through a
  /// fallback. Every text style in the app sets this.
  static const List<String> fallback = <String>[bengali];

  /// Instances the `wght` axis of the variable fonts.
  ///
  /// `fontWeight` alone also works on a variable font, but stating the axis is
  /// explicit and survives a future switch to static instances.
  static List<FontVariation> weight(double value) => <FontVariation>[
    FontVariation('wght', value),
  ];
}
