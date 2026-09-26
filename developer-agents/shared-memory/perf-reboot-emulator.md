---
name: perf-reboot-emulator
description: "before perf.py start/frames on emulator-5558, reboot it if its swap is full — hours of uptime made every start ~2.3x slower"
metadata:
  type: project
---

emulator-5558 has 2 GB RAM. After ~5 h of shared use (2026-09-26), 1.2 of its 1.5 GB swap was in use: `perf.py start` read cold 6.8 s and warm 2.4 s against #464's 2.8 s / 1.05 s baselines. Warm (untouched by the change under test) failing the same way was the tell.

**Why:** a slow emulator makes perf.py's regressions false, and a baseline recorded on it is useless.

**How to apply:** under the device lock, check `adb -s emulator-5558 shell cat /proc/meminfo` (SwapFree); if swap is mostly used, `adb -s emulator-5558 reboot`, wait for `sys.boot_completed`, then measure. Compare warm against its baseline before trusting a cold regression. See [[device-lock-check]].
