# Feature spec: Firefox Translations (on-device translation, Standard tier)

| | |
|---|---|
| **Product** | Sogda (German A1–C2; Bangla and Polish meaning languages) |
| **Target release** | Next release after the current Hy-MT2 release |
| **Status** | Planned — specification |
| **Owner** | Product: Maruf · Engineering: app team |
| **Related** | Hy-MT2 translation (current release) · PR #534 (offline translator research) · Issue #1070 (Model manager Hy-MT card) · ADR 9 (translation) |

---

## 1. Summary

Add **Firefox Translations** — Mozilla's on-device neural translation models, run by the Bergamot engine — as a second translation engine next to Hy-MT2.

The two engines become two tiers in the Model manager:

| Tier | Engine | Download | Character |
|---|---|---|---|
| **Standard** (new, default) | Firefox Translations (Bergamot) | ~17–35 MB per direction, a few per language | Small, fast, works on every supported phone |
| **High quality** (current) | Hy-MT2 1.8B | ~440 MB (1.25-bit) | Larger, higher quality, optional |

Both run fully on the phone. Nothing the learner translates leaves the device.

## 2. Why

1. **Size.** Hy-MT2 is ~440 MB. Many learners in our core markets (Bangladesh, India, Egypt, migrants on mid-range phones) won't download that. Bergamot gives useful translation for a few tens of megabytes.
2. **Speed and memory.** Bergamot is a compact neural MT engine; a model uses roughly 50 MB of RAM and translates a sentence in milliseconds on desktop. It runs well on low-end Android phones, where a 1.8B model struggles.
3. **Licence certainty.** Models are MPL-2.0 (© Mozilla) and the engine is MPL-2.0 / MIT, with no territorial restriction. This gives Sogda an engine that is unambiguously usable everywhere, including the EU, independent of how Hy-MT2's licensing evolves.
4. **Language coverage that matches our plan.** Firefox Translations supports German, English, Bangla and Polish today, plus many likely future meaning languages (Arabic, Hindi, Turkish, Ukrainian, Indonesian, …).
5. **Proven on Android.** Firefox for Android ships these models, and open-source Android apps already bundle the Bergamot engine for on-device translation.

## 3. Goals and non-goals

**Goals**
- Learners can translate German text into their meaning language(s) and back, offline, with a small download.
- Standard tier is the default; High quality (Hy-MT2) stays available as an upgrade.
- Adding a new meaning language only needs a manifest entry and model files (see the language registry spec).

**Non-goals**
- Replacing course content. Course meanings and example translations always come from the reviewed content database. Machine translation is an on-demand helper, always labelled.
- Translating whole documents, camera/OCR translation, or speech translation (not in this release).
- Cloud fallback. There is none, by design.

## 4. Where translation appears in the app

The same entry points as Hy-MT2; the active engine is chosen by the Translator service (§7.4).

| Screen | Action | Direction |
|---|---|---|
| W1 Word detail | *Translate* — translates the example sentences into the meaning language(s) | DE → EN / DE → home |
| T5 Practice sentences | Tap a word that isn't in the course → mini sheet with a machine translation | DE → EN / DE → home |
| R1 Search — no results | *Translate "…"* — shows a machine translation of the query, plus *Add as my word* | DE → EN / home; EN or home → DE when the query isn't German |
| R2 Add my word | *Suggest meaning* fills the Meaning field from a machine translation | DE → EN / home |
| L14 Exam review / L9 Quiz result | *Translate* on an explanation sentence | DE → EN / home |

Rules for every entry point:
- **FR-MT-01** Machine output is always marked with a small *Machine translation* label and the engine name (*Standard* or *High quality*).
- **FR-MT-02** Machine output never overwrites course content, never feeds answer checking, and is never used as a quiz or exam answer key.
- **FR-MT-03** If no translation engine is installed, the action shows *Download translation (about 35 MB)* and opens the Model manager.
- **FR-MT-04** If the needed language pair isn't installed, the action offers exactly the missing download, with its size.

## 5. Languages and directions

Mozilla trains every model to or from English. Any pair without English is translated through English (pivot).

