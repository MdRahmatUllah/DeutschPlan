# Release

## Versioning
`pubspec.yaml` `version: MAJOR.MINOR.PATCH+BUILD`. Content has its own `content_version` (build timestamp) shown in About; a content-only release bumps PATCH.

## Android (#170)
- **The app id** is `de.sogda.app`, the owner's (ADR 28; it replaced `io.github.rahmatullah.deutschplan`, #170, before the first upload). It can never change once the app is on Play. The Kotlin sources live in `android/app/src/main/kotlin/de/sogda/app/`.
- **Signing.** Release builds use the owner's upload key when `app/android/key.properties` exists. It is gitignored, as are keystores, so it's never committed:
  ```
  storePassword=…
  keyPassword=…
  keyAlias=upload
  storeFile=C:/path/to/upload-keystore.jks
  ```
  Without it, a release build (`assembleRelease`, `bundleRelease`) fails, saying so (#705, the owner's decision), unless it opts in to the debug key: `flutter build apk --release -P allowDebugSigning=true` (flutter's `-P`, `--android-project-arg`, passes it to Gradle), or `ORG_GRADLE_PROJECT_allowDebugSigning=true` in the environment of any Gradle run. The agents' release-mode builds opt in: the device-check APK (`tools/device.py` says so), `tools/perf.py`'s, and `tools/release_android.py`'s without `--require-upload-key`. With `key.properties` there, the upload key signs the build whatever the opt-in says. Play refuses a debug-signed upload anyway.
- **Gradle** comes from the wrapper, pinned to its distribution's SHA-256 (`distributionSha256Sum` in `android/gradle/wrapper/gradle-wrapper.properties`, #705). Gradle refuses a download that doesn't match, and an upgrade takes the new "Complete (-all)" checksum from gradle.org/release-checksums.
- **Build and check:** `python tools/release_android.py`. In an agent's worktree the emulator is held first (an app build takes the lock); the owner's checkout has no lock to take (#707). `--check` checks the last build without building; `--require-upload-key` fails a bundle that isn't signed with the owner's upload key (use it for the build that goes to Play); it doesn't opt in to the debug key, so without `key.properties` Gradle already refuses to build.
  - **Libraries:** `libflutter.so` and `libapp.so` must be in the bundle for every ABI it ships (`armeabi-v7a`, `arm64-v8a`, `x86_64`: the bundle has no ABI filter), so a half-built bundle can't pass the 16 KB check on nothing (#697, #858).
  - It builds with `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols` (plus `-P allowDebugSigning=true` unless `--require-upload-key`), into `app/build/app/outputs/bundle/release/app-release.aab`.
  - **16 KB:** every 64-bit native library in the bundle (`arm64-v8a`, `x86_64`) must have its loadable segments aligned to 16 KB, as Play requires of apps targeting Android 15+. The tool reads the ELF headers itself, and exits 1 on a library that fails.
  - **Key:** it says which key signed the bundle; a debug or unsigned bundle fails only with `--require-upload-key`.
  - **Symbols:** it fails if `app/build/symbols` lacks Dart's arm, arm64 or x64 file (a 32-bit crash needs `app.android-arm.symbols`, #858). Once every check has passed, it copies the folder to `app/build/release-symbols/<version>/`, so a later build (perf.py's writes to `build/perf-symbols`) can't overwrite them; a bundle that failed keeps nothing.
  - It passed on 2026-09-26 with AGP 9.1 and the plugins as pinned: ONNX Runtime, llama.cpp's backends, flutter_tts and the rest. The bundle was 272 MB then, all four ABIs; llamadart's removal (ADR 29) shrinks it, so re-measure at the next release.
- **Symbols.**
  - **Dart's** are in `app/build/symbols`, one file per ABI. `flutter symbolize` needs them to read an obfuscated Dart stack trace, so keep them with each release, **privately**: they hold the real, unobfuscated names, which is why the build warns about "unobfuscated DWARF". A private store, not a public GitHub release.
  - **The plugins' native symbol tables** ride in the bundle (`debugSymbolLevel = "SYMBOL_TABLE"`), and Play symbolicates their crashes from them.
- **Play Console declarations.**
  - **Data safety:** no data collected and none shared. There is no account, no analytics and no ads. Model downloads fetch files and send nothing, and progress stays on the phone (export is the learner's own file; Android backup and device transfer are off, #607). *Report a problem* opens a pre-filled GitHub issue page in the browser, with the card's id, and the learner sends it there, or doesn't.
  - **Permissions**, as the merged manifest has them. `tools/release_android.py` fails when the two differ (#611):
    - `RECORD_AUDIO`: the Speaking exam's recording, asked for on the first Record and kept on the phone.
    - `POST_NOTIFICATIONS`: the daily reminder, asked for when it's switched on, and a model download's progress.
    - `RECEIVE_BOOT_COMPLETED`: reminders scheduled again after a restart.
    - `INTERNET` and `ACCESS_NETWORK_STATE`: model downloads, and their Wi-Fi-only rule.
    - `WAKE_LOCK`: WorkManager keeps the phone awake while a model download or the widget's refresh runs in the background.
    - `VIBRATE`: the reminder notification.
  - **Foreground services:** none, so the Console's foreground-service form doesn't apply. WorkManager and background_downloader declare them, and the app's manifest removes both permissions and their services' types (#611). A download carries on in the background as WorkManager work, paused and resumed by it.

## iOS
**Not in v1.0** (owner, 2026-09-26): v1.0 ships on Android only. iOS waits for a Mac with Xcode: its pipeline (#171) and widget (#161) are in the milestone "Later · after v1.0". The iOS code paths stay tested on Windows (adaptive chrome, the iOS goldens). When a Mac is available:

- Deployment target 16.0; SPM; `flutter build ipa --release`.
- Privacy manifest: no tracking; mic usage string; notifications; background modes `fetch` + `processing` for downloads/widget refresh.
- Widget extension target shares App Group `group.de.sogda.app`.

## Checklist
1. `make lint test goldens-verify` green (not `make goldens`, which rewrites every golden instead of checking it); integration smoke on both platforms.
2. Content rebuilt from the workbooks in `data/`; manifest diff reviewed (`make content-diff`: added/removed/changed words).
3. `python tools/licences.py check` passes (after `flutter pub get` in `app/`). It fails if a bundled model or font licence differs from what its maker publishes, is missing, or has no source listed, and if a font family in pubspec's `fonts:` has no licence text (`<Family without spaces>-*.txt`, #719); `python tools/licences.py update` fetches them again. It also fails if a package ships no LICENSE file, which M8's list (Flutter's `LicenseRegistry`) would silently leave out (#172).
4. `ENABLE_HYMT_DOWNLOAD` stays **off** (ADR 9, #173): the release build passes no `--dart-define=ENABLE_HYMT_DOWNLOAD`, so M4 says Hy-MT is "Not offered in this version of the app" and M3 hides its Translation group (#513). Changing that needs a new ADR 9 entry first.
5. `python tools/release_android.py --require-upload-key` passes (libraries, 16 KB, permissions, the upload key, the symbols); `app/build/release-symbols/<version>/` stored privately.
6. `python tools/perf.py all` and `python tools/perf.py all --profile year` pass: size, frames, search and start against their baselines, on a fresh install and on a year of study (`accessibility-performance.md`, #167, #818). The owner's checkout takes no lock, and perf.py refuses while an agent holds the emulator (#845); an agent holds it first (`team.py device`). Then cold and warm start timed by hand on a real mid-range phone against the absolute budgets.
7. Tag `vX.Y.Z`, with the changelog entry (`CHANGELOG.md`) dated in the tagging commit, store notes in EN and BN (`store-listing.md`, which `tools/tests/test_store_listing.py` holds to Play's limits), and the screenshots beside it.
