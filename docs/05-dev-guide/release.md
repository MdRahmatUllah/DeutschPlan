# Release

## Versioning
`pubspec.yaml` `version: MAJOR.MINOR.PATCH+BUILD`. Content has its own `content_version` (build timestamp) shown in About; a content-only release bumps PATCH.

## Android (#170)
- **The app id** is `io.github.rahmatullah.deutschplan`, the owner's. It can never change once the app is on Play. The Kotlin sources live in `android/app/src/main/kotlin/io/github/rahmatullah/deutschplan/`.
- **Signing.** Release builds use the owner's upload key when `app/android/key.properties` exists. It is gitignored, as are keystores, so it's never committed:
  ```
  storePassword=…
  keyPassword=…
  keyAlias=upload
  storeFile=C:/path/to/upload-keystore.jks
  ```
  Without it, a release build is signed with the debug key, so builds and device checks work before the keystore exists. Play refuses a debug-signed upload.
- **Build and check:** `python tools/release_android.py`, with the emulator held (an app build takes the lock). `--check` checks the last build without building.
  - It builds with `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols`, into `app/build/app/outputs/bundle/release/app-release.aab`.
  - **16 KB:** every 64-bit native library in the bundle (`arm64-v8a`, `x86_64`) must have its loadable segments aligned to 16 KB, as Play requires of apps targeting Android 15+. The tool reads the ELF headers itself, and exits 1 on a library that fails.
  - **Key:** it says which key signed the bundle.
  - It passed on 2026-09-26 with AGP 9.1 and the plugins as pinned: ONNX Runtime, llama.cpp's backends, flutter_tts and the rest. The bundle is 272 MB, all four ABIs.
- **Symbols.**
  - **Dart's** are in `app/build/symbols`, one file per ABI. `flutter symbolize` needs them to read an obfuscated Dart stack trace, so keep them with each release, **privately**: they hold the real, unobfuscated names, which is why the build warns about "unobfuscated DWARF". A private store, not a public GitHub release.
  - **The plugins' native symbol tables** ride in the bundle (`debugSymbolLevel = "SYMBOL_TABLE"`), and Play symbolicates their crashes from them.
- **Play Console declarations.**
  - **Data safety:** no data collected and none shared. There is no account, no analytics and no ads. Model downloads fetch files and send nothing, and progress stays on the phone (export is the learner's own file). *Report a problem* opens a pre-filled GitHub issue page in the browser, with the card's id, and the learner sends it there, or doesn't.
  - **Permissions**, as the merged manifest has them (`aapt2 dump permissions`):
    - `RECORD_AUDIO`: the Speaking exam's recording, asked for on the first Record and kept on the phone.
    - `POST_NOTIFICATIONS`: the daily reminder, asked for when it's switched on.
    - `RECEIVE_BOOT_COMPLETED`: reminders scheduled again after a restart.
    - `INTERNET` and `ACCESS_NETWORK_STATE`: model downloads, and their Wi-Fi-only rule.
    - `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SHORT_SERVICE` and `WAKE_LOCK`: background_downloader carrying a model download on with the app in the background. The foreground-service form in the Console declares it as a download the learner started.
    - `VIBRATE`: the reminder notification.

## iOS
**Not in v1.0** (owner, 2026-09-26): v1.0 ships on Android only. iOS waits for a Mac with Xcode: its pipeline (#171) and widget (#161) are in the milestone "Later · after v1.0". The iOS code paths stay tested on Windows (adaptive chrome, the iOS goldens). When a Mac is available:

- Deployment target 16.0; SPM; `flutter build ipa --release`.
- Privacy manifest: no tracking; mic usage string; notifications; background modes `fetch` + `processing` for downloads/widget refresh.
- Widget extension target shares App Group `group.app.deutschplan`.

## Checklist
1. `make lint test goldens-verify` green (not `make goldens`, which rewrites every golden instead of checking it); integration smoke on both platforms.
2. Content rebuilt from the workbooks in `data/`; manifest diff reviewed (`make content-diff`: added/removed/changed words).
3. `python tools/licences.py check` passes (after `flutter pub get` in `app/`). It fails if a bundled model or font licence differs from what its maker publishes, is missing, or has no source listed; `python tools/licences.py update` fetches them again. It also fails if a package ships no LICENSE file, which M8's list (Flutter's `LicenseRegistry`) would silently leave out (#172).
4. `ENABLE_HYMT_DOWNLOAD` stays **off** (ADR 9, #173): the release build passes no `--dart-define=ENABLE_HYMT_DOWNLOAD`, so M4 says Hy-MT is "Not offered in this version of the app" and M3 hides its Translation group (#513). Changing that needs a new ADR 9 entry first.
5. `python tools/release_android.py` passes (16 KB), signed with the upload key; `build/symbols` stored.
6. `python tools/perf.py all` passes, with the emulator held (`team.py device`): size, frames, search and start against their baselines (`accessibility-performance.md`, #167). Then cold and warm start timed by hand on a real mid-range phone against the absolute budgets.
7. Tag `vX.Y.Z`, changelog entry (`CHANGELOG.md`), store notes in EN and BN (`store-listing.md`, which `tools/tests/test_store_listing.py` holds to Play's limits), and the screenshots beside it.
