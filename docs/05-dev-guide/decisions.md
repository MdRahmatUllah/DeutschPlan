# Decision records (ADR)

| # | Date | Decision | Why | Revisit when |
| --- | --- | --- | --- | --- |
| 1 | 2026-09 | Excel authoring, compiled to SQLite | No formula engine on device; fast; typed | Never (authoring can move, output stays SQLite) |
| 2 | 2026-09 | Two databases: content.db (read-only, attached) + user.db | Content updates never touch progress | — |
| 3 | 2026-09 | drift over raw sqlite3 | Typed queries, migrations, streams, FTS5 API | — |
| 4 | 2026-09 | Riverpod 3 codegen | Testability, caching | — |
| 5 | 2026-09 | go_router 18 with StatefulShellRoute | Tab state, deep links | — |
| 6 | 2026-09 | Start on material_ui/cupertino_ui (3.47) | In-SDK libraries deprecated Nov 2026 | — |
| 7 | 2026-09 | FSRS-4.5 default weights | Better than SM-2; optimisation later | ≥ 1,000 reviews per learner |
| 8 | 2026-09 | Supertonic 3 via flutter_onnxruntime; system TTS fallback | On-device, permissive licence | If the ONNX plugin lags ORT releases |
| 9 | 2026-09 | Hy-MT1.5-1.8B via llamadart, 1.25-bit default, behind a build flag | Cross-platform GGUF; licence excludes EU/UK/KR | After legal review; consider Opus-MT/ML Kit alternative |
| 10 | 2026-09 | One exam generator, seeds 1–3 | No hand-authored exams; no repeats | — |
| 11 | 2026-09 | Three theme modes; glass via a single `DpSurface` renderer | Screens stay theme-agnostic | — |
| 12 | 2026-09 | No dynamic (Material You) colour | Gender colours must stay stable | — |
| 13 | 2026-09 | No analytics, no accounts | Privacy promise; audience | — |
| 14 | 2026-09-21 | `sqlite3` 3.x instead of `sqlite3_flutter_libs` | `sqlite3_flutter_libs` is end-of-life; its own description says to move to `package:sqlite3` 3.x, which bundles the native library and is what drift 2.35 depends on | Never — but FTS5 + trigram availability must be asserted at runtime |
| 15 | 2026-09-21 | Drop `custom_lint` | `riverpod_lint` 3.1.4+ is a native `analyzer_plugin` and no longer depends on custom_lint; the two cannot co-resolve (analyzer_plugin ^0.14 vs ^0.13) | If a future lint we want ships only as a custom_lint plugin |
| 16 | 2026-09-21 | Take current majors for eight plugins ahead of the versions in tech-stack.md | `record`, `flutter_local_notifications`, `home_widget`, `workmanager`, `file_picker`, `share_plus`, `permission_handler`, `device_info_plus` and the riverpod/freezed generators had all moved a major since the table was written; running old majors on Flutter 3.47 is the larger risk | Per package, on its next major |
| 17 | 2026-09-21 | Generated code is not committed | `getting-started.md` already runs `build_runner build -d` as a setup step; committing `*.g.dart` adds merge conflicts for no gain | If CI build time makes regeneration expensive |
| 18 | 2026-09-21 | Lint with `dart analyze --fatal-infos`, not `flutter analyze` | `flutter analyze` does not load the `analysis_server` plugin that riverpod_lint 3.1.4+ ships as, so it passes clean while every riverpod rule is inactive; verified by probing `avoid_public_notifier_properties` | If flutter_tools gains plugin support |
