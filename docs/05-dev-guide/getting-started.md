# Getting started

## Prerequisites

- Flutter 3.47.x stable (`flutter --version`), Dart 3.13.x. The exact version is pinned in `.fvmrc` at the repository root (currently **3.47.5**, which ships Dart 3.13.4) so every developer and CI build on the same SDK — see *Using fvm* below.
- Android Studio (latest) with SDK 35, NDK r27; Xcode 16+ with iOS 16 simulator; CocoaPods is no longer required (Swift Package Manager is default since Flutter 3.44).
- Python 3.11+ with `openpyxl` for the content pipeline.
- `make` (targets below).

## First run

```bash
git clone … deutschplan && cd deutschplan
fvm install                     # picks the SDK from .fvmrc
make content                    # Excel → content.db → app/assets/db/content.db
cd app
flutter pub get
dart run build_runner build -d  # riverpod, freezed, drift, go_router codegen
flutter analyze && flutter test
flutter run
```

## Using fvm

The SDK version lives in `.fvmrc` at the repository root and is the single source of truth. `.fvm/` (the downloaded SDK and its symlink) is git-ignored.

```bash
dart pub global activate fvm     # once per machine
fvm install                      # from the repository root; reads .fvmrc
fvm flutter --version            # should print 3.47.5 / Dart 3.13.4
```

Prefix Flutter and Dart commands with `fvm` (`fvm flutter test`, `fvm dart run build_runner build -d`) so they use the pinned SDK rather than whatever is on `PATH`. fvm resolves `.fvmrc` by walking up from the current directory, so this works from `app/` too.

Point your IDE at `<repo>/.fvm/flutter_sdk` as the Flutter SDK path. To move the whole project to a new SDK, change `.fvmrc`, run `fvm install`, and record the reason in `decisions.md`.

## Makefile targets

| Target | Does |
| --- | --- |
| `make content` | `python tools/excel_to_sqlite.py` + `verify_content.py` + copy asset + write manifest |
| `make gen` | build_runner (watch with `make gen-watch`) |
| `make test` | unit + widget + db tests |
| `make goldens` | update golden files for all three themes (review the diff!) |
| `make lint` | `flutter analyze`, `dart format --set-exit-if-changed`, `custom_lint` |
| `make release-android` / `make release-ios` | see `release.md` |

## Project conventions checklist for a new screen

1. Read its guide in `docs/04-screens/`. If something is missing, update the guide first.
2. Create `lib/features/<feature>/<screen>_screen.dart`, `<screen>_providers.dart`, feature widgets.
3. Add the typed route in `lib/router/routes.dart` and the navigation entry in `docs/01-architecture/navigation.md` if new.
4. Use only `DpSurface`, tokens and `Adaptive*` widgets — no raw colours, no direct Material/Cupertino chrome.
5. Copy in ARB (`lib/l10n/app_en.arb`, `app_bn.arb`); German content from the DB.
6. Tests: unit for logic, widget for behaviour (FR IDs in test names), goldens for light/dark/glass.
7. PR template asks for: docs updated · tests · goldens · migration (if DB changed) · licence check (if a package was added).
