# Testing strategy

| Layer | Tool | Coverage target | Examples |
| --- | --- | --- | --- |
| Domain | `flutter_test` (pure Dart) | 95 % | FSRS reference values, plan engine scenarios with a fake clock, answer checking vectors, exam generator no-repeat property test over every step, grammar item generation over every topic in content |
| Data | drift in-memory DB with the real content.db attached | 90 % | DAO queries, migrations from every previous schema fixture, export/import round trip |
| Widgets | `flutter_test`, with provider overrides and hand-written fakes for TTS, the translator and the downloader (`todayStub()`, `wordStub()`) | key flows | reveal → rate → undo; navigator jump; settings rows write keys |
| Goldens | `matchesGoldenFile`, through `test/golden/golden_harness.dart` | every screen × light/dark/glass × phone/tablet | stored under `test/golden/goldens/` |
| Integration | `integration_test` on the Android emulator (`tools/smoke.py`) | smoke | onboarding → first session → day complete; exam resume after kill |
| Performance | `tools/perf.py`: `flutter drive --profile` frame timings, `am start -W`, APK size, against baselines | budgets in `accessibility-performance.md` | glass list scroll, card transition, search, start, size; with the milestone's full suite and before a release |

Rules:
- Test names carry FR/BR IDs.
- Goldens are updated per file, for the screens a change touches (`flutter test --update-goldens test/golden/<screen>_golden_test.dart`), and reviewed as images in the PR. `make goldens` rewrites the whole suite, which hides an unintended change among hundreds of files.
- `goldenTest` also runs each case at 150 and 200 % text (phone, light), with no image, under Android 14+'s nonlinear scaling (`AndroidTextScaler`: Flutter's test scaler is linear, which a phone's isn't; iOS cases keep the linear one): no layout exception, `expectNothingClipped` (text cut to a fixed box), `expectNoWordBroken` (a word split across lines other than at a soft hyphen) and `expectAllLinesShown` (text cut to its `maxLines`, #551). It allows no cut, a field's hint included: a hint wraps rather than end in "…" (#565). `DpOneLine` passes as it is: it draws only the words that fit, then "…". Anything else in a box of fixed height or lines grows instead. The audit runs again in Bangla (`'<name> · text <scale> % · bn'`, the platform locale set to `bn`, #581): its copy is a role larger, and English never showed #580's cuts. So an `act` finds its copy through `tester.l10n` (the app's `AppLocalizations`), never an English literal, and a control by its label where a Bangla word may be drawn in parts. A case sits out the Bangla pass only through `noBanglaAudit:`, with its reason and issue: only iOS cases, iOS being Later. None does today (#588 fixed the two it first named). `study_back_mature` (Easy at 1,111 days, which wraps in Bangla at 200 % and not in English) holds the rating bar's minimum height in that pass. At 200 %, a case with a text field then puts the keyboard up (#584). Its last field is focused (the one the keyboard fights; a dialog's, over a screen), with SQA's room: a 24 dp status bar and the keyboard's top at 396 dp, as Gboard leaves it on SQA's 411 × 731 phone, which covers a 300 dp keyboard too. Then no layout error; the field under the status bar, above the keyboard and hit-testable (neither scrolled out of its list nor covered); nothing clipped; no word broken; and nothing cut to its lines except that field's own one-line hint while typing past 130 % (#570, skipped by name). A field that opens behind a tap needs a golden case that opens it (M1's name sheet has `me_name_sheet`). Screens with keyboard tests of their own: L8 and L12 (390 × 731 with a 300 dp keyboard, 411 × 731 with 335, 360 × 640 with 280, in English and Bangla), L15 and T2 (390 × 731 with 300; T2 also 360 × 640), R2 (`add_word_test`) and Reset (`reset_keyboard_200`, `_bn`, and #586's). `textAudit: false` skips it for a case that is itself a large-text golden (`textScale: 2`), and a case whose `act` can't run at 200 % scrolls to its target first (#165).
- `goldenTest` also runs each case once more, as `'<name> · labels'` (phone, light, after its `act`). Every control a screen reader can press must have a name (`labeledTapTargetGuideline`) and be big enough to press (48 dp; under iOS chrome 44 pt; a node whose semantics identifier, or an ancestor's, starts `dense:` is skipped as too dense to grow: Me's step badges, iOS's segmented control; and no grown target reaches more than 2 dp into another's box, `expectTargetsApart`; #478), and under Material chrome every icon-only control must have a tooltip (`expectIconButtonsTipped`, #162).
- `test/golden/golden_coverage_test.dart` (#168) pairs every screen in `docs/04-screens/` with its golden files, and fails a screen with none (a native one, the home-screen widget, is named with its reason) and a golden file whose every case narrows the matrix: each screen is drawn at least once in light, dark and glass on the phone and the tablet. A new screen's doc goes into its table with the screen's goldens. It doesn't check the iOS goldens where chrome differs (a back row, a sheet, a segmented control): where that is can't be read off the source, so a `chrome: AdaptiveChrome.cupertino` case stays the reviewer's to ask for.
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
