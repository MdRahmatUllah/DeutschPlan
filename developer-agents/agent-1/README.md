# agent-1: developer, lane B

agent-1 builds the voice, the words and search, and it took a large share of
the polish. Through M4–M7 it owned lane B: the TTS seam and Supertonic, word
detail and compare, search and add-word, the download and model manager, and
localisation, reduce-motion, performance and error handling. In 1.0.1 it
did 7 of the 17 large-text fixes: the keyboard family and the Bangla audit.

- **Worktree:** `<root>/dp-wt/agent-1`. **Board clone:** `<root>/dp-team/agent-1`.
- **Memory:** [`memory.md`](memory.md). **What it built:** [`work-history.md`](work-history.md).

## Lane B, in the order it was planned

1. #151 `TtsEngine`, with a `tts` provider seam so every speaker (W1, R1, the quiz runner) codes against it.
2. #140 W1 word detail. Every "open word" goes through `WordRoute.open`: a sheet on phones, a pane on tablets, with `?speak=1`.
3. #137 R1 search results; #141 W1 actions (and the `Translator` interface, "unavailable" by default); #138, #139.
4. #156 the download manager, built against fakes until the manifest URLs were fixed (#245).
5. #142 W2 compare; #143 R2 add word (it edits `quiz_builder.dart`, agent-0's file: message first).
6. #280 iOS bar titles (the `shared-look` lock).
7. #152 Supertonic, then #153 `TtsService`: every `systemTtsProvider` call site migrated.
8. #155 the M4 model manager.
9. #166 localisation, #164 reduce motion, #167 performance, #174 the error matrix, #163 contrast.

What it hands to others: the speaker API (to agent-0's quiz and exam
runners), W1 and `?speak=1` (to agent-0's #136 and agent-2's widget #160),
and the engine swap (to #155, #167, #174).

## How a session runs

1. `team.py agents`, `team.py join agent-1`, then read `agents/agent-1.md` and `MEMORY.md`, then `team.py status`.
2. **Open PRs first:** its own (fix, re-check, merge on approval), then review requests from others. Reviews beat new work.
3. Handoffs from agent-0 (assignments come first), then `team.py ack`.
4. Continue `Now`, or `team.py claim` the first ready issue: assigned ones, then lane B, then lane X floaters.
5. If nothing is ready: `team.py msg agent-0 --kind question -m "lane dry"`. Meanwhile, review or re-check.
6. End: `team.py next`, `team.py note`, `team.py leave`.

## How it takes one task, claim to merge

It follows `ONBOARDING.md` §4 step by step:

1. **Claim, branch, generate.** `team.py claim N`; `git switch -c feat/N-slug origin/main` in its worktree; the gen sequence.
2. **Read** the issue, the spec's FR/BR ids, and every artboard (the HTML for exact sizes; `tools/artboard.py` for the glass set). A pure spec gap is filled in the doc and named in the PR; a real decision goes to `team.py decision` on a new issue, not the one in review ([decision-resets-issue](../shared-memory/decision-resets-issue.md)).
3. **Implement** within the architecture rules. Copy goes in both ARB files. Anything that speaks goes through the `tts` seam.
4. **Test:**
   - unit tests for logic, widget tests for behaviour, DB tests for queries, all with FR/BR ids in their names;
   - keyboard tests set `viewInsets` in physical pixels ([test-viewinsets-physical](../shared-memory/test-viewinsets-physical.md));
   - semantics handles are disposed inline ([test-semantics-dispose-inline](../shared-memory/test-semantics-dispose-inline.md)).
5. **Goldens** per file (light, dark, glass × phone, tablet; iOS where the chrome differs), compared with the artboard. The text audit runs at 150/200 % in en and bn, with the keyboard pass.
6. **The basic check:** analyze, format, the touched tests and their goldens (pytest too, if `tools/` changed).
7. **Plants:** one per claimed behaviour in a plants file outside the repo, then `tools/plant.py`; all must be CAUGHT.
8. **Device check** for anything with platform behaviour (audio, downloads, notifications):
   - take `team.py device` on its own and read the answer;
   - build a release x64 APK;
   - drive it with `tools/device.py`, look at the screenshots;
   - `device --release`.

   Before timing with `perf.py`, reboot the emulator if its swap is full ([perf-reboot-emulator](../shared-memory/perf-reboot-emulator.md)).
9. **Commit, PR:** the PR body starts with `**Agent-1**` and lists the plants; then `team.py review N --pr P`, plus a direct message to an idle reviewer.
10. **Fix** the findings in one push. **Merge** on an approving review, read in full. Delete the branch once the PR is MERGED; then `team.py done`.

## How it reviews

It posts the review as a PR comment starting with `**Agent-1** review`:
what it checked, then findings graded blocking, should-fix or nit, each with
evidence and a suggested fix. It does not merge another agent's PR; it tells
the author it is approved ([no-merging-others-prs](../shared-memory/no-merging-others-prs.md)).

## What it knows best

- The TTS stack: the `tts` seam, system TTS, Supertonic on ONNX Runtime (R8 must keep `ai.onnxruntime`), audio caching and player warm-up.
- Downloads with `background_downloader`: the Wi-Fi-only rule, resume, the notification, the space check.
- Search: `search_repository.dart`'s four tiers, `WordRow`, and meanings in the learner's language (`withMeanings`).
- Large text with the keyboard up: `SgScript.largeTyping`, and "one role smaller, then scroll" for prompts.
