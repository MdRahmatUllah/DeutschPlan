# Theming — Light, Dark and Glass

Three theme modes share one layout, one component set and one behaviour. Only tokens and the surface renderer differ. The learner picks **System / Light / Dark / Glass** in Settings (`theme_mode`); *System* resolves to Light or Dark.

| Mode | Name | Character |
| --- | --- | --- |
| Light | Paper & Ink | Warm cream paper, near-black ink, saturated solid fills with ink text, hard 3 px offset shadows, no gradients. The prototype in `design/android-light/` shows this mode. |
| Dark | Night Ink | Deep violet-black paper, light ink, the same fills lifted one step; offset shadows become 3 px lines at 30 % white. |
| Glass | Aurora Glass | A drifting backdrop of colour blobs behind every screen; frosted translucent panels with blur, a light border and a top highlight. Buttons stay solid so calls to action never blur. |

## Token architecture

`AppTheme` exposes one `DpTokens` object (a `ThemeExtension`) per mode. Widgets read tokens, never hex values.

```dart
final t = context.tokens;            // DpTokens
Container(color: t.surface.card, …)  // never Color(0xFFFFFFFF)
```

### Colour tokens

| Token | Light | Dark | Glass |
| --- | --- | --- | --- |
| `primary` Lagoon | #00C2B2 | #2EE6D6 | #00C2B2 |
| `accent` Sun | #FFC61A | #FFD54A | #FFC61A |
| `ink` (text) | #15121F | #F4F1FF | #15121F (light) / #F4F1FF (dark variant) |
| `paper` (background) | #FFF8EE | #13111D | `backdrop` #F6F3FF + aurora blobs |
| `card` | #FFFFFF | #1E1B2C | rgba(255,255,255,0.55) blur 24 |
| `cardStrong` | #FFFFFF | #1E1B2C | rgba(255,255,255,0.72) blur 32 |
| `muted` Oat | #F3EADB | #29253A | rgba(255,255,255,0.35) |
| `textSecondary` | #5B5670 | #B7B1CC | #5B5670 |
| `outline` | ink 20 % | #F4F1FF 22 % | rgba(255,255,255,0.65) |
| `der` | #3D5AFE (text #2F46E0) | #8C9DFF | as light |
| `die` | #FF3D7F (text #D6155C) | #FF8AB2 | as light |
| `das` | #00B86B (text #00804A) | #4FE3A0 | as light |
| `again` Coral | #FF5E4D | #FF8A7D | as light |
| `hard` Tangerine | #FF9F1C | #FFBE5C | as light |
| `good` Lagoon | #00C2B2 | #2EE6D6 | as light |
| `easy` Lime | #A6E22E | #C4F266 | as light |
| `learning` Sun | #FFC61A | #FFD54A | as light |

Glass has a dark variant (aurora at 35 %, smoked glass rgba(30,27,44,0.55)) chosen automatically when the system is in dark mode.

### Surface renderer

Every card, sheet, header and tab bar is drawn by one widget, `DpSurface`, with a `kind` (`card`, `cardStrong`, `tint(color)`, `bar`). Its implementation switches on the mode:

- **Light/Dark:** `DecoratedBox` with the token fill, 1.5 px outline and the hard offset shadow (3 px down-right; pressed = collapse + translate).
- **Glass:** `GlassPanel` = `ClipRRect` → `BackdropFilter(blur)` → fill → 1 px border → top highlight; shadow 0/8/24 at 10 %. `GlassPanel` degrades to a 92 %-opaque tinted surface when: Android API < 31, the device missed the frame budget for 2 s, or the OS "reduce transparency" setting is on.

Because screens only use `DpSurface`, adding the glass mode did not change a single screen file. Keep it that way.

### Aurora backdrop (glass only)

`AuroraBackdrop` sits under the shell: 3–4 radial blobs (400–700 dp) in Lagoon, Sun, Raspberry, Cobalt, rendered once to an image and translated on 18–24 s loops (≈ 20 dp travel). The leading blob takes the current tab's colour (Today Lagoon, Learn Sun, Search Raspberry, Me Cobalt) and, in a study session, shifts toward the current noun's gender colour. Drift pauses under reduced motion, when backgrounded, and in fallback mode.

### Typography

Inter (Latin) and Noto Sans Bengali, bundled. Scale: display 40/48 · headline 28/34 · title 20/26 · bodyLarge 17/24 · body 15/22 · label 13/16 · caption 12/16. Bangla is set one step larger at the same role. Supports system text scaling to 200 % without clipping the headword.

### Shape, spacing, motion

Radius: cards 16 (glass 20), buttons 12 (glass 16), chips 8, sheets 24 (glass 28). Spacing scale 4/8/12/16/24/32/48. Motion tokens: instant 100 ms, quick 200, standard 300, deliberate 400, celebrate 1200. Glass adds blur-in/out and the press light-sweep. All motion respects the OS reduce-motion setting.

## Platform adaptation

Chrome follows the platform through `Adaptive*` wrappers (`AdaptiveScaffold`, `AdaptiveSheet`, `AdaptiveDialog`, `AdaptiveSwitch`, `AdaptiveSegmented`, `AdaptiveTimePicker`): Material 3 on Android, Cupertino on iOS. Content components (word card, rating bar, ring, charts) are identical on both.

## Golden tests

Every screen has golden tests in all three modes on a 390×844 phone and a 1024×768 tablet frame (`test/golden/<screen>_<mode>_<device>.png`). A theme change that alters a screen must update its goldens in the same PR.
