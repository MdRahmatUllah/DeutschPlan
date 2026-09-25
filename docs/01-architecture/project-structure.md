# Project structure

```
deutschplan/                        ← repository root
├── data/                           ← content sources, the German_*_Tracker.xlsx workbooks (git-ignored;
│                                     only where content is edited). The pipeline compiles the ones
│                                     content/manifest.yaml lists
├── content/
│   ├── manifest.yaml               ← which workbooks to compile, in which order, with level hints
│   ├── interference_tips.csv       ← hand-authored L1 tips (uid or pattern → tip en/bn)
│   └── build/                      ← output: content.db + content_manifest.json (git-ignored)
├── tools/
│   ├── excel_to_sqlite.py          ← the pipeline (Python 3.10+, openpyxl), with pipeline_steps.py,
│   │                                 content_writer.py and the content_schema.sql / content_fts.sql DDL
│   ├── verify_content.py           ← integrity checks, run after every pipeline build
│   ├── content_manifest.py         ← what changed between two builds (`make content-diff`)
│   ├── mirror_content_schema.py    ← writes app/lib/data/db/content_schema.drift from the pipeline's DDL
│   ├── trim_schema_fixture.py      ← trims a `schema dump` fixture (`make schema-dump`)
│   ├── render_design.py            ← renders the Paper & Ink artboards to docs/design/*.png
│   ├── artboard.py                 ← an artboard beside a golden, to compare by eye (glass too)
│   ├── plant.py                    ← planted violations: break the code, check a test notices
│   ├── device.py · smoke.py        ← drive the emulator; the integration smoke
│   ├── team.py                     ← the agents' board
│   └── tests/                      ← the tools' pytest suite
├── deutsch-plan-design-html/       ← Paper & Ink + Night Ink prototype: 58 screens + Foundations
│                                     (59 files) × android-light/dark and ios-light/dark
├── deutsch-plan-v2-aurora-glass-html/  ← Aurora Glass prototype, the same 59 files ×
│                                     the same four canvases
├── docs/                           ← this documentation (source of truth)
├── Makefile                        ← the developer entry points (getting-started.md)
└── app/                            ← Flutter project
    ├── pubspec.yaml
    ├── l10n.yaml · lib/l10n/*.arb  ← en, bn (German strings live in content, not ARB)
    ├── drift_schemas/              ← one JSON fixture per schema version (committed)
    ├── assets/
    │   ├── db/                     ← content.db and content_manifest.json, copied from content/build by
    │   │                             `make content` (committed)
    │   ├── fonts/                  ← Inter, NotoSansBengali
    │   ├── licences/               ← the model and font licence texts M8 shows
    │   └── models/manifest.json    ← the downloadable models (model-manager.md)
    ├── lib/
    │   ├── main.dart · bootstrap.dart   ← startup: open user.db, attach content.db, load settings
    │   ├── core/                   ← adaptive/ (all platform chrome), components/, providers/
    │   │                              (every repository and service provider), theme/ (tokens, 3 modes,
    │   │                              glass, AuroraBackdrop), typography/ (DpText)
    │   ├── data/
    │   │   ├── db/                 ← user_schema.drift (authoritative DDL), *_queries.drift, content.drift,
    │   │   │                          AppDatabase (with its migration steps), ContentDao, content attach
    │   │   └── repositories/       ← the only layer that touches drift: WordRepository, PlanRepository,
    │   │                              GrammarRepository, ExamRepository, SettingsRepository,
    │   │                              ModelRepository (the model files on disk), BackupRepository
    │   │                              (export/import) and their stores
    │   ├── domain/                 ← pure Dart, no Flutter or drift: fsrs, answer_check, text_norm,
    │   │                              plan_engine, quiz_builder, exam_generator, grammar_item_generator,
    │   │                              sentence_picker, … Value types are @immutable classes, records
    │   │                              and sealed classes
    │   ├── features/               ← one folder per screen group: backlog/, bootstrap/, day_complete/,
    │   │                              exam/, learn/ (L1–L6 and the grammar screens), me/ (Me and
    │   │                              settings), onboarding/, quiz/, search/, sentences/, splash/,
    │   │                              study/, today/, words/
    │   │       └── <group>/        ← screens (each with its providers at the top of the file,
    │   │                              riverpod codegen), and their local widgets
    │   ├── services/               ← platform plugins behind small interfaces: tts/ (TtsEngine,
    │   │                              SystemTts), translation/ (Translator), model_downloads,
    │   │                              device_storage, reminder_notifications, background_tasks,
    │   │                              widget_snapshot, exam_recorder, backup_files
    │   └── router/                 ← go_router config, typed routes, the shell, deep links
    ├── test/                       ← domain, data and db, features (widget), golden (per theme),
    │                                  core, router and services; architecture_test.dart and
    │                                  l10n_test.dart enforce the rules
    ├── integration_test/           ← the emulator smoke (testing.md, "Integration smoke")
    └── android/ · ios/             ← native: the Glance widget, the platform channels, launch screens
```

## Layering rules

1. `domain/` imports nothing from Flutter or drift. Everything there is unit-testable with plain Dart.
2. `data/` implements repository interfaces declared in `domain/` and is the only layer that touches drift.
3. `features/` widgets read providers; they never call repositories directly.
4. `services/` wrap platform plugins behind small interfaces (`TtsEngine`, `Translator`, `AudioPlayer`) so tests can fake them.
5. Copy lives in ARB files. German course text comes from content.db, never from ARB.

## Naming

- Files: `snake_case.dart`; screens end in `_screen.dart`, with their providers at the top of the same file (Today's are in `today_providers.dart`). The user tables are in `user_schema.drift` (ADR 22) and the queries in `*_queries.drift`; DAOs are `*_dao.dart`.
- Requirement IDs from `docs/` appear in test names: `test('FR-T1-03 primary button label shows remaining count', …)`.