| Need | Models used | Notes |
|---|---|---|
| DE → EN | de→en | direct |
| EN → DE | en→de | direct |
| DE → BN | de→en + en→bn | pivot through English |
| BN → DE | bn→en + en→de | pivot; used for Bangla search queries |
| DE → PL | de→en + en→pl | pivot |
| PL → DE | pl→en + en→de | pivot |

**Install bundles** (what the learner downloads, per their meaning-language choice):

| Learner's meaning choice | Bundle | Approx. download (tiny models) |
|---|---|---|
| English only | de→en, en→de | ~35 MB |
| English + Bangla, or Bangla only | de→en, en→de, en→bn, bn→en | ~70 MB |
| English + Polish, or Polish only | de→en, en→de, en→pl, pl→en | ~70 MB |

Sizes are planning estimates; the manifest (§7.2) holds the exact numbers. Where Mozilla ships both a *tiny* and a *base* model for a direction, v1 uses *tiny* (or the *Release Android* build where available); *base* can be offered later as an option.

**Future languages:** any language Mozilla releases in **both** directions (xx→en and en→xx) can be added by manifest. Languages released in one direction only are not offered.

## 6. User experience

### 6.1 Model manager (M4) — two tiers

```
Translation
┌──────────────────────────────────────────────┐
│ Standard · Firefox Translations     ✓ Ready  │
│ German ⇄ English · English ⇄ Bangla           │
│ 70 MB · Mozilla Public License 2.0 →          │
│ [ Delete · free 70 MB ]   [ Add a language ]  │
└──────────────────────────────────────────────┘
┌──────────────────────────────────────────────┐
│ High quality · Hy-MT2 1.8B                    │
│ Better for long or tricky sentences           │
│ 440 MB · licence →          [ Download ]      │
└──────────────────────────────────────────────┘
Active engine:  ( • ) Standard   (   ) High quality
```

- **FR-MT-10** The Standard card lists installed directions in plain words ("German ⇄ English"), the total size, the licence link, *Delete*, and *Add a language* (offers bundles for the other meaning languages).
- **FR-MT-11** States per bundle: Not downloaded · Downloading n % · Verifying · Ready · Update available · Failed (*Retry*) · Not enough space (shows the shortfall).
- **FR-MT-12** *Active engine* choice appears only when both tiers are installed. Default: High quality if installed, otherwise Standard. The learner can override.
- **FR-MT-13** Deleting the active engine falls back to the other one if installed; otherwise translation is turned off and entry points show FR-MT-03.
- **FR-MT-14** This replaces the disabled Hy-MT card noted in issue #1070.

### 6.2 Onboarding and Settings

- **FR-MT-20** Onboarding page 5 adds an optional card: *"Offline translation, about 70 MB — translate any German sentence on your phone."* with *Download* / *Later*. The size shown matches the learner's meaning-language choice.
- **FR-MT-21** Settings → Translation: switch *On-device translation*, row *Engine* (Standard / High quality), row *Download on Wi-Fi only* (default on), link to the Model manager.
- **FR-MT-22** When the learner changes their meaning language, Sogda offers the matching Standard bundle if translation is on.

### 6.3 Translation sheet (shared component)

- Source text (German) with a play button, then the translation for each enabled meaning language (EN first, then home language), each with *Copy*.
- Footer: *Machine translation · Standard (Firefox Translations)* and, if High quality is installed, *Try High quality* to re-translate with Hy-MT2.
- Loading: a thin progress line if translation takes more than 150 ms; never a blocking spinner.
- Errors: *"Couldn't translate this. Try again."* with *Retry*; nothing is shown as a translation if the engine fails.

## 7. Technical design

### 7.1 Components

| Component | Responsibility |
|---|---|
| `sogda_bergamot` (new Flutter FFI plugin) | Wraps the Bergamot translator (C++) for Android and iOS: load model, translate batch, unload |
| `BergamotTranslator` (Dart) | Implements the existing `Translator` interface; handles pivoting, batching, caching |
| `TranslatorService` | Chooses the engine (Hy-MT2 or Bergamot) per the setting and availability; single entry point for screens |
| `ModelManager` | Downloads, verifies, installs, updates and deletes model bundles for both tiers |
| `translation_cache` (existing table) | Stores results keyed by (source text, source lang, target lang, engine, model version) |

