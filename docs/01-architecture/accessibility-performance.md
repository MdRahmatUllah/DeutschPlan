# Accessibility, localisation, offline and performance

## Accessibility (WCAG 2.2 AA target)

- Contrast: text 4.5:1, large text and icons 3:1 in all three modes; glass text is checked against the brightest blob it can overlay. Progress graphics 3:1 too (1.4.11): the ring's track, bar tracks and the heat-map's empty days take `surface.track` (#437). `contrast_test.dart` measures both over the tokens.
- Screen readers: every control labelled; the headword is announced with article and gender ("die Wohnung, feminine"); German text tagged `de-DE`, Bangla `bn-BD` via `Semantics(locale:)` so TalkBack/VoiceOver switch voices.
- Every control a screen reader hears as a button can be pressed by one. A `Semantics(button: …)` that hides its child's semantics, through `ExcludeSemantics` or `excludeSemantics: true`, also hides the tap its `GestureDetector` would give. So it carries `onTap:` (and `onLongPress:`) itself (#312). `architecture_test.dart` enforces this.
- Never colour alone: articles printed, statuses labelled, verdicts have icons and words.
- Text scaling to 200 % on every screen, and no word broken mid-syllable to fit it (#165):
  - Above 100 % a long German compound, or a Bangla word, in a narrow place may break at a syllable (`DpScript.allowBreaks`, soft hyphens). Only above 100 %: a soft hyphen splits the font's kerning, so 100 % stays as drawn.
  - Past 130 % (`DpScript.large`), things side by side stack full width: the sentence ratings, the step quiz's tiles, the step header's code and line, the exam intro's columns, the model manager's storage and download lines, and a speaking answer's two buttons.
  - A fixed size around text scales with it (`MediaQuery.textScalerOf(context).scale(n)`), so 100 % is unchanged: the exam timer, the umlaut keys, the rating bar.
  - A number or a segment's label in a fixed cell shrinks to fit (`FittedBox`): Me's counts, the iOS segmented control's labels.
  - A chip's label wraps inside the chip, at most 80 % of the screen wide.
  - A `WidgetSpan`'s child is already scaled with its sentence; scaling it again (the cloze gap) doubles it.
  - Every golden case is audited at 150 and 200 % (`testing.md`), and Today, T2's front, Settings and the exam runner have a 200 % golden.
- An artboard height is a minimum, never a fixed height, wherever text sits inside it. Chips, word rows and chip rows grow at large text; lists use a `prototypeItem`, not a fixed `itemExtent`. Android's tab bar scrolls past 130 %. The keyboard covers the tab bar rather than lifting it, so a screen being typed in (R1, R2) keeps the room for its fields; the tabs return with the keyboard's going (#390). A pushed tab page whose header bleeds to the top (R2) keeps its colour behind the status bar when scrolled, as the tab roots do (#317). The ring's count and caption scale down inside its inner circle (#314). App bars and the screens' own back rows (L2, L4, W1) take 56 / 44 dp as a minimum, and so does the back button, which grows with its iOS label's line at 200 % (48 dp in English, 52 in Bangla) (#280, #404). `expectNothingClipped` (`test/core/text_clipping.dart`) catches text cut to a fixed box, which raises no exception.
- Targets ≥ 48 dp / 44 pt; every swipe has a button equivalent (T2's swipe-to-rate keeps its rating bar; T5's sentences move on by rating, and the dots are an adjustable control, so a screen reader or a switch pages either way, #164); the timers (the exam's, and L8's 15 s) can be paused or disabled.
- Every audio item has its text on screen; listening questions can be disabled in Settings.
- Focus order follows visual order; after rating, focus moves to the next card.
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
| App size | ~20 MB + 5.5 MB content; models downloaded separately |
| Supertonic first audio | < 300 ms for one word |

Glass budget: max three blur layers on screen (header, one panel, tab bar); sheets blur over the scrim, not over other glass.

## Error and edge states

| Situation | Behaviour |
| --- | --- |
| Supertonic missing/fails | Phone voice plays; one-time toast with a Settings link |
| No German system voice | Every speaker shows a slashed icon, the small play buttons too (a word row's, the mini play of T2, W1, T3, the cloze, W4 and the exam review, and L4's) (#452); tap explains how to install one |
| Model download interrupted | "Paused — resumes on Wi-Fi" with Retry |
| Low storage | Download disabled with the exact shortfall |
| Content update | Silent; progress keyed by uid; removed words hidden, never deleted |
| Date/time-zone change | Local device date; never duplicates or drops a day |
| DB write error | Retry + Export; last saved card is never lost |
| Course finished | Today switches to revision-only with a completion card |
