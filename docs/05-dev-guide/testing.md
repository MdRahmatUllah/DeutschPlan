# Testing strategy

| Layer | Tool | Coverage target | Examples |
| --- | --- | --- | --- |
| Domain | `flutter_test` (pure Dart) | 95 % | FSRS reference values, plan engine scenarios with a fake clock, answer checking vectors, exam generator no-repeat property test over every step, grammar item generation over every topic in content |
| Data | drift in-memory DB with the real content.db attached | 90 % | DAO queries, migrations from every previous schema fixture, export/import round trip |
| Widgets | `flutter_test`, `mocktail` fakes for TTS/translator/downloader | key flows | reveal → rate → undo; navigator jump; settings rows write keys |
| Goldens | `alchemist` | every screen × light/dark/glass × phone/tablet | stored under `test/golden/` |
| Integration | `integration_test` on emulator + simulator | smoke | onboarding → first session → day complete; exam resume after kill |
| Performance | `flutter drive --profile` timeline | budgets in `accessibility-performance.md` | glass list scroll, card transition |

Rules: test names carry FR/BR IDs; goldens are updated only by `make goldens` and reviewed as images in the PR; content-dependent tests read `content_manifest.json` so counts don't hard-code.