### 7.2 Model manifest

A versioned JSON manifest shipped in the app (`assets/models/bergamot_manifest.json`) and optionally refreshed from our own server.

```json
{
  "manifest_version": 1,
  "engine": "bergamot",
  "source_registry_date": "2026-09-25",
  "directions": [
    {
      "id": "de-en",
      "src": "de",
      "trg": "en",
      "variant": "tiny",
      "version": "1.0",
      "files": [
        { "name": "model.deen.intgemm.alphas.bin", "size": 17140736, "sha256": "…" },
        { "name": "lex.50.50.deen.s2t.bin",        "size": 3088008,  "sha256": "…" },
        { "name": "vocab.deen.spm",                "size": 797501,   "sha256": "…" }
      ],
      "url_base": "https://models.sogda.de/bergamot/1.0/de-en/",
      "licence": "MPL-2.0",
      "attribution": "Mozilla Firefox Translations models, © Mozilla"
    }
  ],
  "bundles": {
    "en": ["de-en", "en-de"],
    "bn": ["de-en", "en-de", "en-bn", "bn-en"],
    "pl": ["de-en", "en-de", "en-pl", "pl-en"]
  }
}
```

(File names and sizes above are illustrative; the build script fills real values.)

- **FR-MT-30** Every file is verified against size and SHA-256 before it is activated. A failed check deletes the file and shows *Failed · Retry*.
- **FR-MT-31** Models are **mirrored on our own host** (e.g. `models.sogda.de` or GitHub Releases) at pinned versions. We never download directly from Mozilla's internal endpoints at runtime, so a change on their side can't break the app.
- **FR-MT-32** A newer model set is a new manifest version. Installed models keep working until the learner accepts the update.

### 7.3 Native engine

