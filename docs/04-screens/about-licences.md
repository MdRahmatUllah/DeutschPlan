# M9 · About & privacy · M8 · Licences

**Prototype.** `About`, `Licences`.

**Reached from.** M1 → About; M9 → Licences.

**About layout.** App mark; "Version 1.0.0 (build 41) · content 2026.09 · 21 Sep 2026"; **Privacy**: "Your progress stays on this phone. DeutschPlan has no account, no server and no analytics. The internet is used only when you open a web search link or download a model."; **Open-source and model licences** → M8; **Contact** address; **Content**: "5,594 words · 182 grammar topics · 11,188 sentences" (from `meta`).

**Licences layout.** Sections Models (Supertonic 3 — OpenRAIL-M; Hy-MT 1.5 (1.8B) — Hy-MT licence), Fonts (Inter, Noto Sans Bengali — OFL 1.1), Packages (from `LicenseRegistry`).

**Functional requirements**
- FR-M9-01 Version/build from `package_info_plus`; content version and counts from `c.meta`.
- FR-M8-01 Model and font licence texts are bundled as assets and shown in full.

**Tests.** counts equal the content manifest.

## Details #150 settles

- **The version line.** "Version 1.0.0 (build 41) · content 2026.09 · 21 Sep 2026".
  - The app's version and build come from `package_info_plus`.
  - The course's release is `meta.content_version` cut to year and month (`202609251045` → 2026.09).
  - The date is `meta.built_at`, written as M1 writes a day.
- **The counts.** `meta` keeps only the word count, so `ContentDao.facts()` counts `words`, `grammar_topics` and `word_examples`, as the pipeline's manifest does. A test holds them equal to `content_manifest.json` (FR-M9-01).
- **Contact** opens the project's new-issue page on GitHub: the report's destination (#100), since the app has no server or address. An address is the owner's to give (the artboard's is `hello@[YOUR DOMAIN]`).
- **Content** leads nowhere. The artboard draws a chevron, but the spec gives no destination, so the row shows no chevron.
- **Models** (FR-M8-01): the licences are bundled unchanged, as their makers publish them (only git's line endings differ), in `assets/licences/`:
  - Supertonic 3 is under the BigScience OpenRAIL-M licence (`Supertone/supertonic-3`).
  - Hy-MT 1.5 (1.8B) is under the **Tencent HY Community License** (`tencent/HY-MT1.5-1.8B`). It is named that, not "Hy-MT licence" as the artboard has it. Its text excludes the EU, the UK and South Korea, which the model manager's region gate follows.
- **Fonts:** Inter and Noto Sans Bengali, SIL OFL 1.1, bundled.
- **Packages** come from Flutter's `LicenseRegistry`, each package once, in name order. The registry gives texts, not names, so the line under a package is the licence its text is (MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0, MPL-2.0, OFL-1.1, ISC), else "Licence".
- **A licence's text** opens in full in a sheet that scrolls: M8 has no page per licence, so the route table is unchanged.
