# 3 · Capabilities

What Sogda v1.0.1 can do as a system, apart from its features: where it
runs, what works offline, which languages it speaks, how accessible it is,
how it looks, what its voice can do, how much content it carries, how it
keeps a learner's data safe, how fast and how big it is, what it asks
permission for, and where its limits are. Numbers come from the docs, the
code, `content.db` and `tools/perf_baseline.json` at v1.0.1, unless a line
names v1.1.0 or v1.2.0, whose additions are those on main by 2026-10-03.

> The detailed specs in [`docs/`](../README.md) are the source of truth. If
> anything here disagrees with them, the spec wins and this page is wrong.

## Platforms and form factors

| | v1.0.1 |
|---|---|
| **Android** | 8.0 and later (minSdk 26), built against API 37 (compileSdk and targetSdk). Native libraries aligned to 16 KB pages, as Play requires for Android 15+ ([`release.md`](../05-dev-guide/release.md), ADR 19) |
| **iOS** | Not released. The target is iOS 16+; the iOS code paths (Cupertino chrome, iOS goldens) are built and tested on Windows, and the release waits for a Mac (#171) |
| **Phones** | Portrait only. Turned sideways at large text, 16 screens were cut, so phones stay upright (#577, the owner's call) |
| **Tablets** | A shortest side of 600 dp or more. They rotate, and W1 opens as a 420 dp side pane instead of a sheet; W2 shows every column at once. Android 16 ignores an app's orientation lock from 600 dp up, so the line matches Android's |
| **Test frames** | Goldens on a 390 × 844 phone and a 1024 × 768 tablet |

## Offline first

Every study feature works in airplane mode. There is no "no connection"
screen for core features
([`accessibility-performance.md`](../01-architecture/accessibility-performance.md)).

| Needs the network | When | Notes |
|---|---|---|
| **Supertonic voice download** | Only when the learner starts it (S2 page 5, or M4) | Wi-Fi only by default (`models_wifi_only`); resumable; pauses off Wi-Fi |
| **Hy-MT2 translation download** (v1.2.0) | Only when the learner starts it (M4, which M3's switch and D2's card lead to) | The same rules as the voice; the two can download side by side |
| *Rate Sogda on Google Play* (v1.2.0) | At the learner's tap in Me | Opens the Play listing (FR-M1-05); Play's review card after the first passed mock exam is the Play Store's own UI (BR-RATE-01) |
| Web-search chips (Duden, DWDS, Wiktionary, Linguee, Google) | At the learner's tap | Open in an in-app browser; the app itself sends nothing (BR-SEARCH-04) |
| *Report a problem*, About's *Contact* | At the learner's tap | Open a GitHub issue page in the browser |
| Export | At the learner's tap | The system share sheet; the learner chooses where the file goes |

What does **not** need the network:

- The course, all 5,142 words and their examples, which ship inside the app.
- *Check for update* on a model, which reads the manifest bundled with the
  app; the manifest changes only with an app update.
- Content updates, which arrive as app updates through the store.
- Reminders and the widget, which are built on the phone from the local plan.
- **A document** (v1.2.0), from pasted or shared text, a PDF or photos: a
  PDF's text layer is read by pdfbox-android, a photo by ML Kit's text
  recogniser with its Latin model bundled in the app, and the words by
  Sogda's own lemmatiser and matcher (BR-DOC-01). Nothing is downloaded
  for them.
- **Translation** (v1.2.0), once Hy-MT2 is on the phone: llama.cpp runs it
  there ([`translation.md`](../03-domain/translation.md)).

## Languages

v1.1.0 adds Russian and Polish (M8, #1085): each ships only when complete
(PIPE-08), and the learner reads any one or two of the four, a first and an
optional second.

| | English | Bangla | Russian (v1.1.0) | Polish (v1.1.0) |
|---|---|---|---|---|
| **App language** (all UI copy) | Yes: 992 strings | Yes: 992 strings, every number in Bangla digits | Yes: 992 strings | Yes: 992 strings |
| **Meaning language** (first or second) | Yes | Yes | Yes | Yes |
| **Word meanings** | All 5,142 | All 5,142 | All 5,142 | All 5,142 |
| **Pronunciation of each word** | All, an English respelling (v1.1.0) | All 5,142, in Bangla letters (while Bangla is chosen) | All, in Russian letters | All, in Polish spelling |
| **Interference tips** | All 622 | All 622 | Those written for Russian speakers | Those written for Polish speakers |
| **Example translations** (10,691) | All | None: English shows (#598) | All | All |
| **Grammar rules** (182 topics) | All | None | All | All |
| **Category names** | All | Shown in English (#425) | All (#1128) | All (#1128) |

Each guide comes with a one-line key to read it (#1122). Search finds a word
by its meaning in the learner's Russian or Polish, and quizzes, mock exams,
placement and the compare quiz ask in the learner's languages (#1120, #1121).

- **The German stays German.** Headwords, examples and the date on Today
  ("Montag, 21. September") are German in either app language, and German
  content never takes Bangla digits. Step codes (A1.1) and product versions
  keep their own digits.
- **`test/l10n_test.dart`** fails the build on a string with no description,
  a string missing in Bangla, or a literal left in the code.
- **Bangla typography:** Noto Sans Bengali, set one type step larger than the
  Latin text in the same role. A Bangla word too wide for its line first
  shrinks, down to 80 %, and only then breaks between aksharas, never inside a
  conjunct and with no hyphen (#504, #522, the owner's call).
- **Screen readers switch voices mid-sentence.** The course's German is
  tagged `de-DE` and Bangla `bn-BD`, so TalkBack and VoiceOver read each in
  its own voice; the app's own copy is read in the app's language.
- **Translation** (v1.2.0) goes between German and each of the four meaning
  languages, both ways (`translation.md`, *Directions*).
- **Documents** (v1.2.0) are German: a text where fewer than half the words
  read as German gets a warning first (FR-D1-04). OCR reads the Latin
  script, the only model bundled.

## Accessibility

The target is WCAG 2.2 AA ([`accessibility-performance.md`](../01-architecture/accessibility-performance.md)).

- **Text up to 200 %** on every screen, with no word broken mid-syllable to
  fit and nothing cut off. Past 130 %, things side by side stack; a long
  German compound breaks at a syllable with a visible "-".
- **The large-text audit.** Every golden case runs again at 150 % and 200 %,
  in English and in Bangla (#581), under Android 14's nonlinear text scaling.
  At 200 %, a screen with a text field is checked again with the keyboard up
  (#584). The audit fails on a layout error, text clipped to a box, a word
  broken other than at a syllable, or text cut to its line limit
  ([`testing.md`](../05-dev-guide/testing.md)). Today, T2, Settings, the exam
  runner and Search also have goldens drawn at 200 %.
- **Typing at large text.** With the keyboard up past 130 %, what is asked
  stays in view above the field: headers give up their row, prompts drop one
  type size, and what still doesn't fit scrolls with the field kept in view.
  The exam clock moves to the bar above the keyboard (v1.0.1).
- **Screen readers** (TalkBack, VoiceOver). Every control has a name, checked
  on every golden case. The headword is announced with its article and
  gender ("die Wohnung, feminine") when the article makes the gender certain.
  After a rating, focus moves to the next card.
- **Tap targets** are at least 48 dp (44 pt under iOS chrome), checked on
  every golden case. Controls drawn smaller keep their look and get an
  invisible larger hit area (#478). Two documented exceptions: Me's twelve
  step badges (23.5 dp, which meet WCAG's 24 dp with spacing) and iOS's
  segmented control (28 pt, as UIKit draws it).
- **Contrast:** text 4.5:1, large text, icons and progress graphics 3:1, in
  all three themes, glass text checked against the aurora colour it
  contrasts least with. `contrast_test.dart` checks the tokens. Non-text 3:1
  holds everywhere, even where the artboards were softer (#437).
- **Never colour alone.** Articles are printed as well as coloured, statuses
  have labels, verdicts have icons and words. D2's level marks are a fill and
  an ink underline, with the level named on the card; ink on every level's
  fill is at least 6.4:1 in all eight canvases
  ([`doc-words.md`](../04-screens/doc-words.md)).
- **Alternatives.** Every swipe has a button. Timers can be paused or turned
  off. Listening questions can be switched off in Settings. Every sound has
  its text on screen.
- **Reduce motion:** cross-fades instead of slides, no confetti, no aurora
  drift, nothing animating its size. Three iOS-chrome movements remain (the
  sheet, the dialog's scale-in, the segmented thumb), noted as a known edge.
- **Reduce transparency:** the glass theme draws opaque.

## Themes and platform look

| Theme | Name | Character |
|---|---|---|
| Light | Paper & Ink | Warm cream paper, near-black ink, solid fills, hard 3 px offset shadows |
| Dark | Night Ink | Deep violet-black paper, light ink, the same fills lifted a step |
| Glass | Aurora Glass | Frosted panels over a slowly drifting colour field; a smoked dark variant follows the phone's dark mode |

- **System** (the default) follows the phone's light or dark setting.
- **Glass falls back to near-opaque** (92 %) panels on Android below API
  31, when the device misses its frame budget for 2 s, or with reduce
  transparency on. At most three blur layers are on screen at once
  ([`theming.md`](../01-architecture/theming.md)).
- **No dynamic (Material You) colour** (ADR 12): the gender colours must stay
  the same on every phone.
- **Adaptive chrome:** Material 3 on Android, Cupertino on iOS, through one
  set of adaptive wrappers. The content (cards, rating bar, ring, charts) is
  identical on both.
- **Goldens:** every screen in all three themes on phone and tablet, plus iOS
  variants where the chrome differs.

## Voice

| | The phone's voice | Supertonic 3 |
|---|---|---|
| **What it is** | Android's own German text-to-speech (`de-DE`, through `flutter_tts`) | An on-device neural voice (ONNX, about 99 M parameters, on the CPU) |
| **Size** | None: part of the phone | 399 MB to download (nine files, SHA-256 checked) |
| **Voices** | Whatever the phone has | Anna (the default), Jonas, Lena |
| **Role** | Speaks until Supertonic is downloaded, and whenever it fails | Used once downloaded (from S2 or M4), unless the learner picks the phone's voice |

([`tts.md`](../03-domain/tts.md), [`model-manager.md`](../04-screens/model-manager.md))

- **Speed:** 0.5–1.5× in Settings; a long press on the study card's, W1's
  or T5's speaker plays at 0.75× of it.
- **Timing (emulator, release build).** Supertonic's four sessions take about
  2.3 s to open. They open with the first clip a screen needs (a session's
  look-ahead list as it opens, or a tap), and close again in the background
  or under memory pressure (#638, #906), about 400 MB less while unused.
  A new word then takes about 1 s to its first sound; a cached one starts at
  once. So a session prepares its clips ahead (up to 40), and a list a
  release stopped goes on after the next speak: a prepared card played
  146–266 ms after its speak on the emulator. The < 300 ms budget is met for prepared clips, not for a
  word never heard before.
- **Cache:** the last 200 clips on disk, per voice and speed; cleared when
  the model is updated.
- **Memory:** about 520 MB for the app (PSS, on the emulator) with
  Supertonic's sessions open. No budget has been set (the owner's call).
- **Downloads** run in the background with a progress notification (Android),
  resume after a lost connection, wait for Wi-Fi when *Wi-Fi only* is on,
  and keep a 100 MB free-space margin so a download never fills the phone. A
  model is activated only when every file's checksum passes.
- **Failure:** if Supertonic fails, the phone's voice speaks with a one-time
  notice. If the phone has no German voice, speakers show a slashed icon and
  explain how to install one.

## Content scale

| | Count |
|---|---|
| Course steps | 12 (A1.1 … C2.2), in 6 CEFR levels |
| Words and phrases | 5,142 to learn: A1 1,337 · A2 1,067 · B1 396 · B2 1,025 · C1 819 · C2 498, plus 167 lesson notes and comparisons |
| Example sentences | 10,691 (two for almost every word) |
| Grammar topics | 182: 10 or 11 per step from A1.1 to B1.2, 20 per step from B2.1 |
| Word categories | 159 |
| Interference tips | 622, in English and Bangla |
| Words with an article | 2,750 |
| `content.db` | About 6 MB (its search tables an index of the words, not a copy, #712), content version `202609260837`, compiled from six workbooks, one a level |

The counts come from `content.db` itself; a test ties the About screen's
counts to the pipeline's manifest (FR-M9-01).

**Content updates keep progress.** Each word's id is a hash of its level,
German, part of speech and English (BR-CONTENT-01), and progress is keyed by
it. On an update, new words join their step's queue, removed words are hidden
but keep their history, a changed Bangla meaning shows an *Updated* chip for
7 days, and Today shows one card with the counts
([`content-database.md`](../02-data/content-database.md)). A content-only
release bumps the patch version ([`release.md`](../05-dev-guide/release.md)).

## Keeping the learner's data safe

- **Transactions.** Rating a card is one transaction (the word's state, the
  review log, the plan, the day's totals, the undo record), so a failure
  leaves nothing half-written. Planning a day is one transaction. In an
  exam, a tapped answer is written at once and a typed one when the learner
  moves on; Writing's text and the clock are written every 10 s. A crash
  loses at most the answer being typed and 10 s of the clock.
- **When a write fails** during study, a sheet says "Couldn't save that
  answer. Every card before it is saved." with *Retry* and *Export progress*.
  If the app can't open its data at start, a full-screen error offers the
  same two (FR-S1-03, #174).
- **Undo.** A rating or a word action can be undone from its snackbar; the
  undo stack keeps the last 20.
- **Export** writes one JSON file: word states, review log, plans, quiz and
  exam history, settings, the learner's own words and the documents' text,
  words, sentences and queue (not the translation cache, the undo stack,
  Speaking recordings or a document's photos, BR-DOC-06).
- **A deleted document** takes its photos and what it found with it, never
  the words added from it or their sentences (BR-DOC-05).
- **Import** previews the file first. It migrates an older file forward and
  refuses one from a newer build. *Merge* keeps the more recent of each word;
  *Replace* wipes and inserts in one transaction, so a failed import changes
  nothing.
- **Reset** is one step or everything; everything needs RESET typed, and
  keeps the theme, the app language and the downloaded models.
- **Schema migrations** are tested from every schema version's committed
  fixture ([`user-database.md`](../02-data/user-database.md)).
- **The course is read-only by construction** (ADR 26): nothing in the app
  can write to it, and an architecture test fails the build if anything
  tries.
- **Dates** are local calendar days: a clock or time-zone change never plans
  a day twice or drops one.

## Performance

Budgets from [`accessibility-performance.md`](../01-architecture/accessibility-performance.md),
and the baselines recorded in `tools/perf_baseline.json` on the developers'
emulator. The emulator is not a mid-range phone: it catches regressions, and
the absolute budgets are reported there, not enforced, except search's. The
owner checks cold and warm start on a real phone before each release.

| Target | Budget | Baseline (emulator) | Fails when over baseline by |
|---|---|---|---|
| Cold start to Today | < 1.5 s on a mid-range 2022 phone | 2,799 ms | 50 % |
| Warm start | < 500 ms | 1,048 ms | 50 % |
| Card transition after rating | < 16 ms a frame | build 4.0 ms average (9.2 ms p90); raster 63 ms average | 50 % |
| Glass word list, flung | 60 fps | build 2.9 ms average; raster 69 ms average | 50 % |
| Search | < 50 ms a keystroke, after a 120 ms debounce | 17.8 ms median, 32.6 ms slowest | 25 % (the 50 ms budget is enforced too) |
| App size | at most 3 % over its baseline | arm64-v8a APK 72.33 MB | 3 % |
| Supertonic first audio | < 300 ms for one word | see *Voice* | not measured by `perf.py` |
| Memory with Supertonic | no budget yet | about 520 MB PSS | — |

- **How it is measured:** `python tools/perf.py all`, at milestone
  completion and before a release, not per PR (#167). The last run before
  v1.0.0 passed: size 72.44 MB, cold 3,268 ms, warm 807 ms, frames and search
  within their margins.
- **Size.** The arm64 APK went from 159.5 MB to 72.3 MB when llama.cpp was cut
  to its CPU backend (ADR 27), then to 51.2 MB when llamadart was removed (ADR 29). The APK stands in for the one-ABI download
  Play serves, which is compressed and so smaller. The voice model and
  Hy-MT2 are downloaded separately. v1.2.0 adds three libraries:
  - **pdfbox-android:** +1.8 MiB (52.22 → 54.12 MB, ADR 31), the figure
    `perf_baseline.json` has held since. Its post-quantum Bouncy Castle tables
    (4.1 MB) are left out; its CJK CMaps, 1.2 MB, are #1318's to trim.
  - **ML Kit's text recognition:** about 12 MB a phone through the App
    Bundle's per-ABI split, 11 MB of it the arm64 pipeline library
    (`doc-import.md`). A universal APK carries all three ABIs, +31 MB.
  - **llama.cpp's CPU libraries,** back with Hy-MT2 (ADR 30): +22.95 MB of
    the arm64 APK, 89.19 MB in all on 2026-10-03 (#154; ADR 29 had measured
    about 21 MB when it took them out).

  v1.2.0's own total, feature by feature, is #1306's measurement.
- **The documents' budget:** a two-page letter (about 600 words) goes
  through the matcher in under 500 ms, in an isolate, so D2 never blocks
  the UI (`matcher_test` on the host; D2's line in `perf.py` comes with
  #1306 and #1319). D2 builds a 20,000-character text a paragraph at a time.
- **Cold start** is measured to Android's "Fully drawn", which the app
  reports once Today shows its plan, not at the splash's first frame (#462).

## Privacy and permissions

- **Collected:** nothing. The Play data-safety form declares no data
  collected and none shared: no account, no analytics, no ads
  ([`release.md`](../05-dev-guide/release.md)).
- **Stored:** everything in `user.db` and app-private files on the phone
  (BR-PRIV-02), a document's photos included, under
  `<appSupport>/documents/<id>/`, each without its metadata (BR-DOC-05).
- **Network:** no call without a user action (BR-PRIV-01; see *Offline
  first*). A library's own reporting counts: ML Kit's usage metrics are cut
  off in the manifest, and a release checks the merged manifest for
  `datatransport`, `firebase`, `clearcut` and `measurement` after a
  dependency update.

The Android permissions, as the merged manifest has them:

| Permission | Why | When it is asked |
|---|---|---|
| `RECORD_AUDIO` | The Speaking task's recording, kept on the phone | On the first *Record* |
| `POST_NOTIFICATIONS` | The daily reminder, and a model download's progress | When the reminder is switched on, or a download starts (Android 13+); a refusal still downloads, without the notification (#501) |
| `RECEIVE_BOOT_COMPLETED` | Reminders scheduled again after a restart | Not asked (install-time) |
| `INTERNET`, `ACCESS_NETWORK_STATE` | Model downloads and their Wi-Fi-only rule | Not asked |
| `WAKE_LOCK` | WorkManager carrying a model download or the widget's refresh on in the background; no foreground service (#611) | Not asked |
| `VIBRATE` | The reminder notification | Not asked |

Reminders use an inexact alarm, so no exact-alarm permission is needed.
v1.2.0 adds no permission: *Take photos* opens the phone's own camera app
and *Choose images* the system photo picker (both through `image_picker`),
so Sogda holds neither the camera nor the gallery. A shared or chosen PDF
is read from Sogda's own copy in its cache, deleted once its text is out
([`doc-import.md`](../04-screens/doc-import.md)).

## Background behaviour

([`notifications-widget.md`](../03-domain/notifications-widget.md))

| Task | When | Does |
|---|---|---|
| Reminder | The learner's time (19:30 by default), on study days only, a week scheduled ahead | Shows today's plan; with *Only when there is something to do* on, none on a finished day or one with nothing due |
| `plan_pregenerate` | 00:05 local, daily | Plans the day, so the widget and the reminder are right, and rolls the week of reminders on |
| `reminder_compose` | 10 minutes before the reminder | Writes the plan into the reminder, or cancels it |
| `widget_refresh` | Hourly while a widget is placed, and after every session | Rewrites the widget's snapshot |

The Android widget comes in two sizes (2×2, 4×2), follows the phone's light
or dark mode, and draws the glass theme as its opaque fallback.

## Limits: what it can't do yet

| Limit | Detail |
|---|---|
| **No iOS release** | Waits for a Mac: #171 (pipeline), #161 (widget), #398 (simulator smoke test) |
| **Translation is a download, and a machine's** | Hy-MT2 needs 1.1 GB, and in #1278's spot check about a third of its meanings for words outside the course were wrong in Polish and Bangla: they are labelled and offered as suggestions, never filled in |
| **A document's size** | 30 pages or 20,000 characters, whichever comes first; the rest is cut at a sentence end, and the learner told (BR-DOC-02) |
| **PDFs** | Only a text layer is read: a scan goes through the photos, and a PDF with a password is refused, since Sogda asks for none |
| **OCR** | Latin script only; a hard page is the learner's to check (*Check the text*, FR-D1-03) |
| **The lemmatiser's misses** | Recall 0.998 on the corpus: a form the course doesn't have, such as the bench plural «Bänken», reads as outside the course |
| **English-only parts of the course** | Example translations, grammar rules and category names |
| **Self-assessed speaking and writing** | No speech recognition; the app checks length, target words and connectors, and the learner ticks the rubric |
| **Thin B1** | 379 words, against 1,035 at A2 and 1,023 at B2; mock exams at A1.1–B1.2 reuse a grammar topic or two |
| **One course, one learner per phone** | No profiles, no sync; progress moves by export file |
| **Supertonic's first sound for a new word** | About 1 s, over the 300 ms budget, unless prepared ahead |
| **Listening replays** | Counted in memory, so a resumed exam gives each word its three plays again |
| **Reminders across time zones** | A learner who changes time zone hears the old zone's time until the app next starts |
| **The update card's counts** | The newest update's alone, not netted across updates missed in between (#496, the owner's call) |
| **Default FSRS weights** | Not tuned to the learner; optimisation from the review log is future work (ADR 7) |