- Build `bergamot-translator` (from `mozilla/translations`) with Marian NMT for **Android** (arm64-v8a, armeabi-v7a; x86_64 for emulators only) and **iOS** (arm64 device, arm64 simulator) as an xcframework, using the same configuration as Firefox for Android for the ARM backend.
- Expose a small C API to Dart via `dart:ffi`: `bgt_load(model_paths) → handle`, `bgt_translate(handle, texts[]) → texts[]`, `bgt_unload(handle)`.
- Run all translation on a background isolate; the UI isolate never blocks.
- Respect per-ABI packaging (see issue #1070): the AAB splits per ABI; sideload APKs use `abiFilters`.

### 7.4 Engine selection

```
translate(text, from, to):
  engine = settings.engine            // standard | high
  if engine == high and hymt2.installed and hymt2.supports(from, to): use Hy-MT2
  else if bergamot.installed(from, to): use Bergamot
  else if hymt2.installed: use Hy-MT2
  else: return NotInstalled(missing: bundleFor(from, to))
```

- **FR-MT-40** Bergamot pivots automatically: if no direct model exists for `from→to`, it runs `from→en` then `en→to` inside one call.
- **FR-MT-41** Loaded models are kept in an LRU pool of at most **3 models** (≈150 MB RAM ceiling) and unloaded after 2 minutes idle or when the app is backgrounded.
- **FR-MT-42** Input is split into sentences before translation and joined afterwards; a single call is capped at 1,000 characters.
- **FR-MT-43** Results are cached; the cache key includes engine and model version so updates don't serve stale output.

### 7.5 Performance targets

| Metric | Target (mid-range 2022 Android phone) |
|---|---|
| First translation after model load | < 800 ms |
| Warm single sentence, direct pair | < 150 ms |
| Warm single sentence, pivot pair | < 300 ms |
| RAM per loaded model | ≤ 60 MB |
| Native engine size added to the app | ≤ 8 MB per ABI |

## 8. Quality

Bergamot's tiny models are smaller than Hy-MT2 and will be weaker on long or idiomatic sentences, especially through the English pivot to Bangla.

- **QA-01** Build an evaluation set: 300 sentences from the course (A1–C2, all categories) with reviewed reference translations in English, Bangla and Polish.
- **QA-02** Score Standard and High quality on the set (chrF / COMET) and have a native speaker rate 100 sentences per language on a 1–4 scale.
- **QA-03** Release gate per language: native rating average ≥ 3.0 on A1–B1 sentences. A language below the gate stays available only as *English* translation, not as a home-language translation.
- **QA-04** If Mozilla publishes a quality-estimation model for a direction, show a subtle *low confidence* hint when the score is low.

## 9. Data and privacy

- All translation runs on the device; no text is sent anywhere.
- Network is used only for downloading model files the learner asked for (Wi-Fi only by default).
- Cached translations live in `user.db` and are included in Export (§ M6) only if the learner opts in; Reset clears them.
- The privacy statement on About (M9) adds: *"Translation runs on your phone. The models are downloaded once from Sogda's servers."*

## 10. Licences and attribution

| Item | Licence | Obligation |
|---|---|---|
| Firefox Translations models | MPL-2.0, © Mozilla | Ship licence text and attribution; keep files unmodified (if modified, publish the changed files under MPL-2.0) |
| Bergamot translator | MPL-2.0 | Same; publish any changes to MPL-covered source files |
| Marian NMT | MIT | Include copyright and licence notice |
| SentencePiece and other bundled libraries | Apache-2.0 / MIT / BSD (per library) | Include notices |

- **FR-MT-50** About → Licences (M8) lists all of the above with full licence texts.
- **FR-MT-51** The Model manager card links to the model licence.
- **FR-MT-52** Our mirror stores a `NOTICE` and `LICENSE` beside each model version.

## 11. Testing

| Level | What |
|---|---|
| Unit | Manifest parsing and validation; bundle selection per meaning language; pivot routing; engine selection matrix; cache keys |
| Plugin | FFI load/translate/unload on Android and iOS; concurrent calls; out-of-memory handling |
| Integration | Download → verify → install → translate → delete, including interrupted downloads and bad checksums |
| Device | Low-end Android (2 GB RAM), mid-range Android, recent iPhone: latency and memory against §7.5 |
| Quality | §8 evaluation set per language and engine |
| UI | Goldens for Model manager states (light / dark / glass), translation sheet, onboarding card |

## 12. Rollout

1. **Engine and plugin** — build `sogda_bergamot` for Android and iOS; benchmark on devices.
2. **Model mirror and manifest** — mirror de⇄en, en⇄bn, en⇄pl; build script generates the manifest with sizes and hashes.
3. **App integration** — `BergamotTranslator`, `TranslatorService` selection, Model manager two-tier UI, entry points.
4. **Quality gate** — run §8 for English, Bangla, Polish.
5. **Beta** — closed testing track; collect feedback via *Report a problem* on the translation sheet.
6. **Release** — Standard tier on by default in the Model manager offer; High quality remains optional.

## 13. Risks

| Risk | Mitigation |
|---|---|
| Bangla quality through the English pivot is weak for longer sentences | Quality gate (QA-03); *Try High quality* button; translation limited to short texts |
| iOS build of Bergamot is more work than Android | Start with Android; iOS behind a feature flag until the xcframework passes device tests |
| Mozilla changes model formats | Mirror pinned versions (FR-MT-31); update only by new manifest version |
| App size grows | Engine only ~8 MB per ABI; models are downloads, never bundled |
| Two engines confuse learners | One default (Standard), plain-language labels, *Active engine* shown only when both are installed |

## 14. Open questions

1. Do we offer *base* models (larger, better) as a third option, or keep two tiers only?
2. Should Standard translation also be available for the learner's Writing answers (to check their own text), or stay limited to German → meaning language?
3. Host models on our own server (`models.sogda.de`) or GitHub Releases?
4. Do we bundle de⇄en (~35 MB) inside the app so translation works with zero downloads, or keep everything as a download?

## 15. References

- Mozilla Translations (training pipeline, models, Bergamot): https://github.com/mozilla/translations
- Firefox Translations supported languages: https://www.firefox.com/en-US/features/translate/
- Example of Android on-device use of the models (DictateKeyboard, translation models v1): https://github.com/DevEmperor/DictateKeyboard/releases/tag/translation-models-v1
- Internal research: PR #534 — *which offline translator could bring translation back after v1.0*
- Internal: Issue #1070 — Model manager Hy-MT card
