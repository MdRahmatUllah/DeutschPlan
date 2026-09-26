# On-device translation (optional)

`services/translation/hy_mt_translator.dart` using `llamadart` (llama.cpp, GGUF) — off by default (`mt_enabled = 0`).

- Model: Hy-MT1.5-1.8B, one build: Q4_K_M (`HY-MT1.5-1.8B-Q4_K_M.gguf`, ~1.1 GB, from `tencent/HY-MT1.5-1.8B-GGUF`), the owner's choice (#409). The repo publishes Q6_K and Q8_0 too, and no 1.25- or 2-bit build. It is downloaded via `background_downloader` to `<appSupport>/models/hymt/`, checksum-verified, Wi-Fi-only switch.
- Prompt: the model's documented translation template with source/target language names; DE→EN, DE→BN, EN→DE. Max 256 tokens, greedy decoding, run in an isolate; results cached in `translation_cache`.
- Where it appears: Word detail *Translate* (examples into the meaning language), Practice sentences word tap for words not in the course, Search "no results" as an extra action.
- **Licence gate:** the Tencent HY licence excludes the EU, UK and South Korea. The Model manager shows the licence text and the download button is controlled by a build flag `ENABLE_HYMT_DOWNLOAD`; v1.0 ships with it **off in every build** (ADR 9, #173): a single store build can't be kept out of those regions. A licence-clean alternative is #494. Deleting the model turns `mt_enabled` off.

## After v1.0: a translator that can ship everywhere (#494)

Desk research, 2026-09-26, from the model cards and terms cited. Nothing here ships in v1.0; the owner decides whether to pursue it (#533).

| Option | de→en · en→de · de→bn | Licence | Size | Offline | Flutter path |
|---|---|---|---|---|---|
| **Firefox / Bergamot tiny** ([models](https://github.com/mozilla/firefox-translations-models/tree/main/models/tiny)) | de↔en; en↔bn, so de→bn goes through English | MPL-2.0 ([licence](https://raw.githubusercontent.com/mozilla/firefox-translations-models/main/LICENSE)) | ~17 MB a direction: ~51 MB for de→en, en→de, en→bn | Yes, bundled | A new native library behind a platform channel: DuckDuckGo's [translate-kit](https://github.com/duckduckgo/translate-kit) (Apache-2.0, an Android AAR and an iOS package) |
| **Opus-MT** (Helsinki-NLP) on the app's ONNX Runtime | [de-en](https://huggingface.co/Helsinki-NLP/opus-mt-de-en), [en-de](https://huggingface.co/Helsinki-NLP/opus-mt-en-de); en→bn only through [en-inc](https://huggingface.co/Helsinki-NLP/opus-mt-en-inc)/en-mul; one direct de→bn, [tc-bible-big](https://huggingface.co/Helsinki-NLP/opus-mt-tc-bible-big-deu_eng_fra_por_spa-inc) | Apache-2.0; en-de CC-BY-4.0 (a credit) | ~106 MB a direction int8 ([de-en ONNX](https://huggingface.co/Xenova/opus-mt-de-en/tree/main/onnx)); tc-bible-big 959 MB fp32; no ONNX export of the Bengali ones yet | Yes, bundled | `flutter_onnxruntime`, already shipped, plus a Dart SentencePiece tokeniser and our own decoding loop |
| **Google ML Kit** ([languages](https://developers.google.com/ml-kit/language/translation/translation-language-support)) | de, en, bn; de→bn through English | [Google APIs terms](https://developers.google.com/terms), usage metrics to Google ([ML Kit terms](https://developers.google.com/ml-kit/terms)), "Translate with Google" attribution ([rules](https://docs.cloud.google.com/translate/attribution)) | ~30 MB a language | Only after a download from Google; can't be bundled ([paths](https://developers.google.com/ml-kit/tips/installation-paths)) | [google_mlkit_translation](https://pub.dev/packages/google_mlkit_translation) (community, MIT) |
| NLLB-200 distilled 600M | direct de→bn | CC-BY-NC, "not for production" ([card](https://huggingface.co/facebook/nllb-200-distilled-600M)) | — | — | Ruled out: non-commercial |
| Argos Translate | de↔en, en↔bn | code MIT; the models' licence unstated | — | — | No mobile runtime |

Reported quality (flores, from the cards): Bergamot tiny en→bn BLEU 19.2, de→en 39.6, en→de 38.8 ([en-bn metadata](https://raw.githubusercontent.com/mozilla/firefox-translations-models/main/models/tiny/enbn/metadata.json)); Opus tc-bible-big deu→ben 11.3 and eng→ben 17.7: going through English beats Opus's direct German→Bengali.

**Recommendation:** the Bergamot tiny models. They're the smallest, their licence is clean everywhere (MPL-2.0 with a credits line in M8), they ship inside the app as the offline promise asks, and their en→bn is the best of the lot. The cost is a native library (translate-kit) behind a platform channel, where Opus-MT would reuse ONNX Runtime at three times the size with weaker Bengali; Opus-MT is the fallback. ML Kit is the least work but breaks the offline promise (a download from Google), puts Google's branding in the UI and sends it metrics. The Bergamot repository was archived on 2025-12-15, its models moving elsewhere: where they live now is part of the implementation issue.

**Before an implementation issue** (if the owner agrees): a quality check on about twenty sentences from `content.db`, A1 to C1, in the three directions, the two-hop de→bn beside Opus's direct model. It needs reference translations a native Bangla speaker checks, chrF (sacrebleu) and a 1–5 adequacy rating, a look at what the course teaches (du/Sie, case, separable verbs, register), and latency and memory on the emulator.
