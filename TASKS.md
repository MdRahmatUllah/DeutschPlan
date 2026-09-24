# Tasks

The task file. Every open issue of the project, who has it, and what it waits
for; the shared locks; and, at the bottom, the handoffs — assignments, review
requests, reports and questions between agents.

**Edit it only with `python tools/team.py`** (run from your code worktree). The
tool makes every change a push that fails if someone else changed the board
first, and then retries on their version: that is what stops two agents
claiming the same issue. A hand edit skips that check.

- **Status**: `open` (free) · `assigned` (reserved for the owner by another
  agent) · `in-progress` · `review` (PR open) · `done` (merged, issue closed)
  · `needs-decision` (waits for the project owner — never guess these).
- **Ready** = `open` and every issue in *Blocked by* is `done` (an issue not
  on the board was closed before it was made). `team.py status` lists them.
- **Lane**: A agent-0 (lead): quiz & exam runner, release · B agent-1: voice
  seam, words, search, translation, polish · C agent-2: Me, settings, exam
  engine, platform, accessibility · X anyone (follow-ups, decisions, epics).
  Lanes are defaults, not fences: see PLAN.md.
- **Epics** (size `epic`) are blocked by their children; when they are all
  done, claim the epic, `gh issue close` it with a summary, and `done` it.

## Tasks

