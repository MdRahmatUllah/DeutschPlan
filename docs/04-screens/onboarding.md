# S2 · Onboarding (five pages)

**Purpose.** Set the course up in about 60 seconds with safe defaults.

**Prototype.** `OnboardingWelcome`, `Onboarding` (meaning language), `OnboardingStart`, `OnboardingPace`, `OnboardingVoice`.

**Reached from.** S1 on first run; M3 → *Restart setup* (keeps progress; only plan settings change). **Leads to.** S3 from page 3; T1 on finish, or after *Restore a backup* on page 1.

**Layout (shared).** Coloured header block per page (Lagoon, Sun, Raspberry, Cobalt, Emerald) with the headline; "Step n of 5" dots (drawn only: the header already reads the step, so a screen reader hears it once, #740); one control group; primary *Continue* pinned bottom; *Back* text button from page 2; *Skip* top-right from page 3.

| Page | Content | Setting written |
| --- | --- | --- |
| 1 Welcome | The app language first (#1078): a caption *App language* over one chip per language, each named in itself (English · বাংলা · Polski · Русский, #1079), the current one ticked; a tap switches the whole app at once, this page included. Then three points: the whole course offline (the course, not the sound, which needs the phone's German voice or Supertonic: #1365) · exam-structured 12 steps · progress stays on the phone. Button *Let's start*; under it the link *Restore a backup* (#822, below) | `ui_language` (a restore: the file's) |
| 2 Meaning language | A card for each language the course ships (`course_languages`, #1081), named in itself (English, বাংলা, Русский), with the sample `die Wohnung → …` in it: the picked card is the first meaning. Under the cards, *Also show*: chips for a second language (None, or any other the course ships). Picking the second as the first swaps the two. It opens on the app language page 1 set (the owner, #1156): Русский alone for a Russian app and Polski alone for a Polish one, where the course ships it; English alone for an English app (and for a Russian or Polish one on a course without that language; the owner, #1363: an English speaker who keeps the defaults never meets Bangla, and a Bangla speaker taps বাংলা here); বাংলা + English for a Bangla one. *Let's start* writes that as page 2 opens, over nothing or over its own last pick only: going back to change the app language changes it, but a card or chip the learner tapped, or a backup page 1 restored, stays. Note "You can change it later in Settings." The meaning languages alone: page 1 set the app's, and Polish screens with English meanings stay Polish (#1078). The Bangla pronunciation follows: off with no Bangla chosen, on with Bangla first or second (#527) | `meaning_primary`, `meaning_secondary`, `show_pron_bn` |
| 3 Starting point | 12 step chips in level rows with word counts (A1.1 pre-selected); link *Not sure? Take a 3-minute check* → S3 | chosen step |
| 4 Daily pace | New words slider 3–30 (in restart setup Settings' 1–50, where the learner's pace may already be: the owner, 2026-09-28, #1011 ME-4) with live estimate "A1.1 takes about 91 days at 7 words a day" (637 words; the artboard's 69 counted 480); presets Relaxed 5 · Steady 7 · Intensive 15; revisions stepper (10) with note "Due cards beyond this wait for tomorrow"; weekday chips | `daily_new`, `revise_count`, `study_days_mask` |
| 5 Reminder & voice | Reminder switch (off) + time 19:30, note about permission; *Hear it: „Guten Tag!"* (system voice); Supertonic card (its size from the model manifest, about 400 MB, #245; Wi-Fi only, the default voice style F1) with *Download now* / *Later*; button *Start learning* | `reminder_*`, starts download |

**Functional requirements**
- FR-S2-01 *Skip* MUST finish with what the learner has chosen (a placed step, a pace, a reminder they set) and the defaults for what they never touched, on every page it appears (the owner, 2026-09-28, #1011 ME-11).
- FR-S2-02 Values MUST persist when navigating back. While setup finishes, nothing leaves the page: *Back*, *Skip*, the system back and iOS's swipe all wait (#692 ME-5).
- FR-S2-03 Finishing MUST call `PlanEngine.enroll(step, dailyNew)` and open Today with the first day planned, even on a weekday the learner has just switched off (BR-PLAN-01, #606) and a one-time coach mark on the primary button (gone once the button or a session is used, and never over a finished day: `today.md`, #396).
- FR-S2-04 The estimate on page 4 MUST use the selected step's word count ÷ daily_new × (7 ÷ study days per week).
- FR-S2-05 Reminder permission MUST be requested only when the switch is turned on. The one other asker is a model download the learner starts (*Download now* here, M4's *Download* / *Retry* / *Update*): it asks on Android 13+ and iOS, so the download can show its progress, with the line "It asks to show the download's progress in a notification" under the button; a refusal still downloads, without a notification (#501, the owner's decision).
- FR-S2-06 *Download now* MUST start the Supertonic download in the background and continue onboarding. A download that won't fit is refused before the phone is asked for notifications, so there is no permission prompt for a download that never starts (#704).

**Page 5's Supertonic card (#428)** shows the voice as it stands on the phone, from `ModelRepository` and `ModelDownloads.watch` (`supertonicOnPhoneProvider`), and follows it while the page is open:
- **Installed and verified** (an update waiting included): *Ready · downloaded and checked*, and no *Download now* or *Later*. The voice is never fetched again from here, and *Download now* waits disabled until the phone has answered (or failed to: then `start`'s own check stands).
- **In flight:** *Downloading · n% · keep going*; *Waiting for Wi-Fi · keep going* when *Wi-Fi only* is on and the phone is off Wi-Fi; *Paused at n%* when paused in M4. Checking the files reads as *Downloading · 100%*.
- **Failed** (a file, or a checksum): *Couldn't download · try again* with *Retry*, which is `ModelDownloads.retry` (what arrived stays). A retry refused for space (`NotEnoughSpace`) leaves *Retry* and says *Needs N MB more space*.
- **Nothing yet:** *Download now* / *Later*. When the phone lacks the voice's bytes plus the 100 MB margin (`ModelDownloads.shortfallFor`), *Download now* is disabled and greyed, and the card says *Needs N MB more space* (rounded up). A start refused for space after the page looked (`NotEnoughSpace`) checks again and says the same.
- The card's line says the voice comes over Wi-Fi: "About 400 MB, over Wi-Fi, downloaded once."

**Restore a backup (#822, the owner's decision).** Page 1's link, for a learner moving phones, before setup writes a setting of its own: the system file picker, then the file becomes this phone's data, as M6's *Replace* (`export-import.md`, FR-M6-04) in one transaction, with no confirm (there is nothing on the phone yet to lose). A file with a step opens Today and skips the rest of setup; a file with none carries on to page 2. A file that isn't a Sogda export, or is from a newer Sogda, writes nothing and says so over *Let's start* (M6's words); so does an import that fails. Backing out of the picker does nothing. Restart setup never shows it: there it would replace the learner's progress.

**Business rules.** BR-COURSE-04, BR-PLAN-08.

**First run (#1078).** Before page 1 draws, the app language is the phone's when Sogda speaks it (English, বাংলা, Polski, Русский; `bootstrap` writes `ui_language` once, if it has no value), and English otherwise. A phone set to Polish opens setup in Polish; the learner's choice after is never overridden.

**States.** Restart-setup mode hides page 1 and pre-fills current values; page 5's card reads the voice's real state, as above.

**Motion.** Horizontal page slide; system back / edge swipe = previous page.

**Platform.** Time picker: Material dialog / Cupertino wheel. Weekday chips: FilterChip / custom toggle pills.

**Data.** `OnboardingNotifier` holds draft values; commits in one transaction on finish.

**Tests.** FR-S2-01 skip path; FR-S2-04 estimate maths; golden per page × 3 themes.
