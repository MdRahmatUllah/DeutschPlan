# S1 · Splash

**Purpose.** Cover database opening and first-run content copy; route to onboarding or Today.

**Prototype.** `Splash-android.html` — app mark, wordmark, caption "Preparing your course · first start only". The mark and the wordmark are now the brand kit's stacked lockup (`docs/sogda-brand-kit/svg/lockup-stacked-tiles-light.svg`, #602): the tiles, an "a" on Paper behind an "Ä" on Sun, over "Sogda" in Inter ExtraBold, tracked −2 %. The artboard's "D" speech bubble is gone.

**Reached from.** App icon, reminder notification, widget, deep link. **Leads to.** S2 (no enrollment) · T1 · or the deep-link target.

**Layout.** Native launch screen (Android 12 SplashScreen API, iOS LaunchScreen) shows the mark; Flutter's first frame is the same composition so there is no visible hand-off. A thin Lagoon progress line under the mark appears only if bootstrap exceeds 600 ms.
- **The mark (#602).** Drawn in Flutter (`SgMark`, `core/components/sg_mark.dart`), no picture and no new dependency: the kit's 108 grid, framed 1.32× in a 218 dp square (288 / 1.32), which puts the tiles at Android 12's own scale (its splash icon is the grid on a 288 dp canvas, masked to the inner 192 dp circle). The square's centre is the screen's, where Android 12 and the pre-12 window (`splash_mark.xml`, the same art cropped tight) draw it, so the hand-off moves nothing; the wordmark and the caption appear under it. Under the mark: the wordmark at 84/200 of the square, its cap height 18.7/200 below it, as the kit's lockup sets them; then 40 dp and the progress line's slot. The column carries as much empty space above the mark, which centres it, and which the iOS launch image, rendered from the column, carries too.
- **Colours.** The field is `primary`: Lagoon, and in dark the lifted Lagoon, as `colors.xml` paints the native window. The tiles and the wordmark are the kit's own colours in every mode (`SgBrand`), Ink on Lagoon: the kit never recolours them. The caption and the progress line stay tokens. Under glass the aurora is the ground, so the mark takes its Lagoon square (the kit's rule for any other ground) and the wordmark the page's ink; no panel.
- **Text size.** The mark and the wordmark are the logo: they keep their size at any text size. The caption scales.

**Functional requirements**
- FR-S1-01 Bootstrap MUST: open user.db (create schema if absent), copy content.db when `content_version` differs, attach it, load settings, resolve theme.
- FR-S1-02 Warm start to Today MUST be < 500 ms; first run (content copy) SHOULD be < 2 s.
- FR-S1-03 On bootstrap failure show a full-screen error with *Retry* and *Export progress* — never a blank screen.
- FR-S1-04 Deep links and notification taps MUST be honoured after bootstrap.

**Business rules.** BR-CONTENT-01/02 (uid stability during content copy).

**States.** first run · normal · updating content · error.

**Motion.** Mark shrinks toward Today's ring position while Today fades up 8 px (standard).

**Data.** `bootstrap.dart` → `AppDatabase.open()`, `ContentUpdater.check()`, `SettingsRepository.load()`.

**Developer notes.** Keep all I/O in `bootstrap()` before `runApp`; use `FlutterNativeSplash`-style preserve/remove only if the platform splash flickers. Probe the bundled asset's version without loading the whole 5.5 MB into memory twice (write to a temp file once).

**Tests.** Widget: error state shows Retry; unit: content version diff triggers copy and update-card row.
