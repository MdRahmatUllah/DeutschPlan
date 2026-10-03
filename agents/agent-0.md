# agent-0

session: active
last-seen: 2026-10-03 16:41
last-read: 4193

## Now

#1398 in review as PR #1401: answer review threads; re-run the gate if main moved, then merge.

## Next

#1312: merge last, after #1381 (#1364), the M9 full suite (agent-1), agent-3's #1234 pass and its findings; then tag v1.2.0. Changelog current to #1376. Review #1377's fix push.

## Memory

What this agent wants its next session to know: the branch and worktree it
was using, an open PR and its review threads, a half-done step, a lesson.

- Worktree: F:/appDevs/dp-wt/agent-0.
- Lane A: #81 → #122 → #123 → #124 → #125 → #126 → #130 → #131 → #132 → #133 → #134 → #135 → #136 → #169 → #170 → #171 → #175.
- #124's item widgets must be reusable by the exam runner #130 without verdicts. Reuse `PracticeHeader`/`PracticeStrip` (grammar_practice_screen.dart) and `StudyAnswerField` (study_cloze.dart).
- `QuizArgs` lives in `routes.dart` (no `timer` yet); `stepQuiz` (L2) and `categoryQuiz` (L6) already build it.
- Lead duties: review requests before new work; `team.py assign` when a lane is dry; close epics and milestones (PLAN.md); relay the owner's decisions (`reopen` + `remember decisions`).
- 2026-09-24 21:57: emulator-5558 (developers): onboarded learner on A1.1, exam_unlock_percent=0 (set via a debug build's run-as, then the release build installed over it), Mock 1 in progress. The exam screens (#131-#136) can be device-checked there.
- 2026-09-30 00:27: M8 set up (milestone 11, 38 issues; epic #1085 body has the plan + order). NEXT for agent-0: PR #1087 fixes in dp-wt/agent-0-fix — scheme doc: English stress rule (phrase stress, agent-3 #3), nk row + DANK-uh, OWSS-fewl-len; Polish ich -> ś (IŚ, MET-śen, NIŚC, -iś), capitals approved; Open questions -> Decisions; add a conventions section (masculine where German gives no gender; short meanings with ' / '; same text across workbooks). Pilot staging data/_staging/{en,pl}: danke/Danke schön/ausfüllen (en); ś rows, doch 'ależ tak (po przeczeniu) / jednak', dieser 'ten / ta / to', Kollege 'kolegą z pracy' (pl). Merge-tool guard: new column at ws.max_column+1 or refuse non-empty cells + probe test (agent-1). Then #1099 (claimed), then content per workbook with subagents. Russian pilot still awaits agent-2's review. Review PR #1097 (agent-1) if agent-2 hasn't.
- 2026-09-30 01:25: M8 content state (resume here). Scratchpad m8/ = C:/Users/User/AppData/Local/Temp/claude/F--appDevs-deutschplan/235e22a9-6d7c-4bb0-8033-62309951e502/scratchpad/m8 (briefs brief_en/pl/ru.md, batches/, out/, validate.py, assemble.py <code> <level> --write, check_staging.py, brief_consistency.md, tips_draft.py -> tips_new.csv for #1100, manifest_live.yaml for build checks). EN: A1/A2/B1/B2/C1 assembled in data/_staging/en (A1,A2,B1 consistency done + review copies in data/_staging/merged, review asked of agent-1 on #1101-#1103; B2,C1 passes were running); C2-03 was drafting -> then assemble C2, pass, copies, review. PL: A1 assembled (pass was running); A2-01..11 drafted/running, A2-12/13 running; B1..C2 not started. RU: A1-01..09 + A1-15 drafted/running; rest not started; Russian scheme still awaits agent-2's review (#1083). Live workbooks untouched: merge each language into all six at once under 'team.py lock workbooks' before #1100. Subagents may still finish after this session: validate their out/ files before assembling.
- 2026-09-30 02:25: M8 resume point (2026-09-30 ~02:40). Scratchpad m8/ tools: validate.py, assemble.py <code> <lvl> --write, check_staging.py, brief_*.md, brief_consistency.md, manifest_live.yaml. Merge tool fix PR #1132 (needed for B2/C1/C2 copies; use F:/appDevs/dp-wt/agent-0-fix/tools until merged). #1131 decided: Russian stress = capital vowel (PR #1135 docs). EN: all 6 staged + consistent; A1/A2 re-check + B2/C1/C2 review with agent-1 (#1101,#1102,#1104-1106); #1103 closed. PL: A1 (#1113), A2 (#1114), B1 (#1115) with agent-1; B2 assembled, consistency pass was running; C1-01..06 drafting; C1-07..13, C2 not started. RU: A1 consistent, review with agent-2 (#1107); A2 assembled (needs consistency pass); B1-01/02 drafting; rest not started. #1137 = 2 B2 grammar source errors (fix in corrections.yaml with #1100). tips draft: m8/tips_new.csv. Reviewed+approved #1133 (agent-2 to switch ru fixtures to capitals). Live workbooks untouched.
- 2026-09-30 12:10: M8 scratch: C:/Users/User/AppData/Local/Temp/claude/F--appDevs-deutschplan/235e22a9-6d7c-4bb0-8033-62309951e502/scratchpad/m8 — trial/ (manifest.yaml with absolute paths, corrections.yaml, interference_tips.csv, content.db), add_corr_langs.py (tr_corr.py = 272 ru/pl lines), add_1137.py, compare_db.py (old vs new db proof), corr_impact.py, patch.py (staging+out fixes), sync_back.py, samede.py. Staging = source of truth; out/ synced to it. Review sheets: data/_staging/review/.
- 2026-09-30 14:38: #1149: approved by agent-2 at be1ec28e plus a main merge (tools only, re-gated). Workbooks lock held until it merges; data/ live workbooks carry en/ru/pl (backup in scratch m8/live_backup). pubspec lock held for #1151. Pre-M8 APK (51e2fe66) and candidate APK in scratch.
- 2026-10-01 11:30: 2026-10-01: owner approved #1186 Play titles, #115 bn copy, O1 via DNS TXT (owner), O9 keep address. Release candidate on #1123: built from 04554cf8 (main moved only by tools/test #1185), 6,323 tests, aab sha 0b937c55...; en store sets re-shot (#1184). Draft release PR sogda-website #128. Website default branch is dev (Closes works).
- 2026-10-02 13:15: v1.1.0 tagged 4106e393 (2026-10-02), release/1.1 cut; hand-off on #1123 = Closed testing (D1: personal account). Main stays 1.1.0+4 until #1235 sets 1.2.0+10. M9 lane A: lemmatiser #1256 -> tokens #1260 -> matcher feat/1225-matcher are a stack in dp-wt/agent-0-fix; plants files in the scratchpad (plants1223/1224/1225.json). #1225's data wiring (learner snapshot) goes to #1230.
- 2026-10-02 23:57: 2026-10-02 late: D2 #1294 (fe6c40ab) and D3 #1299 (f8518e20) merged; #1302 (agent-2, M3 docs settings + auto-delete + #1298) and #1292/#1293/#1281 merged too. D3 lives at /search/documents (one stack with D1/D2). AdaptiveScaffold keeps the status strip with bottomBar+statusBarColour. find.textRange reads semantics labels: use a RenderParagraph helper (doc_words_test wordAt) for marked text. #154 reopened (closed by hand; #1269 unmerged until S24).

