# Testing strategy

| Layer | Tool | Coverage target | Examples |
| --- | --- | --- | --- |
| Domain | `flutter_test` (pure Dart) | 95 % | FSRS reference values, plan engine scenarios with a fake clock, answer checking vectors, exam generator no-repeat property test over every step, grammar item generation over every topic in content |
| Data | drift in-memory DB with the real content.db attached | 90 % | DAO queries, migrations from every previous schema fixture, export/import round trip |
| Widgets | `flutter_test`, with provider overrides and hand-written fakes for TTS, the translator and the downloader (`todayStub()`, `wordStub()`) | key flows | reveal → rate → undo; navigator jump; settings rows write keys |
| Goldens | `matchesGoldenFile`, through `test/golden/golden_harness.dart` | every screen × light/dark/glass × phone/tablet | stored under `test/golden/goldens/` |
| Integration | `integration_test` on the Android emulator (`tools/smoke.py`) | smoke | onboarding → first session → day complete; exam resume after kill |
| Performance | `flutter drive --profile` timeline | budgets in `accessibility-performance.md` | glass list scroll, card transition |

Rules:
- Test names carry FR/BR IDs.
- Goldens are updated per file, for the screens a change touches (`flutter test --update-goldens test/golden/<screen>_golden_test.dart`), and reviewed as images in the PR. `make goldens` rewrites the whole suite, which hides an unintended change among hundreds of files.
- `goldenTest` also runs each case at 150 and 200 % text (phone, light), with no image, under Android 14+'s nonlinear scaling (`AndroidTextScaler`: Flutter's test scaler is linear, which a phone's isn't; iOS cases keep the linear one): no layout exception, `expectNothingClipped` (text cut to a fixed box) and `expectNoWordBroken` (a word split across lines other than at a soft hyphen). `textAudit: false` skips it for a case that is itself a large-text golden (`textScale: 2`), and a case whose `act` can't run at 200 % scrolls to its target first (#165).
- `goldenTest` also runs each case once more, as `'<name> · labels'` (phone, light, after its `act`). Every control a screen reader can press must have a name (`labeledTapTargetGuideline`), and under Material chrome every icon-only control must have a tooltip (`expectIconButtonsTipped`, #162).
- Most tests run over `ContentFixture`, a small content.db built for the test. A test about the real course's counts reads them from `app/assets/db/content_manifest.json` instead of hard-coding them, as `content_dao_test`'s FR-M9-01 does.

## Integration smoke (#169)

The two flows that must never break, on the real app and the real content.db:

- `app/integration_test/first_day_test.dart` — a fresh install: S1 → S2 (every page, the defaults, A1.1) → T1 → the day's session (each new word turned over and rated Good) → T3 → T5 when the day has sentences → T6, which hands back to T1 reading "All done".
- `app/integration_test/exam_start_test.dart` — L10 → L11 → L12: Mock 1 begun and three typed answers written, then the test ends mid-exam. It sets `exam_unlock_percent` to 0 first: the smoke is about the runner, not BR-EXAM-01's threshold.
- `app/integration_test/exam_resume_test.dart` — a new process: L10 offers *Resume*, L12 opens at question 4 with the three answers there, and *Leave* abandons it.

Run it with the device lock held, from the repo root:

```bash
python tools/team.py device
python tools/smoke.py                     # --device emulator-5558 is the default
python tools/team.py device --release
```

`smoke.py` uninstalls the app, runs the three files in order with `flutter test --no-uninstall -d <device>`, and force-stops the app between the exam's two halves (checking with `pidof` that no process is left). `--no-uninstall` is what keeps user.db from one run to the next: without it `flutter test` uninstalls the app after each run, and its reinstall is `adb install -r`, which keeps data. It prints PASS or FAIL per step and exits non-zero on the first failure. Each file builds its own debug APK, so a run takes several minutes. The helpers the files share are in `integration_test/smoke.dart`; they wait on the real clock in bounded steps rather than `pumpAndSettle`, which the aurora and the exam clock never let settle.

Out of reach, deliberately: the iOS simulator (this is a Windows host) and CI (switched off by the owner, #302). The smoke is run by hand on the emulator, like the device check.
