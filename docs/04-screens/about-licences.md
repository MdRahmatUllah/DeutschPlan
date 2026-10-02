# M9 · About & privacy · M8 · Licences

**Prototype.** `About`, `Licences`.

**Reached from.** M1 → About; M9 → Licences.

**About layout.** App mark (the app icon, `SgMark.appIcon` at 60 dp: the brand kit's tiles on the Lagoon square, #602); "Version 1.0.0 (build 41) · content 2026.09 · 21 Sep 2026"; **Privacy**: "Your progress stays on this phone. Sogda has no account, no server and no analytics. The internet is used only when you open a web search link or download a model."; **Open-source and model licences** → M8; **Contact** address; **Content**: "5,069 words · 182 grammar topics · 10,545 sentences" (from `meta`).

**Licences layout.** Sections Models (Supertonic 3 — OpenRAIL-M; Hy-MT2 (1.8B) — Apache-2.0), Fonts (Inter, Noto Sans Bengali — OFL 1.1), Native libraries (ONNX Runtime — MIT, with its third-party notices; llama.cpp — MIT, the translator's runtime, ADR 30; the Android libraries — Apache-2.0; #610; desugar_jdk_libs — GPL-2.0 with the Classpath Exception, #848), Packages (from `LicenseRegistry`).

**Functional requirements**
- FR-M9-01 Version/build from `package_info_plus`; content version and counts from `c.meta`. The app's version shows on its own ("Version 1.0.0 (build 41)") when the course's facts can't be read (#692 ME-13).
- FR-M8-01 Model, font and native-library licence texts are bundled as assets and shown in full.

**Tests.** counts equal the content manifest.

## Details #150 settles

- **The version line.** "Version 1.0.0 (build 41) · content 2026.09 · 21 Sep 2026".
  - The app's version and build come from `package_info_plus`.
  - The course's release is `meta.content_version` cut to year and month (`20260925104512` → 2026.09).
  - The date is `meta.built_at`, written as M1 writes a day.
- **The counts.** `meta` keeps only the word count, so `ContentDao.facts()` counts `words`, `grammar_topics` and `word_examples`, as the pipeline's manifest does. A test holds them equal to `content_manifest.json` (FR-M9-01).
- **Contact** opens the project's new-issue page on GitHub: the report's destination (#100), since the app has no server or address. An address is the owner's to give (the artboard's is `hello@[YOUR DOMAIN]`). A phone that can't open it (no browser) gets a toast saying so, not silence: every web link goes through `openWebProvider`, which answers false rather than throwing (#692 ME-13).
- **Content** leads nowhere. The artboard draws a chevron, but the spec gives no destination, so the row shows no chevron.
- **Models** (FR-M8-01): the licences are bundled unchanged, as their makers publish them (only git's line endings differ), in `assets/licences/`:
  - Supertonic 3 is under the BigScience OpenRAIL-M licence (`Supertone/supertonic-3`).
  - The Supertonic SDK is under MIT (`supertone-inc/supertonic-py`): `supertonic_text.dart` ports its text front end (#172).
  - Hy-MT2 (1.8B) is under **Apache-2.0** (`tencent/Hy-MT2-1.8B-GGUF`), not the Tencent HY Community License of Hy-MT 1.5 that the artboard names: no regional exclusions, so no region gate (ADR 30). Its text ships as `assets/licences/Hy-MT2-Apache-2.0.txt`.
- **Fonts:** Inter and Noto Sans Bengali, SIL OFL 1.1, bundled.
- **Native libraries** (#610): what ships in the APK that no package's LICENSE covers, so Flutter's registry can't list it.
  - **ONNX Runtime** 1.23.0, the Supertonic voice's engine (`libonnxruntime.so`, from Maven through flutter_onnxruntime, whose own LICENSE covers only the plugin): its MIT licence and its `ThirdPartyNotices.txt`, both from the release commit.
  - **The Android libraries** the plugins pull in: AndroidX (core, WorkManager, browser, preference, media), Jetpack Glance, Kotlin and kotlinx, Gson. All are Apache-2.0, so one entry carries that licence (AndroidX's own `LICENSE.txt`).
  - **desugar_jdk_libs** 2.1.5 (#848): the build's `coreLibraryDesugaring`, which flutter_local_notifications needs, compiles OpenJDK's `java.time` and other backports into the release DEX. GPL-2.0 with the Classpath Exception, which lets the app link to it on its own terms; the text ships whole, from `google/desugar_jdk_libs` at the commit that prepared 2.1.5.
- **Collection** is a release step (`release.md`): `tools/licences.py` lists each bundled text's source, and `check` compares them with what the makers publish. It also fails if a package ships no LICENSE file, or if a font family in pubspec's `fonts:` has no licence text (#719).
- **Packages** come from Flutter's `LicenseRegistry`, each package once, in name order. The registry gives texts, not names, so the line under a package is the licence its text is (MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0, MPL-2.0, OFL-1.1, ISC), else "Licence". The registry also carries the build's tools (`analyzer` and its plugins, `build_runner`, `drift_dev`, `riverpod_lint`, `lints`, and theirs), since Flutter collects every package the project resolves, dev dependencies included, and has no switch to leave them out (3.47). They don't ship in the app. Listing a licence too many is harmless, so the list keeps them rather than a generated list of shipped packages to filter by (#1055).
- **A licence's text** opens in full in a sheet that scrolls: M8 has no page per licence, so the route table is unchanged. The sheet lays the text out line by line as it scrolls (#849): ONNX Runtime's notices are 327 KB, which as one text were laid out and painted whole on open. A short licence still hugs its text.
