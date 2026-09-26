# Sogda — brand kit (v1)

**Name:** Sogda · **Domain:** sogda.de · **Tagline:** The road to a new language
**Store title:** Sogda: German A1–C2 · **Suggested application ID:** `de.sogda.app` (permanent after the first Play upload)

## The mark
Two letter tiles: the letter you know (a) behind, the new language's letter (Ä) in front.
The Sogdians were the interpreters of the Silk Road; the mark is that crossing, from your language to the new one.
Later courses change only the front tile (É for French, Ñ for Spanish).

- **Variant A · Tiles** — the app icon and the main logo. Use this everywhere by default.
- **Variant B · Tiles + Silk Road** — adds a dotted route over the tiles. Too busy below 48 px, so it is
  for large marketing use only (splash animation, onboarding, store feature graphic), never the launcher icon.

## Colours
| Role | Hex |
|---|---|
| Lagoon (ground) | #00C2B2 |
| Sun (front tile) | #FFC61A |
| Ink (outline, text) | #15121F |
| Paper (back tile, light background) | #FFF8EE |
| Night (dark background) | #13111D |

## Type
Wordmark: **Inter ExtraBold** (weight 800, optical size 32), tracking −2 %, outlined to paths in the SVGs.
Tagline: Inter SemiBold. Inter is also the app's UI typeface. Licence: SIL OFL 1.1.

## Files
| File | Use |
|---|---|
| `svg/icon-tiles-full.svg` | Master icon, Lagoon background |
| `svg/icon-tiles-foreground.svg` + background `#00C2B2` | Android adaptive icon (108 × 108 grid, art inside the 66-unit safe circle) |
| `svg/icon-tiles-mono.svg` | Android 13+ themed icon; silhouette for the notification icon |
| `svg/lockup-horizontal-tiles-light/-dark.svg` | Website header, documents, store feature graphic |
| `svg/lockup-stacked-tiles-light.svg` | Splash, square placements |
| `svg/wordmark-ink.svg` | Name only |
| `png/play-store-icon-512.png` | Google Play icon (Play rounds the corners; add no shadow) |
| `png/adaptive-*-432.png` | xxxhdpi layers; regenerate other densities with Android Studio's Image Asset tool |
| `svg/icon-road-*`, `svg/lockup-*-road-*` | Variant B, marketing only |

## Rules
- Clear space around the mark: the height of the Ä's dots on every side.
- Never recolour the tiles, add gradients, or stretch the mark. On photos, place it on its Lagoon square.
- The name is always one word with a capital S: **Sogda**, never SOGDA or sogda (except in URLs).

## Status
These are production-ready sketches, not a designer's final artwork. Before launch: a designer refines
the tile corners and glyph spacing, and exports the full Android mipmap set and the iOS 1024 px icon.