| Issue | Ms | Lane | Pri | Size | Title | Status | Owner | Blocked by | PR |
|---|---|---|---|---|---|---|---|---|---|
| #81 | M4 | A | P1 | M | quiz_builder.dart | done | agent-0 | #58 #74 #75 | #289 |
| #83 | M4 | C | P1 | L | exam_generator.dart — nine sections, three seeds, no repeats | done | agent-2 | #81 #82 | #296 |
| #84 | M4 | C | P1 | M | Exam grading including writing and speaking scoring | review | agent-2 | #61 #83 | #299 |
| #122 | M4 | A | P1 | M | L7 · Custom quiz sheet | done | agent-0 | #37 #81 #116 | #295 |
| #123 | M4 | A | P1 | M | L8 · Quiz runner shell, timer and per-item persistence | done | agent-0 | #61 #68 #122 | #297 |
| #124 | M4 | A | P1 | M | L8 · Item layouts and feedback | in-progress | agent-0 | #40 #75 #123 |  |
| #125 | M4 | A | P2 | S | L8 · Re-ask queue for wrong items | open |  | #124 |  |
| #126 | M4 | A | P1 | M | L9 · Quiz result | open |  | #125 |  |
| #127 | M4 | C | P1 | M | L10 · Mock exam hub (unlocked) | review | agent-2 | #83 #113 | #300 |
| #128 | M4 | C | P1 | S | L10 · Mock exam hub (locked) | open |  | #127 |  |
| #129 | M4 | C | P1 | S | L11 · Exam intro | open |  | #61 #127 |  |
| #130 | M4 | A | P1 | L | L12 · Exam runner shell, timer and resume | open |  | #69 #124 #129 |  |
| #131 | M4 | A | P2 | S | L12 · Question navigator sheet | open |  | #130 |  |
| #132 | M4 | A | P2 | S | L12 · Leave dialog | open |  | #130 |  |
| #133 | M4 | A | P1 | M | L12 · Writing section | open |  | #84 #130 |  |
| #134 | M4 | A | P1 | M | L12 · Speaking section and recorder | open |  | #64 #84 #130 |  |
| #135 | M4 | A | P1 | M | L13 · Exam results | open |  | #84 #133 #134 |  |
| #136 | M4 | A | P2 | M | L14 · Exam review | open |  | #135 |  |
| #6 | M4 | X | P0 | epic | Epic · Domain engines | open |  | #81 #83 #84 |  |
| #10 | M4 | X | P1 | epic | Epic · Quizzes | open |  | #122 #123 #124 #125 #126 |  |
| #11 | M4 | X | P1 | epic | Epic · Mock exams | open |  | #127 #128 #129 #130 #131 #132 #133 #134 #135 #136 |  |
| #137 | M5 | B | P1 | L | R1 · Search results | in-progress | agent-1 | #39 #63 #67 |  |
| #138 | M5 | B | P2 | S | R1 · Search idle: recents and My words | open |  | #137 |  |
| #139 | M5 | B | P2 | S | R1 · No results and the web hand-off | open |  | #137 |  |
| #140 | M5 | B | P1 | L | W1 · Word detail | review | agent-1 | #39 #58 #70 | #298 |
| #141 | M5 | B | P1 | M | W1 · Word actions | open |  | #78 #140 |  |
| #142 | M5 | B | P3 | M | W2 · Compare words | open |  | #81 #140 |  |
| #143 | M5 | B | P2 | M | R2 · Add and edit my word | open |  | #63 #138 |  |
| #144 | M5 | C | P1 | M | M1 · Me | done | agent-2 | #58 #72 #79 | #293 |
| #145 | M5 | C | P2 | M | M2 · Progress detail | open |  | #144 |  |
| #146 | M5 | C | P1 | L | M3 · Settings | open |  | #37 #62 #144 |  |
| #147 | M5 | C | P2 | M | M5 · Study days and reminder | open |  | #146 #158 |  |
| #148 | M5 | C | P2 | M | M6 · Export and import | open |  | #65 #146 |  |
| #149 | M5 | C | P2 | M | M7 · Reset | open |  | #148 |  |
| #150 | M5 | C | P2 | S | M9 · About & privacy and M8 · Licences | open |  | #51 #146 |  |
| #12 | M5 | X | P1 | epic | Epic · Search and words | open |  | #137 #138 #139 #140 #141 #142 #143 |  |
| #13 | M5 | X | P1 | epic | Epic · Me, progress, settings and data | open |  | #144 #145 #146 #147 #148 #149 #150 |  |
| #151 | M6 | B | P1 | S | TtsEngine interface and SystemTts | done | agent-1 | #20 | #290 |
| #152 | M6 | B | P2 | L | SupertonicTts — Supertonic 3 through ONNX Runtime | open |  | #64 #151 #245 |  |
| #153 | M6 | B | P1 | M | TtsService — engine selection, fallback and autoplay | open |  | #152 |  |
| #154 | M6 | B | P3 | L | HyMtTranslator behind the licence build flag | open |  | #64 #151 #283 |  |
| #155 | M6 | B | P2 | L | M4 · Model manager | open |  | #146 #153 #156 |  |
| #156 | M6 | B | P2 | M | Download manager: resumable, Wi-Fi-only, checksum-verified | open |  | #64 |  |
| #157 | M6 | C | P2 | M | Notification service and the permission flow | open |  | #62 #70 |  |
| #158 | M6 | C | P2 | M | Background tasks: plan pre-generation, reminder composition, widget refresh | open |  | #76 #157 |  |
| #159 | M6 | C | P2 | S | Widget snapshot writer and word-of-the-day selection | open |  | #158 |  |
| #160 | M6 | C | P2 | M | X1 · Android home-screen widget (Glance) | open |  | #159 |  |
| #161 | M6 | C | P2 | M | X1 · iOS home-screen widget (WidgetKit) | open |  | #159 |  |
| #245 | M6 | X | - | - | Model manifest: Supertonic 3's files do not exist, and the real model is ~398 MB, not ~100 MB | needs-decision |  |  |  |
| #283 | M6 | X | - | - | Model manifest: the Hy-MT files 404, and no q2 build exists | needs-decision |  |  |  |
| #14 | M6 | X | P1 | epic | Epic · Voice, translation and model manager | open |  | #151 #152 #153 #154 #155 #156 #245 #283 |  |
| #15 | M6 | X | P1 | epic | Epic · Reminders, background work and home-screen widget | open |  | #157 #158 #159 #160 #161 |  |
| #162 | M7 | C | P1 | L | Semantics and screen-reader pass across every screen | open |  | #111 #136 #147 #150 #155 |  |
| #163 | M7 | B | P1 | M | Contrast audit across Light, Dark and Glass | open |  | #32 #162 |  |
| #164 | M7 | B | P1 | M | Reduce motion and reduce transparency | open |  | #35 #111 |  |
| #165 | M7 | C | P1 | M | Text scaling to 200 % across every screen | open |  | #36 #162 |  |
| #166 | M7 | B | P1 | M | Localisation completeness: en and bn | open |  | #27 #36 |  |
| #167 | M7 | B | P1 | M | Performance budgets | open |  | #153 #164 |  |
| #168 | M7 | C | P1 | L | Complete the golden suite: every screen × three themes × two devices | open |  | #25 #165 |  |
| #169 | M7 | A | P1 | M | Integration smoke tests on emulator and simulator | open |  | #111 #130 |  |
| #170 | M7 | A | P1 | M | Android release pipeline | open |  | #152 #160 #167 |  |
| #171 | M7 | A | P1 | M | iOS release pipeline | open |  | #152 #161 #167 |  |
| #172 | M7 | C | P2 | S | Licence collection and model licence texts | open |  | #150 |  |
| #173 | M7 | B | P1 | S | Hy-MT region decision and ADR | open |  | #154 |  |
| #174 | M7 | B | P1 | M | Error and edge-state matrix | open |  | #153 #156 #167 |  |
| #175 | M7 | A | P2 | S | Store listing, changelog and release tagging | open |  | #168 #169 #170 #171 #172 #173 #174 |  |
| #280 | M7 | B | P1 | - | fix(adaptive): iOS bar titles at 17 pt, and a long title ends in an ellipsis | open |  |  |  |
| #281 | M7 | X | P2 | - | test(learn): L6 review follow-ups: tie-break, loading, suspended, ellipsis | open |  |  |  |
| #282 | M7 | X | P3 | - | fix(words): the glass word list is one frosted panel (L2, L6) | open |  |  |  |
| #284 | M7 | X | P2 | - | docs(dev-guide): reconcile the dev guide with how the app is built | open |  |  |  |
| #16 | M7 | X | P1 | epic | Epic · Accessibility, localisation and performance | open |  | #162 #163 #164 #165 #166 #167 #168 #169 |  |
| #17 | M7 | X | P1 | epic | Epic · Release readiness | open |  | #170 #171 #172 #173 #174 #175 |  |
| #239 | - | X | - | - | fsrs-scheduler.md's Good chain does not reproduce | needs-decision |  |  |  |
| #287 | M7 | X | P2 | - | content: 54 nouns keep their article inside german, not in article | open |  |  |  |
| #291 | M4 | A | P1 | - | perf(domain): quiz_builder ranks distractors before the synonym check | done | agent-0 |  | #292 |
| #294 | M7 | X | P3 | - | content: skill_prompts holds scraped worksheet cells, not prompts | open |  |  |  |

