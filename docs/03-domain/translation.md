# On-device translation (optional)

`services/translation/hy_mt_translator.dart` using `llamadart` (llama.cpp, GGUF) — off by default (`mt_enabled = 0`).

- Model: Hy-MT1.5-1.8B, one build: Q4_K_M (`HY-MT1.5-1.8B-Q4_K_M.gguf`, ~1.1 GB, from `tencent/HY-MT1.5-1.8B-GGUF`), the owner's choice (#409). The repo publishes Q6_K and Q8_0 too, and no 1.25- or 2-bit build. It is downloaded via `background_downloader` to `<appSupport>/models/hymt/`, checksum-verified, Wi-Fi-only switch.
- Prompt: the model's documented translation template with source/target language names; DE→EN, DE→BN, EN→DE. Max 256 tokens, greedy decoding, run in an isolate; results cached in `translation_cache`.
- Where it appears: Word detail *Translate* (examples into the meaning language), Practice sentences word tap for words not in the course, Search "no results" as an extra action.
- **Licence gate:** the Tencent HY licence excludes the EU, UK and South Korea. The Model manager shows the licence text and the download button is controlled by a build flag `ENABLE_HYMT_DOWNLOAD`; keep it off for store builds distributed in those regions until the legal check is done. Deleting the model turns `mt_enabled` off.
