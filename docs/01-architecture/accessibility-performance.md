# Accessibility, localisation, offline and performance

## Accessibility (WCAG 2.2 AA target)

- Contrast: text 4.5:1, large text and icons 3:1 in all three modes; glass text is checked against the brightest blob it can overlay.
- Screen readers: every control labelled; the headword is announced with article and gender ("die Wohnung, feminine"); German text tagged `de-DE`, Bangla `bn-BD` via `Semantics(locale:)` so TalkBack/VoiceOver switch voices.
- Never colour alone: articles printed, statuses labelled, verdicts have icons and words.
- Text scaling to 200 %; long compounds soft-hyphenate.
- Targets ≥ 48 dp / 44 pt; every swipe has a button equivalent; the only timer (exams) can be paused or disabled.
- Every audio item has its text on screen; listening questions can be disabled in Settings.
- Focus order follows visual order; after rating, focus moves to the next card.
- OS "reduce motion" → cross-fades, no shake, no confetti, no aurora drift. OS "reduce transparency" → glass renders opaque.

## Localisation

- UI languages: English and Bangla (ARB). German UI is a possible later immersion mode.
- The meaning language (EN / বাংলা / both) is separate from the UI language.
- The Today date is always German on purpose. Bangla numerals only in Bangla UI text, never inside German content.

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
| No German system voice | Speaker shows a slashed icon; tap explains how to install one |
| Model download interrupted | "Paused — resumes on Wi-Fi" with Retry |
| Low storage | Download disabled with the exact shortfall |
| Content update | Silent; progress keyed by uid; removed words hidden, never deleted |
| Date/time-zone change | Local device date; never duplicates or drops a day |
| DB write error | Retry + Export; last saved card is never lost |
| Course finished | Today switches to revision-only with a completion card |
