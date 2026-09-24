# Work log

What each agent did, newest last. `team.py` adds a line for every claim, report
and handoff; add your own with `team.py log -m "..."` at each real step (a test
green, a review posted, a PR merged, a surprise). Anyone reading this should be
able to tell what is going on without asking.

- 2026-09-24 10:45 · agent-1 · M3 finished: #112–#121 and #82 merged, epic #9 and milestone M3 closed
- 2026-09-24 10:45 · agent-1 · follow-ups filed from the PR #279 review: #280 (iOS bar titles), #281 (L6 tests), #282 (glass word lists); from planning: #283 (Hy-MT manifest, decision), #284 (dev-guide drift)
- 2026-09-24 10:45 · agent-1 · board opened with every open issue of M4–M7, four lanes (PLAN.md)
- 2026-09-24 11:21 · agent-1 · session started
- 2026-09-24 11:27 · agent-0 · the team is three agents (agent-0 lead, agent-1, agent-2); lanes rebalanced, PLAN.md rewritten
- 2026-09-24 11:27 · agent-0 #151 · assigned to agent-1
- 2026-09-24 11:27 · agent-0 #140 · assigned to agent-1
- 2026-09-24 11:27 · agent-0 #144 · assigned to agent-2
- 2026-09-24 11:27 · agent-0 #83 · assigned to agent-2
- 2026-09-24 11:27 · agent-0 #81 · claimed: quiz_builder.dart
- 2026-09-24 11:31 · agent-1 · session started
- 2026-09-24 11:31 · agent-1 #151 · claimed: TtsEngine interface and SystemTts
- 2026-09-24 11:31 · agent-2 · session started
- 2026-09-24 11:32 · agent-2 #144 · claimed: M1 · Me
- 2026-09-24 11:47 · agent-0 #287 · added to the board, lane X
- 2026-09-24 11:47 · agent-0 #81 · quiz_builder.dart + DriftQuizStore + quizBuilderProvider written; 23 domain tests green; found 54 C1/C2 nouns with the article inside german (filed #287, lane X)
- 2026-09-24 11:48 · agent-1 #151 · TtsEngine grown (name, isAvailable, speed, state stream); ttsProvider seam + ttsAvailable; say()/speakerState() in features/words/speak.dart; every speaker but S2's preview moved onto it; 14 test fakes -> test/services/fake_tts.dart. Gate running.
- 2026-09-24 12:01 · agent-2 #144 · M1 built: me_screen.dart (header+name sheet, words, 12-week heat-map, schedule through yesterday, exam badges, links), PlanRepository.watchActivity, LearnerName notifier (Today watches it); me_test 27 + me_view_test 5 green; goldens compared light/dark/glass
- 2026-09-24 12:09 · agent-1 #151 · gate green (2164 flutter, 262 pytest); 25/25 plants caught; device check next
- 2026-09-24 12:11 · agent-0 #81 · PR #289 open; review requested from all
- 2026-09-24 12:18 · agent-0 #81 · done (#289)
