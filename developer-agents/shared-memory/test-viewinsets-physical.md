---
name: test-viewinsets-physical
description: In widget tests tester.view.viewInsets (a simulated keyboard) is in PHYSICAL pixels; multiply by devicePixelRatio (3.0 by default)
metadata:
  type: feedback
---

`tester.view.viewInsets = FakeViewPadding(bottom: N)` takes physical pixels. The default test view is 800 × 600 logical at devicePixelRatio 3.0, so a 250 dp keyboard is `bottom: 250 * 3`. Reset with `addTearDown(tester.view.resetViewInsets)`.

**Why:** on #526 (#515) a cloze keyboard test "failed with the fix in": I had passed 250, an 83 dp keyboard, and the card only re-centred by half of it. Cost a debugging round.

**How to apply:** any keyboard-inset test (a focused field's `scrollPadding`, a pinned bar), write `logical * tester.view.devicePixelRatio`, or set `physicalSize` and multiply by the ratio you set. Focus the field first, then set the inset and `pumpAndSettle`, so `showCaretOnScreen` runs with the field's scrollPadding. Related: [[test-semantics-dispose-inline]].
