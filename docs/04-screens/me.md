# M1 · Me

**Purpose.** Personal overview and the door to settings, models and data.

**Prototype.** `Me`.

**Reached from.** Me tab. **Leads to.** M2 (Words/Activity cards), T4 (schedule card when behind), L10 (exam badges), L7 (quick quiz), M3, M4, M9.

**Layout.** Cobalt header: name (tap to edit → `learner_name`), streak pill, "Learning since 19 Aug 2026 · 31 days studied". Words card: segmented bar + "1,248 Done · 312 Learning · 4,034 To do" + legend "Learning = seen, still being reviewed · Done = remembered for 7+ days · Suspended = paused by you". Activity card: 12-week heat-map. Schedule card: "2 days behind · 14 words in backlog · tap to catch up" (or "On schedule"). Mock exams card: "2 passed · A2.1 unlocks at 90%" + 12 step badges (Lime passed, Lagoon unlocked, Oat locked). List: Settings · Voice & translation · About & privacy.

**Functional requirements**
- FR-M1-01 Counts from `stepProgressProvider` aggregated; legend text uses `done_stability_days`.
- FR-M1-02 Heat-map: `daily_stats` per day, 5 shade steps (0 / 1–9 / 10–19 / 20–39 / ≥ 40 cards). A day's count is every item practised (`new_done + reviews_done + grammar_done + sentences_done`), the activity the streak counts, so a day inside the streak is never empty. Twelve columns, a week each, Monday to Sunday top to bottom, the last the current week; days still to come are drawn empty. Shades are Lagoon at 15 / 35 / 65 / 100 % (the artboard draws the top three); an empty day is `surface.track`, 3:1 on the card, where the artboard's Oat is 1.2:1 (#437). The header's "days studied" is every day with a non-zero count.
- FR-M1-03 Schedule card per `plan-engine.md` schedule check, measured through yesterday: today's new words are today's, not the backlog, so what is behind is exactly T4's backlog. The title is whole days (`behind / daily_new`, rounded), "Less than a day behind" under half a day, "On schedule" with no line and no tap when nothing is behind.
- FR-M1-04 Badge tap opens L10 for that step (cross-tab). Lime once a mock is passed, Lagoon once the exams are unlocked, Oat outlined in ink for the current step, faded Oat otherwise; every badge opens its hub. The card's line is "{n} passed", then " · {step} unlocks at {exam_unlock_percent}%" (or " · {step} unlocked") for a current step not yet passed.
- The name opens a sheet with a text field and *Save*; a blank name clears `learner_name`, and the header then offers "Add your name". T1's greeting follows the change.

**Tests.** aggregation; heat-map bucketing.
