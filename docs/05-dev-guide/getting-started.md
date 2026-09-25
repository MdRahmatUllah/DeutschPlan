# Getting started

## Prerequisites

- Flutter 3.47.x stable (`flutter --version`), Dart 3.13.x. The exact version is pinned in `.fvmrc` at the repository root (currently **3.47.5**, which ships Dart 3.13.4). CI reads it from there, so every build uses the same SDK. Install that version however you like: *Using fvm* below is one way.
- Android Studio (latest) with SDK 37 (`compileSdk` and `targetSdk`, ADR 19). The NDK is Flutter's own (`flutter.ndkVersion`). Xcode 16+ with an iOS 16 simulator. CocoaPods is no longer required: Swift Package Manager is the default since Flutter 3.44.
- Python 3.10+ (3.12 in CI) with `openpyxl`, for the content pipeline and the tools' tests.
- `make` is optional. Each target is spelled out below; without `make`, run those commands.

## First run

Generated code isn't committed (ADR 17), so a fresh clone generates it before anything resolves. From the repository root:

```bash
git clone … deutschplan && cd deutschplan
python tools/mirror_content_schema.py
cd app
flutter pub get                 # also runs gen_l10n -> lib/l10n/generated/
dart run drift_dev schema steps drift_schemas/ lib/data/db/schema_versions.dart
dart run drift_dev schema generate drift_schemas/ test/db/generated/
dart run build_runner build --delete-conflicting-outputs
dart analyze --fatal-infos
flutter test
flutter run
```

That generation block is `make gen`, which runs it rather than `build_runner` alone. `AppDatabase` imports `lib/data/db/schema_versions.dart`, which the drift_dev CLI writes from the fixtures in `app/drift_schemas/`. Without that step, build_runner has nothing to analyse and the whole package fails to resolve. Run it again after a rebase or branch switch that changes `.drift` files, providers, routes or ARB files.

`app/assets/db/content.db` is committed, so a first run doesn't build content. `make content` needs the Excel workbooks in `data/`, which is git-ignored and exists only where the content is edited. Run it only for a content change (`docs/02-data/content-pipeline.md`).

## Using fvm

fvm is one way to get the pinned SDK. `.fvmrc` is the source of truth either way. `.fvm/` (the downloaded SDK and its symlink) is git-ignored.

```bash
dart pub global activate fvm     # once per machine
fvm install                      # from the repository root; reads .fvmrc
fvm flutter --version            # should print 3.47.5 / Dart 3.13.4
```

With fvm, prefix Flutter and Dart commands with `fvm` (`fvm flutter test`, `fvm dart run build_runner build -d`), so they use the pinned SDK rather than whatever is on `PATH`. fvm resolves `.fvmrc` by walking up from the current directory, so this works from `app/` too. Point your IDE at `<repo>/.fvm/flutter_sdk`.

To move the project to a new SDK, change `.fvmrc`, install that SDK, and record the reason in `decisions.md`.

## Makefile targets

Every target runs from the repository root. Without `make`, run the command in the second column (from `app/` unless it starts with `python`).

| Target | Does | Spelled out |
| --- | --- | --- |
| `make content` | Excel → content.db, verified, copied to the asset with its manifest | `python tools/excel_to_sqlite.py`, `python tools/verify_content.py`, then copy `content/build/content.db` and `content_manifest.json` to `app/assets/db/` |
| `make content-diff` | what changed since the committed asset; run before `make content` | `python tools/content_manifest.py app/assets/db/content_manifest.json content/build/content_manifest.json` |
| `make gen` | the content-schema mirror, the drift migration helpers, then build_runner | the generation block in *First run* |
| `make gen-watch` | build_runner in watch mode | `dart run build_runner watch --delete-conflicting-outputs` |
| `make schema-dump` | capture the current schema as a fixture; run after bumping `schemaVersion` (it refuses to overwrite one) | `dart run drift_dev schema dump lib/data/db/app_database.dart drift_schemas/`, then `python tools/trim_schema_fixture.py` |
| `make test` | the tools' Python tests, then unit, widget and db tests, without goldens | `python -m pytest tools/tests -q`, then `flutter test --exclude-tags golden` |
| `make goldens-verify` | compare every golden; on one platform only (`test/golden/README.md`) | `flutter test test/golden` |
| `make goldens` / `make update-goldens` | rewrite **every** golden. Prefer updating the goldens of the files you changed (`testing.md`) | `flutter test test/golden --update-goldens` |
| `make lint` | analyzer and formatter check, as CI runs them | `dart analyze --fatal-infos` (no path arguments, and not `flutter analyze`: ADR 18), then `dart format --output=none --set-exit-if-changed .` |
| `make format` | apply the formatter | `dart format .` |
| `make release-android` / `make release-ios` | see `release.md` | `flutter build appbundle` / `flutter build ipa`, both `--release --obfuscate --split-debug-info=build/symbols` |
| `make clean` | remove build output | `flutter clean`, and delete `content/build/` |

## Project conventions checklist for a new screen

1. Read its guide in `docs/04-screens/`. If something is missing, update the guide first.
2. Create `lib/features/<feature>/<screen>_screen.dart`, with the screen's providers at the top of that file (`state-management.md`), and any feature widgets beside it. Today is the one exception: its providers are in `today_providers.dart`.
3. Add the typed route in `lib/router/routes.dart` and the navigation entry in `docs/01-architecture/navigation.md` if new.
4. Use only `DpSurface`, tokens and `Adaptive*` widgets — no raw colours, no direct Material/Cupertino chrome.
5. Copy in ARB (`lib/l10n/app_en.arb`, `app_bn.arb`); German content from the DB. Every key needs an `@key` description — `test/l10n_test.dart` fails without one, and also fails on a hard-coded string in a `Text(...)`, `tooltip:`, `label:`, `hintText:` or `semanticsLabel:` position. A literal that is genuinely not copy is marked `// ponytail: allow-literal`.
6. Tests: unit for logic, widget for behaviour (FR IDs in test names), goldens for light/dark/glass.
7. PR template asks for: docs updated · tests · goldens · migration (if DB changed) · licence check (if a package was added).
