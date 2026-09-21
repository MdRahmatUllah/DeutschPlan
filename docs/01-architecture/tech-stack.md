# Tech stack and package decisions

Verified against pub.dev and the Flutter release notes in September 2026. Pin the versions below in `pubspec.yaml`; upgrade deliberately, one package at a time, with a note in `05-dev-guide/decisions.md`.

## SDK

| | Version | Why |
| --- | --- | --- |
| Flutter | **3.47.x** (stable, Aug 2026) | Latest stable; Impeller everywhere; standalone design packages at 1.0. Enterprises may stay on 3.44.x — do not go older than that. |
| Dart | 3.13.x (ships with 3.47) | Records, patterns, macros-free codegen via build_runner. |
| Android | minSdk 26, targetSdk latest, AGP 9, 16 KB page-size compliant native libs | Required by Google Play for new uploads. |
| iOS | 16.0+ | Required by `flutter_onnxruntime`; Swift Package Manager is the default dependency manager since Flutter 3.44. |

## Design system packages (new in 3.47)

Flutter 3.47 moved Material and Cupertino into `package:material_ui` and `package:cupertino_ui` (both 1.0.x). The in-SDK imports are deprecated from the November 2026 release and removed in 2027. **This project starts on the standalone packages**:

```yaml
material_ui: ^1.0.1
cupertino_ui: ^1.0.0
```

Import `package:material_ui/material_ui.dart` and `package:cupertino_ui/cupertino_ui.dart`; never `package:flutter/material.dart`. If a dependency still uses the old imports, enable `MaterialUiCompatibilityBridge` at the root (documented in the 3.47 release notes) and file an issue upstream; remove the bridge as soon as the dependency migrates.

## Core packages

| Concern | Package | Version | Rationale |
| --- | --- | --- | --- |
| State / DI | `flutter_riverpod` + `riverpod_annotation` + `riverpod_generator` | 3.4.x / 3.x | Riverpod 3 is stable; codegen gives typed, auto-disposed providers and `Notifier`/`AsyncNotifier`; offline-first fits its caching model. |
| Routing | `go_router` | 18.x | `StatefulShellRoute.indexedStack` for the four tabs with preserved state; typed routes via `go_router_builder`; deep links. |
| Database | `drift` + `drift_flutter` + `drift_dev` | 2.35.x | Type-safe SQL, migrations, reactive `Stream` queries, background isolate, **FTS5 helpers in the Dart API** (2.35+). Runs on `sqlite3` 3.x. |
| SQLite binaries | `sqlite3_flutter_libs` | latest 0.5.x compatible with drift 2.35 | Ships a current SQLite build with FTS5 (incl. trigram tokenizer) on Android/iOS so the same DB features exist on both platforms. |
| Immutable models | `freezed` + `freezed_annotation` + `json_serializable` | 3.x / 6.x | Data classes, unions for card kinds and exam sections, JSON for export/import. |
| Localisation | `flutter_localizations` + `intl` | SDK / 0.20.x | ARB files for en/bn; German date on Today. |
| TTS (system) | `flutter_tts` | 4.x | Zero-download fallback voice. |
| TTS (on-device model) | `flutter_onnxruntime` | 1.8.x | Native ONNX Runtime wrapper (ORT 1.22+), 16 KB-page compliant on Android, SPM on iOS. Runs Supertonic 3. |
| Translation model | `llamadart` | latest 0.x | llama.cpp GGUF inference on **both** Android and iOS via native assets; `llama_cpp_flutter` is Apple-only, so it is not used. Loads Hy-MT1.5-1.8B GGUF. |
| Audio playback | `just_audio` | 0.10.x | Plays synthesised WAV/PCM and recorded speaking answers; one shared player. |
| Audio recording | `record` | 6.x | Speaking section recorder (AAC/M4A), mic permission handling. |
| Downloads | `background_downloader` | 9.x | Resumable, background, Wi-Fi-only model downloads with progress notifications on both platforms. |
| Notifications | `flutter_local_notifications` | 19.x | Daily reminder (inexact alarm on Android, UNUserNotificationCenter on iOS). |
| Home-screen widget | `home_widget` | 0.8.x | Bridges to Glance (Android) and WidgetKit (iOS) via a shared JSON snapshot. |
| Background work | `workmanager` | 0.9.x | Nightly plan pre-generation and widget refresh on Android; iOS uses BGTaskScheduler through the same package. |
| Files & sharing | `path_provider`, `file_picker`, `share_plus` | 2.x / 10.x / 11.x | Export/import JSON. |
| Web links | `flutter_custom_tabs` | 2.x | Chrome Custom Tabs / SFSafariViewController for Duden, DWDS, Wiktionary, Linguee, Google. |
| Animation | `flutter_animate` | 4.x | Declarative micro-animations (reveal, shake, ring fill). Confetti is a custom `CustomPainter`. |
| Charts | `fl_chart` | 1.x | Activity bars, retention line on Progress. |
| Permissions | `permission_handler` | 12.x | Mic and notification permissions with rationale. |
| Device info | `device_info_plus` | 11.x | Glass fallback decision (API level, low-end detection). |
| Lints | `flutter_lints` + `riverpod_lint` + `custom_lint` | latest | Enforced in CI. |
| Tests | `flutter_test`, `mocktail`, `drift` in-memory DB, `golden_toolkit` (or `alchemist`) | latest | Unit, widget, golden (three themes) and integration tests. |

## Rejected alternatives (and why)

| Considered | Rejected because |
| --- | --- |
| Parsing `.xlsx` on device | No formula evaluation, slow, large. Excel stays an authoring format; the pipeline compiles it. |
| Raw `sqlite3` package without drift | Works (the prototype used it) but loses typed queries, migrations and reactive streams; drift wraps the same engine. |
| Isar / Hive / ObjectBox | No FTS5, no SQL joins across content and user data, weaker migration story. |
| `sqflite` | No FTS5 guarantee on iOS, no isolate-friendly API, fewer features than drift. |
| Bloc | Riverpod 3 gives the same testability with less ceremony and better async caching for an offline app. |
| `llama_cpp_flutter` | iOS/macOS only. |
| Cloud TTS / translation | Violates the privacy promise. |

## Licences to ship in About → Licences

Flutter packages (auto-collected by `LicenseRegistry`), Supertonic 3 (OpenRAIL-M, model) and its sample code (MIT), Hy-MT1.5 (Tencent HY licence — **territorial restriction; verify before enabling downloads in the EU/UK/KR**), Inter and Noto Sans Bengali (OFL 1.1).
