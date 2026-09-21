# M1 · Me

**Purpose.** Personal overview and the door to settings, models and data.

**Prototype.** `Me`.

**Reached from.** Me tab. **Leads to.** M2 (Words/Activity cards), T4 (schedule card when behind), L10 (exam badges), L7 (quick quiz), M3, M4, M9.

**Layout.** Cobalt header: name (tap to edit → `learner_name`), streak pill, "Learning since 19 Aug 2026 · 31 days studied". Words card: segmented bar + "1,248 Done · 312 Learning · 4,034 To do" + legend "Learning = seen, still being reviewed · Done = remembered for 7+ days · Suspended = paused by you". Activity card: 12-week heat-map. Schedule card: "2 days behind · 14 words in backlog · tap to catch up" (or "On schedule"). Mock exams card: "2 passed · A2.1 unlocks at 90%" + 12 step badges (Lime passed, Lagoon unlocked, Oat locked). List: Settings · Voice & translation · About & privacy.

**Functional requirements**
- FR-M1-01 Counts from `stepProgressProvider` aggregated; legend text uses `done_stability_days`.
- FR-M1-02 Heat-map: `daily_stats` per day, 5 shade steps (0 / 1–9 / 10–19 / 20–39 / ≥ 40 cards).
- FR-M1-03 Schedule card per `plan-engine.md` schedule check.
- FR-M1-04 Badge tap opens L10 for that step (cross-tab).

**Tests.** aggregation; heat-map bucketing.
