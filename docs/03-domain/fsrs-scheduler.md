# FSRS-4.5 scheduler

`domain/fsrs.dart`. Day-granular, deterministic, no dependencies.

- Default weights (17 values) from the published FSRS-4.5 set; `desired_retention` from settings.
- `retrievability(elapsedDays, stability) = (1 + 19/81 · t/S)^(-0.5)`.
- `elapsedDays` is the number of **local calendar days** between the last review and this one (`elapsedDays()` in `fsrs.dart`, #327), never negative. A card rated in the evening and reviewed next morning has 1, however few hours passed. It is counted on calendar dates, so a daylight-saving change doesn't give 0 or 2. `review_log.elapsed_days` and L6's retrievability order use the same count.
- `intervalDays(S) = S / (19/81) · (R^(-2) − 1)`, clamped 1…36500.
- First review: `S = w[rating-1]`, `D = clamp(w4 − (rating−3)·w5, 1, 10)`; Again → 1 day.
- Later reviews: recall formula with hard/easy multipliers `w15`, `w16`; lapse formula on Again; difficulty drifts with mean reversion (`w7`).
- Returns `CardState(stability, difficulty, reps, lapses, state, lastReview, due, scheduledDays)`.

Rating bar preview: the four intervals shown under Again/Hard/Good/Easy are `Fsrs.review(state, r, now).scheduledDays` for r = 1..4, computed on reveal.

Reference values (tests): first review intervals at 90 % retention = 1 / 1 / 4 / 14 days; a chain of Good reviews taken on their due day grows 4 → 16 → 53 → 157 → 420; `intervalDays(10) == 10`; at 80 % retention `intervalDays(10) == 24`.

Grammar topics use the same class on `grammar_state`.

Future: on-device optimisation of weights from `review_log` once ≥ 1,000 reviews exist (not in v1).
