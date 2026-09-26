---
name: v1-release
description: "v1.0.0 (2b424e33) and v1.0.1 (0d23968e) tagged 2026-09-26, Android-only; the owner's release decisions and what is still theirs"
metadata:
  type: project
---

v1.0.0 was tagged on 2026-09-26 on main commit 2b424e33 (#558, closing #175). The gate on the tagged code: 4,166 flutter tests and 339 pytest. Smoke 7/7, perf.py passing, licences current. SQA pass 3 found no P1. M7 and epics #14–#17 are closed.

The owner's decisions (2026-09-26):
- v1.0 is Android-only: iOS (#171, #161, #398) is in the milestone "Later · after v1.0" and waits for a Mac.
- Hy-MT is off in every build (ADR 9, #173). #154 is deferred; #494/#533 track a licence-clean translator.
- The app id is io.github.rahmatullah.deutschplan. Signing: the owner adds the upload key later (debug-signed until then).
- llamadart ships its CPU backend only (#463): the arm64 APK is 72.3 MB.
- Controls keep their look (the invisible 48 dp hit areas are the fix, #478/#492). Bangla pronunciation follows the meaning language (#537).
- The update card keeps the newest update's counts (#496). A download asks for notifications at Download (#501).
- A Bangla word too wide first shrinks to 80 %, then breaks with no hyphen (#522).
- The FSRS doc matches the code (#239). The duplicate C2 row is dropped in the pipeline (#407). emulator-5558 was wiped (owner's OK).

**Why:** a future session must not redo the release or re-ask these questions.

v1.0.1 was tagged on 2026-09-26 on 0d23968e (#594, closing #593): 17 large-text and Bangla fixes, gate 4,598 flutter and 339 pytest. The owner said "Tag now" without waiting for SQA, because agent-3 was idle. SQA's 1.0.1 pass (H-1125, H-1130) still stands, and its findings go into 1.0.2. The release commit follows #558's pattern: pubspec version+build, a CHANGELOG entry, and "What's new (X.Y.Z)" in store-listing.md, which test_store_listing ties to the pubspec version.

**Why:** a future session must not redo either release or re-ask these questions.

**How to apply:** still the owner's: the upload key (release.md step 5), a real-phone start check (step 6) before the Play upload, and the OK to restart emulator-5558. Every open issue is in "Later · after v1.0" (iOS needs a Mac; #533 and #154 are the owner's). Related: [[keep-working]], [[merge-open-prs-first]].
