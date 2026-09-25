# S2 · Onboarding (five pages)

**Purpose.** Set the course up in about 60 seconds with safe defaults.

**Prototype.** `OnboardingWelcome`, `Onboarding` (meaning language), `OnboardingStart`, `OnboardingPace`, `OnboardingVoice`.

**Reached from.** S1 on first run; M3 → *Restart setup* (keeps progress; only plan settings change). **Leads to.** S3 from page 3; T1 on finish.

**Layout (shared).** Coloured header block per page (Lagoon, Sun, Raspberry, Cobalt, Emerald) with the headline; "Step n of 5" dots; one control group; primary *Continue* pinned bottom; *Back* text button from page 2; *Skip* top-right from page 3.

| Page | Content | Setting written |
| --- | --- | --- |
| 1 Welcome | Three points: offline · exam-structured 12 steps · progress stays on the phone. Button *Let's start* | — |
| 2 Meaning language | Cards English / বাংলা / Both with sample `die Wohnung → …`; note "This also sets the app language" | `meaning_language`, `ui_language` |
| 3 Starting point | 12 step chips in level rows with word counts (A1.1 pre-selected); link *Not sure? Take a 3-minute check* → S3 | chosen step |
| 4 Daily pace | New words slider 3–30 with live estimate "A1.1 takes about 69 days at 7 words a day"; presets Relaxed 5 · Steady 7 · Intensive 15; revisions stepper (10) with note "Due cards beyond this wait for tomorrow"; weekday chips | `daily_new`, `revise_count`, `study_days_mask` |
| 5 Reminder & voice | Reminder switch (off) + time 19:30, note about permission; *Hear it: „Guten Tag!"* (system voice); Supertonic card (its size from the model manifest, about 400 MB, #245; Wi-Fi only, the default voice style F1) with *Download now* / *Later*; button *Start learning* | `reminder_*`, starts download |

**Functional requirements**
- FR-S2-01 *Skip* MUST apply defaults for all remaining pages and finish.
- FR-S2-02 Values MUST persist when navigating back.
- FR-S2-03 Finishing MUST call `PlanEngine.enroll(step, dailyNew)` and open Today with the first day planned and a one-time coach mark on the primary button.
- FR-S2-04 The estimate on page 4 MUST use the selected step's word count ÷ daily_new × (7 ÷ study days per week).
- FR-S2-05 Reminder permission MUST be requested only when the switch is turned on.
- FR-S2-06 *Download now* MUST start the Supertonic download in the background and continue onboarding.

**Page 5's Supertonic card (#428)** shows the voice as it stands on the phone, from `ModelRepository` and `ModelDownloads.watch` (`supertonicOnPhoneProvider`), and follows it while the page is open:
- **Installed and verified** (an update waiting included): *Ready · downloaded and checked*, and no *Download now* or *Later*. The voice is never fetched again from here, and *Download now* waits disabled until the phone has been asked.
- **In flight:** *Downloading · n% · keep going*; *Waiting for Wi-Fi · keep going* when *Wi-Fi only* is on and the phone is off Wi-Fi; *Paused at n%* when paused in M4. Checking the files reads as *Downloading · 100%*.
- **Failed** (a file, or a checksum): *Couldn't download · try again* with *Retry*, which is `ModelDownloads.retry` (what arrived stays).
- **Nothing yet:** *Download now* / *Later*. When the phone lacks the voice's bytes plus the 100 MB margin (`ModelDownloads.shortfallFor`), *Download now* is disabled and greyed, and the card says *Needs N MB more space* (rounded up). A start refused for space after the page looked (`NotEnoughSpace`) checks again and says the same.
- The card's line says the voice comes over Wi-Fi: "About 400 MB, over Wi-Fi, downloaded once."

**Business rules.** BR-COURSE-04, BR-PLAN-08.

**States.** Restart-setup mode hides page 1 and pre-fills current values; page 5's card reads the voice's real state, as above.

**Motion.** Horizontal page slide; system back / edge swipe = previous page.

**Platform.** Time picker: Material dialog / Cupertino wheel. Weekday chips: FilterChip / custom toggle pills.

**Data.** `OnboardingNotifier` holds draft values; commits in one transaction on finish.

**Tests.** FR-S2-01 skip path; FR-S2-04 estimate maths; golden per page × 3 themes.
