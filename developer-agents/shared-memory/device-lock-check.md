---
name: device-lock-check
description: "Never chain `team.py device` with install/device.py in one command: a refused lock must stop the check"
metadata:
  type: feedback
---

Run `python tools/team.py device` as its own command and read its output before any `flutter build apk` install, `tools/device.py` or `adb` call. Only "device held" means go. On "refused: the device is in use by …", do other work and retry later.

**Why:** on 2026-09-25 a chained `team.py device; … device.py install …` carried on after "refused" and installed my build on emulator-5558 in the middle of agent-2's device check. Earlier the same session I'd also used emulator-5554, which is agent-3's (SQA) alone. See [[ci-minutes]] for the other team rules.

**How to apply:** use one tool call for the lock and a separate one for the device work. Only ever target `emulator-5558` (`device.py` defaults to it; plain `adb` needs `-s emulator-5558`).

It happened again on 2026-09-25 (agent-2, #282): `team.py device 2>&1 | tail -1 && flutter build … && device.py install` installed over agent-1's build. A pipe into `tail` makes the exit status `tail`'s (0), so `&&` doesn't stop on "refused". Never pipe the lock command, and never put anything after it in the same call.