## Locks

One holder at a time; `team.py lock <resource> -m why` / `unlock <resource>`.

- `user-db-schema`: bumping `latestSchemaVersion` / a new `drift_schema_vN.json`.
- `adr-number`: writing the next row of `docs/05-dev-guide/decisions.md`.
- `pubspec`: adding or bumping a dependency (`pubspec.yaml`/`.lock`).
- `ci-config`: `.github/workflows/*`, `Makefile`, `tools/tests/test_ci.py`.
- `shared-look`: a change to `core/theme`, `core/components`, `core/adaptive`,
  `core/typography` or `golden_harness.dart` that re-renders OTHER screens'
  goldens (adding an optional parameter for your own screen does not need it).

The emulator lock is local, not here: `team.py device`.

| Resource | Owner | Since | Why |
|---|---|---|---|
| user-db-schema |  |  |  |
| adr-number |  |  |  |
| pubspec |  |  |  |
| ci-config |  |  |  |
| shared-look |  |  |  |

## Handoffs

Newest last. `team.py status` shows the ones for you; `team.py ack` marks them
read. Reports on finished work are written here by `team.py done`.

### H-1 · 2026-09-24 10:45 · agent-1 → all · heads-up

The board is open. Every open issue of M4–M7 is here, in four lanes (PLAN.md): A agent-1 quiz & exam runner (the critical path), B agent-2 search/words/polish, C agent-3 Me/settings/exam engine/accessibility, D agent-4 voice/platform/release.

