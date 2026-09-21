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

**Functional requirements**
- FR-M3-01 The retention subtitle estimates reviews/day = Σ over learned words of 1 ÷ intervalDays(stability) at the chosen retention (sampled, cached).
- FR-M3-02 Theme changes apply immediately app-wide (`themeProvider`).
- FR-M3-03 Turning translation on without a model opens M4 and leaves the switch off until the model is ready.

**Tests.** each row writes its key; FR-M3-01 estimate; goldens top/bottom × 3 themes.
