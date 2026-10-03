# On-device translation (optional)

**Hy-MT2-1.8B, Q4_K_M, on stock llama.cpp through `llamadart`** (the owner's decision on #533, 2026-09-30; ADR 30, #154). It is an optional download, offered in every build, and translation is off until the learner turns it on (`mt_enabled = 0`).

## The model

- **Pinned:** [`tencent/Hy-MT2-1.8B-GGUF`](https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF) at revision `a0c709d9fac510f2c807aa3af52872340dc37a4a`.
  - The file is `Hy-MT2-1.8B-Q4_K_M.gguf`: 1,133,080,448 bytes, sha256 `dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699`.
  - Architecture `hunyuan-dense`, stock tensor types only, so stock llama.cpp loads it. (The repository's 1.25-bit build needs an unmerged llama.cpp change and a fork, so it isn't used.)
- **Manifest:** the entry keeps the id `hymt` (so its folder is `<appSupport>/models/hymt/`), named *Hy-MT2 translation*, licence Apache-2.0, `disables: mt_enabled`. It has no `region_excluded`.
- **Offered in every build.** The licence is Apache-2.0: not gated, no regional exclusions, no NOTICE file. So the `ENABLE_HYMT_DOWNLOAD` build flag of ADR 9 and its EU/UK/KR reasoning are gone.
- **Only on a phone with 4 GB of memory** (a spec gap filled on #154, the lead's call, H-3441).
  - **The line:** `ActivityManager.MemoryInfo.totalMem` of at least 3.5 GiB (`HyMtTranslator.memoryFloor`), since a "4 GB" phone reports 3.6 to 3.8 GiB, the kernel and the modem keeping the rest. On iOS it's `ProcessInfo.physicalMemory`.
  - **Asked once,** over `sogda/storage` (`DeviceStorage.memory`, `translationFitsProvider`). A phone that won't say is offered, as the space check lets it download.
  - **Below the line:** M4's card is *Not available* and says it needs a phone with 4 GB of memory, with no *Download* (FR-M4-04). M3's switch can't be turned on, and its row says the same, so R1's, W1's and T5's entry points, which follow `mt_enabled`, never show.
  - **Why:** on a 2 GB phone one translation took minutes (below).
- **The download is the voice's** (`model-manager.md`): pinned URL and sha256, the space check, the *Wi-Fi only* switch, and the swap into place. Two models can now download side by side:
  - deleting one never touches the other's download in flight (its partial file, its records);
  - a new attempt while another model downloads joins that one's notification, so the shade keeps one for both.
- **Deleting the model** turns `mt_enabled` off (FR-M4-03) and releases the engine.

## The binding

- **`llamadart` ^0.9.0.** It pins `llamadart-native` v0.5.0, which is llama.cpp `7fe450e1` and has `LLM_ARCH_HUNYUAN_DENSE`.
- **CPU backend only** (ADR 27's `hooks: user_defines: llamadart:` block, back): `llamadart_native_runtimes: llama_cpp` and, on Android, `llamadart_native_backends: [cpu]`. Without it the hook also bundles Vulkan and LiteRT-LM.
- **The cost** is llama.cpp's CPU libraries in every APK (13 libraries, `libmtmd` among them): the arm64 APK measured 89.19 MB with them on 2026-10-03, against 66.24 MB on main without them, so +22.95 MB (#154; ADR 29 had measured 21.6 MB), and the perf baseline moved with it.
- **No isolate of our own:** llamadart's llama.cpp backend runs the model in its own worker isolate, so a translation never blocks the UI.
- **`ModelParams`:**
  - `contextSize: 1024`. A sentence and its translation fit, and the default 4096 would hold four times the cache in memory.
  - `preferredBackend: cpu`.
  - `useMmap: true`, the default: the 1.1 GB file is mapped, not copied into memory.

## The prompt

The model card's, with **no system prompt**. It goes in as the user message, through the GGUF's own chat template (`LlamaEngine.create`):

```
Translate the following text into {target_lang}. Note that you should only output the translated result without any additional explanation:

{source_text}
```

- `{target_lang}` is the full English name: German, English, Bengali, Russian or Polish.
- **Sampling, as the card recommends:** temperature 0.7, top_p 0.6, top_k 20, repetition penalty 1.05. At most 256 new tokens.
- **The output is trimmed.** An empty result is no result: `translate` returns null, and nothing is cached.

## Directions

German into each meaning language the app offers (en, bn, ru, pl), and each of them into German. `Translator.translate(text, from:, to:)` takes any pair; the app asks only these eight.

## The engine's life

- **`translatorProvider`** gives `HyMtTranslator` (`hymtTranslatorProvider`, kept alive). While `mt_enabled` is off or the model isn't ready on the phone, it answers null, as `UnavailableTranslator` does, so nothing is cached then; a test without a model can still use `UnavailableTranslator`.
- **Loaded on the first translation,** not at launch. It stays loaded for the next one. **Measured** (#154's device check, emulator-5558, 2 GB of RAM): R1's two lines took 2 to 5 minutes, cold or warm, even right after a reboot. The 1.1 GB mapping can't stay resident beside Android in 2 GB, so each token reads weights from flash again (81,000 major page faults in 25 s). It's memory, not threads (llama.cpp picks the cores). That's why there's a memory floor (above). A phone with room for the mapping is timed in #154's PR.
- **Released** under memory pressure and when the app goes to the background, as the voice is (`VoiceRelease`). Also when the model is deleted. A release doesn't wait: the translation under way is stopped (llamadart's `cancelGeneration`, or before it starts when the cancel came during the load), and those waiting are dropped. Each answers null, since a phone short of memory can't wait minutes for 1.1 GB to go.
- **One at a time,** in the order asked. A translation nobody waits for any more is dropped while it waits, or stopped while it runs, and answers null, so nothing half-done is cached. That's a line off the screen (`translationOfProvider` disposed: R1's sheet closed, T5's sheet gone), or W1 left (`ExampleTranslations` disposed). So a learner's next *Translate* never waits behind translations they've walked away from.
- **Reloaded** when a new download of it lands.
- **A failure answers null:** a load that fails, memory gone, a broken file. The engine is let go, so the next translation loads it again, and nothing is cached. It's never an error, which W1's unawaited call would never catch.
- **A time limit of 60 s a translation** (`HyMtTranslator.limit`). Past it, the translation is stopped and the screen hears null at once. The next one still waits for the stop, so two never run side by side.

## The cache

`translation_cache`, keyed by (`src_lang`, `tgt_lang`, `src_text`, `model`).
- **`model` is `hymt2-1.8b-q4km`,** so nothing an older or another model wrote is read back.
- **A second ask doesn't run the model.**
- **It's a cache,** so it isn't exported or restored (`user-database.md`), and a reset clears it.

## Where it appears

- **W1 *Translate*** (FR-W1-05):
  - it's offered when translation is on and the course lacks example lines in one of the learner's **chosen meaning languages**: the first such language, first or second, and it fills the lines missing there into it;
  - today that means Bangla, since the course has no Bangla example lines. So an English-then-Bangla learner gets Bangla, as before;
  - an English, Polish or Russian learner with no Bangla chosen already sees every example in their language, so isn't offered it.
- **T5's word tap** (FR-T5-03): a word that isn't in the course shows its translation into the first meaning language, above the Duden link.
- **R1's *No results*:**
  - an extra action, *Translate «…»*;
  - a query can be German or the learner's own language, so it shows both: German into the first meaning language, and that language into German.

## The licence

- **Apache-2.0.** The model repository's licence text ships as `assets/licences/Hy-MT2-Apache-2.0.txt`.
- **M8's Models row** reads *Hy-MT2 (1.8B) — Apache-2.0*.
- **What goes:** the region note, the Tencent HY Community License text and `modelsHymtGated`.