Start a session: read CLAUDE.md, then `python tools/team.py agents`, `join` an idle identity, read your agents/<id>.md (your memory) and MEMORY.md, then `status` and claim the first ready issue in your lane. Log as you go; `done` reports to everyone.

Ready now: #81 (A), #140 #137 (B), #144 (C), #151 #156 #157 (D), and floaters #164 #166 #280 #281 #282 #284.

### H-2 · 2026-09-24 10:45 · agent-1 → owner · decision

Waiting on you — nothing downstream of these can finish without your call:
- #245 Supertonic: the real model is ~398 MB, not ~100 MB; which voice styles ship; still offered on S2; Wi-Fi rules. Blocks #152 → #153 → #155.
- #283 Hy-MT: both manifest URLs 404; which source/quant (a third-party 1.25-bit build exists, 462 MB); what "Better quality" is. Blocks #154.
- #239 FSRS: is fsrs-scheduler.md's Good chain right, or the code?
- Later: #173 Hy-MT region decision; #170/#171/#175 the real app id (still com.example.deutschplan), signing keys, store accounts, a macOS host for iOS; branch protection on main (admin).

### H-3 · 2026-09-24 11:27 · agent-0 → all · heads-up

The team is three agents: agent-0 (the lead: lane A, the critical path, plus release, reviews and assignments), agent-1 (lane B: the voice seam, words, search, translation, polish) and agent-2 (lane C: Me, settings, the exam engine, platform, accessibility). Lane D's voice issues moved to B and its platform issues to C; PLAN.md has the new lanes. Your first issues are assigned to you in the next handoffs. Review requests beat new work; `team.py msg agent-0` when your lane runs dry.

### H-4 · 2026-09-24 11:27 · agent-0 → agent-1 · assign · #151

Please start with #151: grow `TtsEngine` (name, isAvailable, speed, a state stream) and add a `tts` provider seam, so every new speaker — your W1 and R1, my quiz runner — codes against it instead of `systemTtsProvider`. It is small (S) and unblocks us both. PR, review request to agent-0, merge, then #140.

### H-5 · 2026-09-24 11:27 · agent-0 → agent-1 · assign · #140

Then #140 W1 word detail: `WordRoute.open` becomes a sheet on phones and a right pane on tablets; it is the single entry point used by backlog, category_words, step_words, sentences and study, and #136/#137/#143/#160 build on it. After it, continue lane B (PLAN.md).

### H-6 · 2026-09-24 11:27 · agent-0 → agent-2 · assign · #144

Please start with #144 M1 Me (ready now): replace the `MeRoute` placeholder; data from `stepProgressProvider`, `PlanEngine.streak`, daily_stats and `ExamRepository.watchStepPassed`. PR, review request to agent-0, merge.

### H-7 · 2026-09-24 11:27 · agent-0 → agent-2 · assign · #83

Then #83 exam generator — it is on the critical path (#127 → #129 → my #130). It is blocked by my #81 (quiz_builder), which I start now; `status` shows it ready once #81 is done. If #81 is not merged when #144 is, do #146 Settings first (it unblocks #147, #148, #150, #155) and come back to #83.

### H-8 · 2026-09-24 11:47 · agent-0 → all · note · #287

Added #287 (content: 54 nouns keep their article inside german, not in article) to lane X.

### H-9 · 2026-09-24 11:59 · agent-0 → all · heads-up

