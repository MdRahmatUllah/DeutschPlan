import 'package:material_ui/material_ui.dart';

/// The brand kit's colours: `docs/sogda-brand-kit/README.md` (#602).
///
/// Not tokens, and on purpose: the kit says the tiles are never recoloured,
/// so the mark draws in these in every mode, glass and dark included. They
/// are the light palette's own values — Lagoon is `primary`, Sun `accent`,
/// Ink `ink`, Paper the light paper and Night the dark one —
/// which `sg_brand_test.dart` holds them to.
abstract final class SgBrand {
  /// The ground: the icon's square and the splash's field.
  static const Color lagoon = Color(0xFF00C2B2);

  /// The front tile, the new language's letter.
  static const Color sun = Color(0xFFFFC61A);

  /// The outlines, the shadows, the letters and the wordmark.
  static const Color ink = Color(0xFF15121F);

  /// The back tile, the letter the learner knows.
  static const Color paper = Color(0xFFFFF8EE);

  /// The dark background the kit's dark lockups sit on.
  static const Color night = Color(0xFF13111D);
}
