# Theming — Light, Dark and Glass

Three theme modes share one layout, one component set and one behaviour. Only tokens and the surface renderer differ. The learner picks **System / Light / Dark / Glass** in Settings (`theme_mode`); *System* resolves to Light or Dark.

| Mode | Name | Character |
| --- | --- | --- |
| Light | Paper & Ink | Warm cream paper, near-black ink, saturated solid fills with ink text, hard 3 px offset shadows, no gradients. Artboards: `deutsch-plan-design-html/android-light/` and `ios-light/`. |
| Dark | Night Ink | Deep violet-black paper, light ink, the same fills lifted one step; offset shadows become 3 px lines at 30 % white. Artboards: `deutsch-plan-design-html/android-dark/` and `ios-dark/`. |
| Glass | Aurora Glass | A drifting backdrop of colour blobs behind every screen; frosted translucent panels with blur, a light border and a top highlight. Buttons stay solid so calls to action never blur. Artboards: all four canvases of `deutsch-plan-v2-aurora-glass-html/`. |

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
| `track` (ring, bars, slider, heat-map's empty day) | ink 47 % | #F4F1FF 37 % | ink 56 % (light) / #F4F1FF 52 % (dark variant) |
| `textSecondary` | #5B5670 | #B7B1CC | #5B5670 |
| `inverseLink` (on the ink snackbar) | #00C2B2 | #007A70 | as light |
| `onAccentMark` (Learning on a Sun field: L1's course bar, L2's step bar) | #FFFFFF | #FFFFFF | #FFFFFF (light) / #0E0C16, the paper (dark variant) |
| `onAccentTrack` (To do on a Sun field: L1's course bar, L2's step bar and exams card) | #15121F 50 % | #15121F 50 % | ink 56 % (light) / #F4F1FF 73 % (dark variant) |
| `outline` | ink 20 % | #F4F1FF 22 % | rgba(255,255,255,0.65) |
| `scrim` (behind a sheet over a screen) | #15121F 32 % | as light | as light |
| `der` | #3D5AFE (text #2F46E0) | #8C9DFF | as light |
| `die` | #FF3D7F (text #D6155C) | #FF8AB2 | as light |
| `das` | #00B86B (text #00804A) | #4FE3A0 | as light |
| `again` Coral | #FF5E4D | #FF8A7D | as light |
| `hard` Tangerine | #FF9F1C | #FFBE5C | as light |
| `good` Lagoon | #00C2B2 | #2EE6D6 | as light |
| `easy` Lime | #A6E22E | #C4F266 | as light |
| `learning` Sun | #FFC61A | #FFD54A | as light |

Glass has a dark variant (aurora at 35 %, smoked glass rgba(30,27,44,0.55)) chosen automatically when the system is in dark mode.

**Fills are not text.** Lagoon is 2.2:1 as text on a card and Coral 3.0:1. So a Material text button (dialogs, the time picker) takes `link`, from `AppTheme`'s `textButtonTheme`, and a destructive one takes `wrongText`, Coral's text colour (#318). Dialogs and the Android time picker sit on `card`, where `link` is 5.2:1; on Oat it would be 4.4. Under glass that card is made opaque over the paper (`AppTheme.dialogTheme`), or the scrim would show through the text.

### Surface renderer

Every card, sheet, header and tab bar is drawn by one widget, `DpSurface`, with a `kind` (`card`, `cardStrong`, `tint(color)`, `bar`). Its implementation switches on the mode:

- **Light/Dark:** `DecoratedBox` with the token fill, 1.5 px outline and the hard offset shadow (3 px down-right; pressed = collapse + translate).
- **Glass:** `GlassPanel` = `ClipRRect` → `BackdropFilter(blur)` → fill → 1 px border → top highlight; shadow 0/8/24 at 10 % (light) / 35 % black (dark). Light fills: card `rgba(255,255,255,0.55)` blur 24, cardStrong `rgba(255,255,255,0.72)` blur 32, border `rgba(255,255,255,0.65)`, highlight `inset 0 1px 0 rgba(255,255,255,0.9)` over a `rgba(255,255,255,0.35)`→transparent sheen. Dark fills: card `rgba(30,27,44,0.55)`, cardStrong `rgba(30,27,44,0.72)`, border `rgba(255,255,255,0.14)`, highlight at 25 %, sheen at 10 %, backdrop `#0E0C16`. `GlassPanel` degrades to a 92 %-opaque tinted surface when: Android API < 31, the device missed the frame budget for 2 s, or the OS "reduce transparency" setting is on.
- **Contrast (#163).** WCAG 2.2 AA holds in every mode: text 4.5:1 on paper, cards, muted chips and fills, checked by `test/core/theme/contrast_test.dart` over the tokens. Glass text sits on a card over any aurora blob at its peak, so Glass has its own text colours: `DpPalette.glass` is the light palette with its text roles (secondary, link, the gender and verdict texts) darkened toward ink until each reaches 4.6:1 over the darkest blob (Cobalt), and `DpPalette.glassDark` lifts the secondary text toward white over the brightest (Sun). Fills and gender swatches are the light and dark palettes'. **Non-text (#437):** a graphic that shows progress reaches 3:1 (WCAG 1.4.11) against what it sits on, so what is not done yet is drawn in `surface.track`, not Oat (1.2:1, and 1.0 under glass): the ring's track, a bar's To do, a slider's rail, the heat-map's empty day, M4's storage and download bars, the widget's ring. It is the page's ink at an alpha that reaches 3:1, with a small margin, on the paper, a card and a strong card, and under glass on each blob at its peak with or without a card over it; translucent, so one value holds on all of them. This departs from the artboards' soft Oat on purpose (owner, #437). The fills over it stay the palette's and are told apart by hue and by the count printed beside them. A bar on a **Sun** field (L1's course bar, L2's step bar and its exams card) has its own: `onAccentTrack`, 3:1 against solid Sun or, under glass, a 22 % Sun wash on each blob (#449); Done is Sun's ink (the page's ink under glass) and Learning `onAccentMark`, 3:1 from the track: white, and the paper in glass dark, where Done and the track are the page's light ink; as L1 draws it — the artboards' Lime Done and Sun Learning vanish on Sun. The splash's loading rule is `track` too. Text is never a token faded on the screen (`ink.withValues(alpha: 0.9)` is a colour the test never meets); `architecture_test.dart` rejects one. A failure is fixed in these tokens, never per screen.

Because screens only use `DpSurface`, adding the glass mode did not change a single screen file. Keep it that way.

### Aurora backdrop (glass only)

`AuroraBackdrop` sits under the shell: 3–4 radial blobs (400–700 dp) in Lagoon, Sun, Raspberry, Cobalt, rendered once to an image and translated on 18–24 s loops (≈ 20 dp travel). The leading blob takes the current tab's colour (Today Lagoon, Learn Sun, Search Raspberry, Me Cobalt) and, in a study session, shifts toward the current noun's gender colour. Drift pauses under reduced motion, when backgrounded, and in fallback mode.

### Typography

Inter (Latin) and Noto Sans Bengali, bundled. Scale: display 40/48 · headline 28/34 · title 20/26 · bodyLarge 17/24 · body 15/22 · label 13/16 · caption 12/16. Bangla is set one step larger at the same role. Supports system text scaling to 200 % without clipping the headword. App bar titles are one line at 600, 22 on Android (between title and headline, as the Android artboards draw it) and bodyLarge 17 on iOS. A title that doesn't fit is cut after its last whole word with "…" (`DpOneLine`), and Bangla still reads a role larger. The bar is 56 / 44 dp at the least, and grows when larger text needs the room (#280, #314).

### Shape, spacing, motion

Radius: cards 16 (glass 20), buttons 12 (glass 16), chips 8, sheets 24 (glass 28). Spacing scale 4/8/12/16/24/32/48. Motion tokens: instant 100 ms, quick 200, standard 300, deliberate 400, celebrate 1200. Glass adds blur-in/out and the press light-sweep. All motion respects the OS reduce-motion setting.

## Platform adaptation

Chrome follows the platform through `core/adaptive/adaptive.dart`: the widgets `AdaptiveScaffold`, `AdaptiveBackButton`, `AdaptiveSwitch`, `AdaptiveSegmented`, `AdaptiveTabBar`, `AdaptiveNavBar` and `AdaptiveRefresh`, and the calls `Adaptive.showSheet`, `showPane`, `showConfirm`, `showTypedConfirm` and `showTimePickerFor`. It is Material 3 on Android and Cupertino on iOS. Content components (word card, rating bar, ring, charts) are identical on both.

## Golden tests

Every screen has golden tests in all three modes on a 390×844 phone and a 1024×768 tablet frame (`test/golden/goldens/<screen>_<mode>_<device>.png`). A theme change that alters a screen must update its goldens in the same PR.