team.py status crashes (UnicodeEncodeError) on a Windows console when you have an unread handoff: the headers contain the arrow character. Until PR #288 merges, run it as: PYTHONIOENCODING=utf-8 python tools/team.py status. After it merges, rebase your branch or just use the variable.

### H-10 · 2026-09-24 12:11 · agent-0 → all · review-request · #81

PR #289 for #81 (quiz_builder.dart) is up. Review it on GitHub and answer with `team.py msg agent-0 --kind review`.

### H-11 · 2026-09-24 12:18 · agent-0 → all · report · #81

#81 (quiz_builder.dart) is merged as #289. quizBuilderProvider builds a Quiz from (direction, source, sourceRef, length, seed, today); QuizItem carries prompt/expected/options/form; distractors(), parseForms(), applies() are reusable (domain/quiz_builder.dart). QuizArgs has timer now. Now ready: #122.

### H-12 · 2026-09-24 12:18 · agent-0 → agent-2 · note · #83

#81 is merged (PR #289), so #83 is ready for you after #144. For the exam generator: QuizBuilder/quizBuilderProvider in domain/quiz_builder.dart gives you seeded word selection (pickWords), distractors(answer, pool, value, random) with the same-POS/same-step/no-synonym rules, parseForms() and applies(); DriftQuizStore.stepWords(step) is a step's whole pool. The four-tile QuizItem.options are ready for multiple-choice exam items.

### H-13 · 2026-09-24 12:27 · agent-1 → agent-0 · review-request · #151

PR #290 for #151 (TtsEngine interface and SystemTts) is up. Review it on GitHub and answer with `team.py msg agent-1 --kind review`.

### H-14 · 2026-09-24 12:28 · agent-1 → agent-0 · heads-up · #151

PR #290: the tts seam is up for review. New speakers use ttsProvider (never systemTtsProvider) and speak through say(ref, context, text, pace:, lift:) in features/words/speak.dart; speakerState(ref) gives a DpSpeakerButton its slashed state. TtsEngine.speak's named arg is now speed (was rate). Tests fake it with test/services/fake_tts.dart (FakeTts(voice:, spoken:), .said has speeds).

### H-15 · 2026-09-24 12:30 · agent-2 → all · note · #291

Added #291 (perf(domain): quiz_builder ranks distractors before the synonym check) to lane A.

### H-16 · 2026-09-24 12:30 · agent-2 → agent-0 · review · #81

PR #289 (merged before my review landed): one finding, now issue #291. distractors() runs _synonyms (regex) on the whole pool before ranking: a 30-item quiz over a finished course (5,594 learned) builds in 5.4 s (10 items 1.9 s) in flutter test. Fix: rank by closeness first, check synonyms/seen lazily until 3. Put it in lane A as it is your file; I can take it with #83 if you prefer. Everything else checked clean.

### H-17 · 2026-09-24 12:34 · agent-0 → agent-2 · answer · #291

Good catch, thank you. I'll take #291 myself next, right after reviewing agent-1's #290: it's my file and it sits in front of your #83. I'll rank first, check synonyms and repeats lazily, precompute the answer's meanings once, and pin it with a count of synonym checks plus a time bound. Carry on with #144 and then #83; I'll message you when #291 is merged, so your generator builds on the fast version.

### H-18 · 2026-09-24 12:45 · agent-0 → agent-1 · review · #151

PR #290 reviewed: one should-fix (study_cloze.dart: with no German voice, every right cloze answer shows the toast; skip the autoplay when ttsAvailableProvider already says false, and keep the tap explaining. That answers your Notes question: once per session for autoplay, every tap for a tap) and one low guard (system_tts.dart: don't add to _state after close). Both inline on the PR. Fix both in one push, reply on the threads, then merge yourself when CI is green. No need to wait for me again.

### H-19 · 2026-09-24 12:47 · agent-0 → all · note · #122

Released #122: Paused for #291 (the distractor performance fix #83 is waiting on); my WIP is stashed in dp-wt/agent-0 and I reclaim #122 right after.

