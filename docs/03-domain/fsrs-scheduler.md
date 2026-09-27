# FSRS-4.5 scheduler

`domain/fsrs.dart`. Day-granular, deterministic, no dependencies.

- Default weights (17 values) from the published FSRS-4.5 set; `desired_retention` from settings.
- `retrievability(elapsedDays, stability) = (1 + 19/81 · t/S)^(-0.5)`.
- `elapsedDays` is the number of **local calendar days** between the last review and this one (`elapsedDays()` in `fsrs.dart`, #327), never negative. A card rated in the evening and reviewed next morning has 1, however few hours passed. It is counted on calendar dates, so a daylight-saving change doesn't give 0 or 2. `review_log.elapsed_days`, L6's retrievability order and the quiz builder's ranking use the same count. `review_log` rows written before #327 keep 24-hour periods, which matters only to a future weight optimisation over the log.
- `intervalDays(S) = S / (19/81) · (R^(-2) − 1)`, clamped 1…36500.
- First review: `S = w[rating-1]`, `D = clamp(w4 − (rating−3)·w5, 1, 10)`; Again → 1 day.
- Later reviews: recall formula with hard/easy multipliers `w15`, `w16`; lapse formula on Again; difficulty drifts with mean reversion (`w7`).
- Hard < Good < Easy (#616), as py-fsrs orders them: Good's interval is at least Hard's + 1 and Easy's at least Good's + 1, up to 36500. On a same-day re-review recall is 1 and the stability grows by nothing whatever the rating, so without this all three would schedule the same. Only the intervals move; each rating keeps its own stability. The reference values below are unchanged.
- Returns `CardState(stability, difficulty, reps, lapses, state, lastReview, due, scheduledDays)`.

Rating bar preview: the four intervals shown under Again/Hard/Good/Easy are `Fsrs.review(state, r, now).scheduledDays` for r = 1..4, computed on reveal.

Reference values (tests): first review intervals at 90 % retention = 1 / 1 / 4 / 14 days; a chain of Good reviews taken on their due day grows 4 → 15 → 50 → 150 → 409 (the owner's decision on #239: the chain this doc used to give, 4 → 16 → 53 → 157 → 420, came from no formulation of these weights, while the three other values pin them); `intervalDays(10) == 10`; at 80 % retention `intervalDays(10) == 24`.

Grammar topics use the same class on `grammar_state`.

Difficulty's mean reversion (#687 AN-5, the lead's decision): `D' = w7 · D0(Easy) + (1 − w7) · (D − w6 · (rating − 3))`, clamped 1…10, with `D0(Easy) = w4 − w5`. That target is FSRS-5's; canonical FSRS-4.5 reverts towards `w4`, a Good first review's difficulty, and would give the Good chain 4 → 15 → 49 → 146 → 393. The app keeps its target, and with it the chain above, so no learner's schedule moves. Switching to FSRS-4.5's target is a possible later change, best made with the on-device weight fitting below, and would re-pin the chain.

A card with no stability to grow (0, negative, NaN or infinite) is scheduled as a first review, whatever its `fsrs_state` (#687 AN-6, #863): an infinite one would otherwise be 36500 days out whatever the rating, Again included. No review leaves one; an imported row can. `intervalDays` of a NaN stability is 1 day and of an infinite one 36500, never a throw.

Future: on-device optimisation of weights from `review_log` once ≥ 1,000 reviews exist (not in v1).
