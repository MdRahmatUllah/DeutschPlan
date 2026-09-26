# Accessibility, localisation, offline and performance

## Accessibility (WCAG 2.2 AA target)

- Contrast: text 4.5:1, large text and icons 3:1 in all three modes; glass text is checked against the brightest blob it can overlay. Progress graphics 3:1 too (1.4.11): the ring's track, bar tracks and the heat-map's empty days take `surface.track` (#437). `contrast_test.dart` measures both over the tokens.
- Screen readers (#162):
  - **Every control labelled.** `goldenTest` checks each case with Flutter's `labeledTapTargetGuideline`.
  - **An icon-only control shows its name on a long press** under Material chrome, as a Material icon button does (`AdaptiveTooltip`). iOS has no tooltips. The name is never read twice, since the control's label is the same words. A speaker whose long press replays slowly shows it on a hover only. `goldenTest` checks every icon-only control under Material chrome.
  - **The headword is announced with its article and gender** ("die Wohnung, feminine"), the gender in the app's language. The gender is said only when the article makes it certain:
    - *der* and *das* always;
    - *die* only for a noun with a plural (`Word.forms`), since a plural-only noun (die Leute, die Kosten) takes *die* too and the course doesn't mark one;
    - the learner's own words and a compare set's members have no plural, so their *die* goes without a gender.
  - **Voices.** German is tagged `de-DE` and Bangla `bn-BD`, so TalkBack and VoiceOver switch voices mid-string.
    - The tags are on the text's spans (`DpScript.spans`). A label on the whole `Text` would drop them, so `DpText` sets none unless its caller does.
    - Bangla is always tagged. Latin text is tagged `de-DE` only when it is the course's German: the headword, `DpText(german: true)` (examples, sentences, the placement check, the German date) and the cloze. The app's own copy is untagged, so it is read in the app's language, not in a German voice.
- Every control a screen reader hears as a button can be pressed by one. A `Semantics(button: …)` that hides its child's semantics, through `ExcludeSemantics` or `excludeSemantics: true`, also hides the tap its `GestureDetector` would give. So it carries `onTap:` (and `onLongPress:`) itself (#312). `architecture_test.dart` enforces this.
- Never colour alone: articles printed, statuses labelled, verdicts have icons and words.
- Text scaling to 200 % on every screen, and no word broken mid-syllable to fit it (#165):
  - Above 100 % a long German compound, or a Bangla word, in a narrow place may break at a syllable (`DpScript.allowBreaks`, soft hyphens). Only above 100 %: a soft hyphen splits the font's kerning, so 100 % stays as drawn.
  - Past 130 % (`DpScript.large`), things side by side stack full width: the sentence ratings, the step quiz's tiles, the step header's code and line, the exam intro's columns, the model manager's storage and download lines, and a speaking answer's two buttons.
  - A fixed size around text grows with it, by the factor its text takes: `DpScript.grow(context, n, role:)`. Never by `textScaler.scale(n)`: Android 14+ scales text nonlinearly (at 200 % 14 sp is 28, but 96 is about 97), so a box's own size scaled as if it were a font barely grows. Only the text's part grows (the rating bar: 28 of room, two lines grown), and 100 % is unchanged. The examples are W2's columns, the rating bar, the grammar library's band and T2's snackbar lift. The exam timer and the umlaut keys take their content's height, with a minimum.
  - A number or a segment's label in a fixed cell shrinks to fit (`FittedBox`): Me's counts, the iOS segmented control's labels.
  - A chip's label wraps inside the chip, at most 80 % of the screen wide.
  - A `WidgetSpan`'s child is already scaled with its sentence; scaling it again (the cloze gap) doubles it.
  - Every golden case is audited at 150 and 200 % (`testing.md`), and Today, T2's front, Settings and the exam runner have a 200 % golden.
- An artboard height is a minimum, never a fixed height, wherever text sits inside it. Chips, word rows and chip rows grow at large text; lists use a `prototypeItem`, not a fixed `itemExtent`. Android's tab bar scrolls past 130 %. The keyboard covers the tab bar rather than lifting it, so a screen being typed in (R1, R2) keeps the room for its fields; the tabs return with the keyboard's going (#390). A pushed tab page whose header bleeds to the top (R2) keeps its colour behind the status bar when scrolled, as the tab roots do (#317). The ring's count and caption scale down inside its inner circle (#314). App bars and the screens' own back rows (L2, L4, W1) take 56 / 44 dp as a minimum, and so does the back button, which grows with its iOS label's line at 200 % (48 dp in English, 52 in Bangla) (#280, #404). `expectNothingClipped` (`test/core/text_clipping.dart`) catches text cut to a fixed box, which raises no exception.
- Targets ≥ 48 dp / 44 pt (#478). A control drawn smaller keeps its drawn size and takes `AdaptiveTapTarget`, which grows its hit area and its screen-reader node to 48 dp (44 pt under iOS chrome) without growing its layout. It is the control's own semantics node, so the control's own `Semantics` isn't a container. `goldenTest` checks every case.
  - **Where it's used:** only where the gap to a pressable neighbour is at least the growth. A grown target claims the gap, so beside a closer neighbour it would take that neighbour's taps. Hence Me's twelve step badges (23.5 dp, 4 dp gaps) keep their drawn boxes: each is its own node marked `dense:` (a semantics identifier), which the check skips. They meet WCAG 2.2's 24 dp with spacing (2.5.8).
  - **The hit area grows only inside the parent's box.** A chip in a one-row `Wrap` (32 dp tall) is 48 dp to a screen reader, but 32 dp to a finger above or below the row. ponytail: a parent-side hit area on chip rows is the upgrade.
  - **Two exceptions:**
    - iOS's sliding segmented control draws its segments 28 pt, as UIKit's control is short of 44 too. Growing it is an owner question (#492).
    - A text field's node is its field, so a field drawn smaller takes the target as well (R1's), and iOS's typed confirm is 44 pt tall.
- Every swipe has a button equivalent (T2's swipe-to-rate keeps its rating bar; T5's sentences move on by rating, and the dots are an adjustable control, so a screen reader or a switch pages either way, #164); the timers (the exam's, and L8's 15 s) can be paused or disabled.
- Every audio item has its text on screen; listening questions can be disabled in Settings.
- Focus order follows visual order; after rating, focus moves to the next card: its headword takes the focus as it appears, so a screen reader follows (#162).
- OS "reduce motion" → cross-fades, no shake, no confetti, no aurora drift. Read live (`MediaQuery.disableAnimationsOf`, each place its own `still`): pushed pages cross-fade (`StillPageTransitions` in the theme, and S2's pages), a tablet pane fades in, a Material sheet appears at once, a tab indicator moves without sliding, scroll-to-top jumps, a swiped card is back at once, and nothing animates its size (#164). iOS's Reduce Motion sets `reduceMotion`, not `disableAnimations`, so the app root folds the one into the other (`stillOnReduceMotion`). Under it a page's own transition is still built at rest inside the fade, so the iOS edge swipe and predictive back keep working. ponytail: three things still move under it, as they take no animation style: the iOS sheet (`showCupertinoModalPopup`), the iOS dialog's scale-in and the segmented control's thumb spring. OS "reduce transparency" → glass renders opaque, the iOS tab bar included (it blurs a see-through colour itself).

## Localisation

- UI languages: English and Bangla (ARB). German UI is a possible later immersion mode.
- The meaning language (EN / বাংলা / both) is separate from the UI language.
- The Today date is always German on purpose. Every number in Bangla UI text is in Bangla digits (owner, #425), and Bangla numerals never go inside German content. A step's code (A1.1) and a product's version (Hy-MT 1.5) are names, and keep theirs.

## Offline

Everything except web-search links and model downloads works in airplane mode. There is no "no connection" screen for core features.

## Performance budgets

| Target | Budget |
| --- | --- |
| Cold start to Today | < 1.5 s on a mid-range 2022 Android phone |
| Warm start | < 500 ms |
| Card transition after rating | < 16 ms/frame; DB write off the UI isolate |
| Glass list scroll | 60 fps with one `BackdropFilter` per list panel |
| Search | < 50 ms per keystroke after 120 ms debounce |
| App size | Play's one-CPU-type download, ONNX Runtime and llama.cpp included, at most 3 % over its baseline, measured by its stand-in, the arm64-v8a split APK (159.5 MB on 2026-09-26), until `bundletool get-size`; models downloaded separately |
| Supertonic first audio | < 300 ms for one word |
| Memory with Supertonic | No budget yet (the owner's call). Measured: ~520 MB PSS, 435 MB of it native heap, with its sessions open from the app's start (#460), on the emulator; with the phone's voice they never open |

How it is measured (#167): `python tools/perf.py all` on the developers' emulator (emulator-5558), with the milestone's full suite and before a release, not per PR. Each number is compared with its baseline in `tools/perf_baseline.json` and fails when it grows past its margin: size 3 %, search 25 %, frames and start 50 %: the emulator shares its host with the other emulators and the builds, and their load moves these numbers by a quarter from one run to the next, and by more from one day to another. Measure with the host as quiet as it can be, and read the emulator as catching gross regressions only. The 99th percentiles, the missed-frame counts and search's cold first run are shown, not judged: a handful of frames is the host's hiccup, not the app's. `--update-baseline` records today's numbers. Every step holds the emulator's lock (`team.py device`), the APK builds included, and the app is uninstalled at the end, so the next check finds no profile build, glass theme or studied day. The emulator is not a mid-range phone: it tracks regressions, and the absolute budgets are reported, not enforced, except search's, which fails when it is over 50 ms and over its baseline too. The owner checks cold and warm start on a real phone before each release.

- Start: `am start -W`'s `TotalTime` for the release x86_64 APK, the median of five, always from the same state: a fresh install, S2 walked with its defaults (A1.1, the default theme), on Today with day 1 unstudied. Cold runs must report a COLD launch; warm is HOME, once the app has stopped, then the launcher's intent again, and must report HOT. Anything else stops the run rather than reading as a regression. A cold start's `TotalTime` ends at Flutter's first frame, which is S1. Bootstrap's wait for Today comes after it, which debug and profile builds log as `bootstrap: N ms`.
- Frames: `integration_test/perf_test.dart` under `flutter drive --profile`, five cards rated in T2 and L2's word list flung under glass, with only the app asking for frames; average, 90th and 99th percentile build and raster times. Blur is held on (the frame watchdog stopped); a run where glass did not blur stops rather than be compared or recorded.
- Search: `SearchRepository.search` over the real content.db, timed at each keystroke of a few words (letters, prefixes, an umlaut, a phrase, English, Bangla), the whole list three times over; each keystroke's median, then their median and the slowest.
- Size: the arm64-v8a APK of `flutter build apk --release --split-per-abi`, standing in for the one-ABI download Play serves from the bundle, which is compressed and so smaller: the APK stores its native libraries uncompressed.
- Supertonic's first audio is measured by #430's work, not here.

Glass budget: max three blur layers on screen (header, one panel, tab bar); sheets blur over the scrim, not over other glass.

## Error and edge states

| Situation | Behaviour |
| --- | --- |
| Supertonic missing/fails | Phone voice plays; one-time toast with a Settings link |
| No German system voice | Every speaker and play button shows a slashed icon (#452); tap explains how to install one |
| Model download interrupted | "Paused — resumes on Wi-Fi" with Retry |
| Low storage | Download disabled with the exact shortfall |
| Content update | Silent; progress keyed by uid; removed words hidden, never deleted |
| Date/time-zone change | Local device date; never duplicates or drops a day |
| DB write error | Retry + Export; last saved card is never lost |
| Course finished | Today switches to revision-only with a completion card |
