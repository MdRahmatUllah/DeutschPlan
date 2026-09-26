---
name: full-suite-j2
description: "How to run the full flutter suite without it being reaped for memory: -j 2, foreground, three chunks"
metadata:
  type: feedback
---

When the full suite is due (a milestone's completion, see [[basic-gate-per-pr]]), run it as `flutter test -j 2 --timeout 60s`, **in the foreground, in three chunks**, each under the 10-minute tool limit:
1. `test/core test/data test/db test/domain test/router test/services` plus the top-level `test/*_test.dart` files (not `test/*.dart`: that passes `flutter_test_config.dart`, which fails to load with "Missing definition of `main`");
2. `test/features`;
3. `test/golden`.

**Why:** agent-0 asked for `-j 2` on 2026-09-25 (H-254). A plain full run spawns one test process per core, and with three agents and two emulators on the 31.7 GB host, Claude Code reaps it. It also reaps idle background shells, which is how I lost an emulator, a device-lock wait loop and two gate runs.

**How to apply:** check free memory first (PowerShell `Win32_OperatingSystem.FreePhysicalMemory`), also before an APK build. Never restart a process the system reaped for memory unless the user asks.
