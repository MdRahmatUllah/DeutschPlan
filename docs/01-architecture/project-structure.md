# Project structure

```
deutschplan/                        ← repository root
├── German_B1_Tracker.xlsx          ← content sources (A1–B1). More workbooks may be added; the
├── German_B2_Tracker.xlsx             pipeline picks up every *.xlsx matching content/manifest.yaml
├── German_C1_Tracker.xlsx
├── German_C2_Tracker.xlsx
├── content/
│   ├── manifest.yaml               ← which workbooks to compile, in which order, with level hints
│   ├── interference_tips.csv       ← hand-authored L1 tips (uid or pattern → tip en/bn)
│   └── build/                      ← output: content.db + content_manifest.json (git-ignored)
├── tools/
│   ├── excel_to_sqlite.py          ← the pipeline (Python 3.11+, openpyxl)
│   ├── verify_content.py           ← integrity checks run in CI
│   └── render_design.py            ← renders the artboards to docs/design/*.png
├── deutsch-plan-design-html/       ← Paper & Ink + Night Ink prototype: 60 artboards ×
│                                     android-light/dark and ios-light/dark
├── deutsch-plan-v2-aurora-glass-html/  ← Aurora Glass prototype, same 60 artboards ×
│                                     the same four canvases
├── docs/                           ← this documentation (source of truth)
└── app/                            ← Flutter project
    ├── pubspec.yaml
    ├── l10n.yaml · lib/l10n/*.arb  ← en, bn (German strings live in content, not ARB)
    ├── drift_schemas/              ← one JSON fixture per schema version (committed)
    ├── assets/
    │   ├── db/content.db           ← copied from content/build by `make content`
    │   └── fonts/                  ← Inter, NotoSansBengali
    ├── lib/
    │   ├── main.dart · app.dart · bootstrap.dart
    │   ├── core/                   ← theme (3 modes), tokens, adaptive widgets, GlassPanel, AuroraBackdrop, extensions
    │   ├── data/
    │   │   ├── db/                 ← user_schema.drift (authoritative DDL), AppDatabase, DAOs, migrations, content attach
    │   │   ├── repositories/       ← WordRepository, PlanRepository, GrammarRepository, ExamRepository, SettingsRepository, ModelRepository
    │   │   └── files/              ← model store, export/import, recordings
    │   ├── domain/                 ← pure Dart, no Flutter imports: models (freezed), fsrs, answer_check, text_norm,
    │   │                              plan_engine, quiz_builder, exam_generator, grammar_item_generator, sentence_picker
    │   ├── features/               ← one folder per screen group: today/, study/, backlog/, sentences/, learn/, grammar/,
    │   │                              quiz/, exam/, search/, word/, me/, settings/, models/, onboarding/
    │   │       └── <feature>/      ← screen widgets, providers (riverpod codegen), feature-local widgets
    │   ├── services/               ← tts (SupertonicTts, SystemTts), translation (HyMtTranslator), audio, notifications,
    │   │                              widget_bridge, downloads, clock
    │   └── router/                 ← go_router config, typed routes, shell
    ├── test/                       ← unit (domain), widget, golden (per theme), db
    ├── integration_test/
    ├── android/ · ios/             ← native: Glance widget, WidgetKit extension, launch screens
    └── tool/                       ← makefile targets, golden update scripts
```

## Layering rules

1. `domain/` imports nothing from Flutter or drift. Everything there is unit-testable with plain Dart.
2. `data/` implements repository interfaces declared in `domain/` and is the only layer that touches drift.
3. `features/` widgets read providers; they never call repositories directly.
4. `services/` wrap platform plugins behind small interfaces (`TtsEngine`, `Translator`, `AudioPlayer`) so tests can fake them.
5. Copy lives in ARB files. German course text comes from content.db, never from ARB.

## Naming

- Files: `snake_case.dart`; screens end in `_screen.dart`; providers in `_providers.dart`; drift tables in `tables.dart`, DAOs in `*_dao.dart`.
- Requirement IDs from `docs/` appear in test names: `test('FR-T1-03 primary button label shows remaining count', …)`.
