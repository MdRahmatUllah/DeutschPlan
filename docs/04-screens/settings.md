# M3 · Settings

**Prototype.** `Settings` (top), `SettingsBottom` (scrolled), `ResetDialog`.

**Reached from.** M1, gear on T1. **Leads to.** M5 (Study days & reminder), M4 (Voice engine / On-device translation), M6 (Export / import), M7 (Reset), S2 (Restart setup).

Grouped list (Material headers / Cupertino inset groups). Changes save instantly; rows whose effect starts tomorrow say "Applies from tomorrow".

| Group | Row | Control | Setting |
| --- | --- | --- | --- |
| Daily plan | New words per day | stepper 1–50 | `daily_new` |
| | Revisions per day | stepper 0–100 | `revise_count` |
| | Practice sentences per day | stepper 0–20 | `sentence_count` |
| | Study days & reminder | → M5, subtitle "Mon–Sat · 19:30 · only when something is due" | |
| | Continue into the next step automatically | switch | `auto_advance` |
| | Pause new words when backlog is large | switch | `pause_new_when_backlog` |
| Revision | Target retention | slider 80–97 %, subtitle "≈ 11 reviews/day at your pace" | `desired_retention` |
| | Mark Done after N days remembered | stepper 3–60 | `done_stability_days` |
| | Swipe to rate | switch, "Left = Again, right = Good" | `swipe_to_rate` |
| Display | Meaning language | EN / বাংলা / Both | `meaning_language` |
| | App language | EN / বাংলা | `ui_language` |
| | Theme | System / Light / Dark / Glass | `theme_mode` |
| | Show Bangla pronunciation | switch | `show_pron_bn` |
| Audio | Voice engine | Supertonic · Anna / Phone voice → M4 | `tts_engine`, `tts_voice` |
| | Speech speed | slider, "1.0× · long-press any speaker for 0.75×" | `tts_speed` |
| | Auto-play headword / first example | switches | `autoplay_*` |
| | Listening questions | switch (accessibility) | `listening_questions` |
| Exams | Unlock mock exams at | stepper 50–100 % | `exam_unlock_percent` |
| | Pass mark | stepper 50–90 % | `exam_pass_percent` |
| | Timer on by default | switch | `exam_timer_default` |
| Translation | On-device translation | switch, subtitle status ("Hy-MT 1.5 · downloading 42%") → M4 when not downloaded | `mt_enabled` |
| Data | Export / import | → M6 | |
| | Reset | → M7, "One step, or everything" | |
| | Restart setup | → S2 (restart mode) | |

Details M3 settles (#146):
- The rows are the table's, in its order. The artboards leave some out (practice sentences, the backlog pause, Mark Done, app language, Bangla pronunciation, listening questions); each sits where the table puts it, drawn as its neighbours are.
- "Applies from tomorrow" is on *New words per day* and *Revisions per day*, the two BR-PLAN-08 names that M3 shows (the study days are M5's). *New words per day* also moves the open enrollment's `daily_new`, which is the pace the plan engine reads, as restart setup does; today's plan is left as it is.
- *Unlock mock exams at* and *Pass mark* show the value and a chevron, as the artboards draw them, and open a choice in steps of five across the ranges above. *Meaning language*, *App language* and *Theme* open the same kind of choice. The two languages are set apart here; S2's one choice sets both.
- *Speech speed* runs 0.5–1.5× in quarters, with the artboard's 1.0× at the middle: the grid the study menu's 0.75 / 1 / 1.25 are on, so both read a stored speed the same.
- *Study days & reminder* reads "Mon–Sat · 19:30 · only when something is due": a run of three or more days as a range (across the week's end too, "Fri–Mon"), otherwise the days listed ("Mon, Wed, Fri"), "Every day" for all seven; then the time in the phone's format, or "no reminder".
- *Voice engine* reads "Supertonic · Anna" or "Phone voice". *On-device translation* reads the model's state: "Hy-MT 1.5 · downloading 42%", "· ready", "· not downloaded", and so on.
- FR-M3-01's sample is every n-th of at most 1,000 learned words (rated, not suspended), scaled back up. The stabilities are read once per visit; the slider re-sums them.
- FR-M3-03: the model is there when it is `ready`, or `updateAvailable` (the old one is whole). A download in progress is not, so the switch stays off and M4 opens.
- M4 and M6 are pushed over M3 (navigation.md), so back returns to Settings. A choice's list scrolls when it outgrows the sheet (a phone held sideways, 200 % text).
- *Reset* opens M7 once #150 builds it; until then the row is there and does nothing.
- FR-M3-02: *Glass* gives the app `AppTheme.glass`, its light and smoked dark variants picked by the phone's light/dark, as theming.md says. Before #146 the root drew paper whatever was chosen.
- Android: a Cobalt header over flat rows (on the aurora under glass). iOS: an upper-case header over an inset panel, and the stepper is the number beside UIStepper's − | + pill (as OnboardingPace-ios draws it too). Every row is 52 dp.

**Functional requirements**
- FR-M3-01 The retention subtitle estimates reviews/day = Σ over learned words of 1 ÷ intervalDays(stability) at the chosen retention (sampled, cached).
- FR-M3-02 Theme changes apply immediately app-wide (`themeProvider`).
- FR-M3-03 Turning translation on without a model opens M4 and leaves the switch off until the model is ready.

**Tests.** each row writes its key; FR-M3-01 estimate; goldens top/bottom × 3 themes.
