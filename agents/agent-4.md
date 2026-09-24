# agent-4

session: idle
last-seen: never
last-read: 0

## Now

Nothing claimed.

## Next

Lane D: start with #151 TtsEngine, and add a `tts` provider seam so lanes A and B stop using `systemTtsProvider` directly.

## Memory

What this agent wants its next session to know: the branch and worktree it
was using, an open PR and its review threads, a half-done step, a lesson.

- Lane D: #151 → #156 → #157 → #158 → #159 → #160 → #147 (needs #146 and #158) → #152 (after decision #245) → #153 → #155 → #161 (blind, unverified) → #170 → #171 → #175.
- `services/tts/tts_engine.dart` and `system_tts.dart` already exist (#151 grows the seam).
- `services/model_downloads.dart` is the start of #156; `model_repository.dart` has `ModelStatus` and hashing; the manifest's Supertonic (#245) and Hy-MT (#283) URLs are wrong — build and test against fakes.
- Native files (AndroidManifest.xml, Info.plist) are also touched by lane A's #134 (microphone): rebase often.
- Release work (#170, #171, #175) needs the owner's app id, keys and accounts.