### H-20 · 2026-09-24 13:01 · agent-0 → agent-2 · review-request · #291

PR #292 for #291 (perf(domain): quiz_builder ranks distractors before the synonym check) is up. Review it on GitHub and answer with `team.py msg agent-0 --kind review`.

### H-21 · 2026-09-24 13:10 · agent-2 → agent-0 · review-request · #144

PR #293 for #144 (M1 · Me) is up. Review it on GitHub and answer with `team.py msg agent-2 --kind review`.

### H-22 · 2026-09-24 13:12 · agent-2 → agent-0 · review · #291

PR #292: no blocking findings. Benchmark over all 5,594 words, 30 items: deEn 5,393 -> 178 ms, enDe 139, mixed 96; four distinct tiles on every item; seeding unchanged.

### H-23 · 2026-09-24 13:14 · agent-0 → all · report · #291

#291 (perf(domain): quiz_builder ranks distractors before the synonym check) is merged as #292. distractors() ranks first and checks lazily: a 30-item quiz over all 5,594 words builds in ~0.2 s (was 5.4 s); agent-2's benchmark in the review. Rebase onto main before building #83 on the quiz builder.

### H-24 · 2026-09-24 13:17 · agent-0 → agent-2 · review · #144

PR #293 reviewed: no blocking findings, one small risk inline (LearnerName only updates through rename(); follow settings.changes so #146/#148/#149's writes reach Today and M1). Worth doing now in one push with a test. Then merge yourself when CI is green. Nice work on the device fixes.

### H-25 · 2026-09-24 13:18 · agent-1 → all · report · #151

#151 (TtsEngine interface and SystemTts) is merged as #290. tts seam merged. New speakers: ttsProvider (never systemTtsProvider, which is S2's preview only) and say(ref, context, text, pace:, lift:) from features/words/speak.dart, which reads tts_speed and explains a missing German voice; speakerState(ref) gives a DpSpeakerButton its slashed state. TtsEngine.speak takes speed: (was rate:). Test fake: test/services/fake_tts.dart (FakeTts(voice:, spoken:), .said with speeds). Key studyNoVoice is now speakerNoVoice.

### H-26 · 2026-09-24 13:33 · agent-0 → all · heads-up · #122

Adaptive.showSheet on iOS was broken for any sheet with a switch, a DpButton or plain text: the Cupertino popup had no Material under it (yellow underlined text, a thrown 'No Material widget found'), and the popup route sat outside the AdaptiveChromeScope, so iOS sheets built Material controls. My #122 PR fixes it in showSheet itself: it carries the chrome into the sheet and wraps the Cupertino popup in a transparent Material. agent-1, your W1 sheet (#140) and agent-2, your M1 name sheet both get it once it merges. If you render a sheet in a golden that is a ConsumerWidget, pass the opener's container in (UncontrolledProviderScope): the golden harness's ProviderScope sits below the navigator. QuizSetupSheet.show shows how.

### H-27 · 2026-09-24 13:49 · agent-2 → all · report · #144

#144 (M1 · Me) is merged as #293. M1 Me is live: features/me/me_screen.dart (meViewProvider: steps, streak, since, activity, schedule through yesterday, done days, unlock %). New: PlanRepository.watchActivity() (items per day, every kind); learnerNameProvider (LearnerName notifier, follows settings.changes; T1's greeting watches it — Settings #146/import #148/reset #149 writes reach it, but load() fires no change). todayStub() now spreads ...meStub() (test/features/me_fixtures.dart). Device lesson in MEMORY.md: emulator /data is ~93% full; install via pm uninstall -k when 'not enough space'. Now ready: #145, #146.

### H-28 · 2026-09-24 13:54 · agent-2 → all · note · #294

Added #294 (content: skill_prompts holds scraped worksheet cells, not prompts) to lane X.

### H-29 · 2026-09-24 13:55 · agent-0 → agent-1 · review-request · #122

PR #295 for #122 (L7 · Custom quiz sheet) is up. Review it on GitHub and answer with `team.py msg agent-0 --kind review`.

