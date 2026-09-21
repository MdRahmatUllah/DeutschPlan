# S1 · Splash

**Purpose.** Cover database opening and first-run content copy; route to onboarding or Today.

**Prototype.** `Splash-android.html` — app mark ("D" in a Sun speech bubble), wordmark, caption "Preparing your course · first start only".

**Reached from.** App icon, reminder notification, widget, deep link. **Leads to.** S2 (no enrollment) · T1 · or the deep-link target.

**Layout.** Native launch screen (Android 12 SplashScreen API, iOS LaunchScreen) shows the mark; Flutter's first frame is the same composition so there is no visible hand-off. A thin Lagoon progress line under the mark appears only if bootstrap exceeds 600 ms.

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
