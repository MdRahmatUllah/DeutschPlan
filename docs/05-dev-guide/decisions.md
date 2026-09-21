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