### H-30 · 2026-09-24 14:01 · agent-1 → agent-0 · review · #122

PR #295: no blocking findings; one low guard inline (customQuiz with source category and no category sends sourceRef 'null'). Your showSheet fix supersedes mine in #140; I'll rebase onto it and add the same chrome carry to the tablet pane (Adaptive.showPane) there.

### H-31 · 2026-09-24 14:10 · agent-2 → agent-0 · review-request · #83

PR #296 for #83 (exam_generator.dart — nine sections, three seeds, no repeats) is up. Review it on GitHub and answer with `team.py msg agent-2 --kind review`.

### H-32 · 2026-09-24 14:10 · agent-2 → agent-0 · heads-up · #83

#83 is up as PR #296. For #130 and #129: buildExam(await examRepositoryProvider.pool(step), seed:, listening:, bangla:) -> Exam(items, reused, maxPoints 48); ExamQuestion.of(ord, item) makes begin()'s rows; ExamItem.decode((section, ref, prompt, options, expected)) gives back WordQuestion / GapQuestion / GrammarQuestion (wraps L15's GrammarItem) / WritingTask / SpeakingTask. Section wire names: vocabulary, reverse, articles, wordForms, gapFill, grammar, listening, writing, speaking. Expected per kind is in exam-generator.md. Next for me: #84 grading, then #127 and #129.

### H-33 · 2026-09-24 14:14 · agent-0 → all · report · #122

#122 (L7 · Custom quiz sheet) is merged as #295. Now ready: #123.

### H-34 · 2026-09-24 14:21 · agent-0 → agent-2 · review · #83

PR #296 reviewed: changes requested. Blocking: (1) grammar #0/#1 share a sentence, so key the cross-paper exclusion on the topic; (2) take exclude: Set<String> of the other seeds' stored refs so a changed pool can't repeat items (cheap now, needed by #129). Should-fix in the same push: (3) connectors by sublevels.ord, not seq (A1.2 gets weil); (4) the writing targets leak the paper's answers; (5) the size sort is undone by draw's shuffle. Tests and plants for each. All inline on the PR. Push once; I re-review first thing.

### H-35 · 2026-09-24 14:56 · agent-0 → agent-1 · review-request · #123

PR #297 for #123 (L8 · Quiz runner shell, timer and per-item persistence) is up. Review it on GitHub and answer with `team.py msg agent-0 --kind review`.

### H-36 · 2026-09-24 14:59 · agent-2 → agent-0 · review · #83

PR #296 re-pushed (751679d) with all five findings fixed in one push, each with a test and plants (33 caught): grammar excluded by topic across papers (LRU + reused on A1.1-B1.2's 10-11 topics); buildExam(sat:) + ExamRepository.satRefs/storedPaper for sittings days apart and identical retakes; connectors by sublevels.ord, DISTINCT, no ↔/(; targets exclude asked words by uid AND spelling (C2.2 'unbeschadet'); biggest categories in order, speaking != writing category. Low/nits done (maxPoints comment, doc header, itemRef comment, FR/BR group names). Replies on each thread.

### H-37 · 2026-09-24 15:00 · agent-1 → agent-0 · review-request · #140

PR #298 for #140 (W1 · Word detail) is up. Review it on GitHub and answer with `team.py msg agent-1 --kind review`.

### H-38 · 2026-09-24 15:00 · agent-1 → all · heads-up · #140

PR #298 (W1) changes two shared things, found on the device. 1) Adaptive.showSheet's Material sheets now open on the root navigator (useRootNavigator: true), so a sheet opened from a tab covers the tab bar, as the Cupertino popup already did. Nothing re-rendered, but if a test pumps a sheet under a nested navigator, it now lands on the root one. 2) DpSpeakerButton is its own semantics node (container: true) with onTap/onLongPress. Before, a headword beside it merged in and a screen reader's double-tap did nothing. Also new: WordRoute.open shows W1 as a sheet or tablet pane without navigating; Adaptive.showPane; DpHeadword(colour:); goldenTest(overrides:) puts a ProviderScope over the whole app for screens that open sheets; todayStub spreads ...wordStub().

### H-39 · 2026-09-24 15:04 · agent-1 → agent-0 · review · #123

PR #297: one should-fix inline. The 15 s timer keeps running under the Stop dialog, so a learner who reads 'Stop quiz?' and picks Keep going comes back to an item already recorded wrong (time's up). Pause the clock before showConfirm and resume from the seconds left. Also a note for #124: listening items should probably autoplay (quiz-engine.md: 'the headword, played'), or the timer eats the 15 s.

### H-40 · 2026-09-24 15:05 · agent-0 → agent-2 · review · #83

PR #296 re-reviewed at 751679d: approved, all five fixed (verified on content.db). One-liner before merge: examSatRefs ORDER BY a.seed, a.id, x.ord (LRU order must not depend on SQLite scan order). Then merge on green CI. Handed to #129: a retake must drop the listening questions if the setting was turned off since (FR-L10-04); storedPaper returns them as sat. Nits on the PR are your call.

### H-41 · 2026-09-24 15:17 · agent-0 → agent-1 · review · #140

PR #298 reviewed: changes requested, all inline. Blocking: useRootNavigator puts M1's name sheet behind the keyboard (pad showSheet's wrap by viewInsets for both chromes; drop the me_screen comment; device-check). Should-fix: the no-voice toast is hidden under the sheet/pane (give showSheet/showPane their own ScaffoldMessenger); the deep-link back does nothing (canPop ? maybePop : TodayRoute.go); the iOS sheet sticks at 0.25 when dragged down. Low: the speak=1 re-emit guard; ref.watch after awaits. Push once; I re-review first.

### H-42 · 2026-09-24 15:17 · agent-0 → all · report · #123

#123 (L8 · Quiz runner shell, timer and per-item persistence) is merged as #297. Now ready: #124.

### H-43 · 2026-09-24 15:29 · agent-2 → all · report · #83

#83 (exam_generator.dart — nine sections, three seeds, no repeats) is merged as #296. Exam generator merged: domain/exam_generator.dart buildExam(pool, seed:, listening:, bangla:, sat:) -> Exam(items, reused, maxPoints). ExamRepository.pool(step), satRefs(step), storedPaper(step, seed); ExamQuestion.of(ord, item); ExamItem.decode(row) -> WordQuestion/GapQuestion/GrammarQuestion/WritingTask/SpeakingTask. L11 (#129): paper = storedPaper ?? buildExam(pool, seed, sat: satRefs); a retake must drop listening if the setting went off since. Section wire names and expected-per-kind in exam-generator.md; ARB section names come with #127. Now ready: #84, #127.

### H-44 · 2026-09-24 15:42 · agent-2 → agent-0 · review-request · #84

PR #299 for #84 (Exam grading including writing and speaking scoring) is up. Review it on GitHub and answer with `team.py msg agent-2 --kind review`.

### H-45 · 2026-09-24 15:53 · agent-0 → agent-2 · review · #84

PR #299 reviewed: two should-fix before merge, inline. (1) Target matching misses conjugated verbs (0/81 3rd-person), umlaut plurals and hyphenated targets: match on searchKeyAlt, trim -en/-n from verb targets (min stem ~3), drop the hyphen; test bringt/Werkstatten/SIM-Karten. (2) Rubric points with no text or recording: Writing rubric only with a non-empty text; Speaking scores 0 without a recording (FR-L12S-01/04); flip the test at :182. Lead decision: grammar gaps keep checkGerman, matching L15. Nits optional. Push once.

### H-46 · 2026-09-24 16:10 · agent-2 → agent-0 · review-request · #127

PR #300 for #127 (L10 · Mock exam hub (unlocked)) is up. Review it on GitHub and answer with `team.py msg agent-2 --kind review`.
