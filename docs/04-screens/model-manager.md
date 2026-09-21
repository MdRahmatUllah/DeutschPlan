# M4 · Model manager (Voice & translation)

**Prototype.** `ModelManager`.

**Reached from.** M1, M3 (Voice engine, Translation), T1 voice card, S2 page 5. **Leads to.** —

**Layout.** Storage card "Phone storage · 12.4 GB free of 64 GB · Models: 540 MB". Card **Supertonic 3 voice** "98 MB · OpenRAIL-M licence" · status *Ready* · voice chips Anna / Jonas / Lena with preview play · *Delete · free 98 MB* · *Check for update*. Card **Hy-MT 1.5 translation** "1.25-bit build · 440 MB · licence →" · status *Downloading · 42% · 185 of 440 MB · Wi-Fi* with note "Continues in the background with a system notification · pauses off Wi-Fi" · switch *Wi-Fi only* · *Pause* · option *Better quality · 2-bit, 575 MB*. Footer "Both models run entirely on the phone. Deleting the voice falls back to the phone's German voice; deleting the translation model turns translation off."

**States per model.** Not downloaded · Downloading n % (pausable) · Verifying · Ready · Update available · Failed (*Retry*) · Not enough space (button disabled with shortfall).

**Functional requirements**
- FR-M4-01 Downloads via `background_downloader`: resumable, Wi-Fi-only flag, progress notification, checksum (SHA-256 from the model manifest) verified before activation; partial files never activate.
- FR-M4-02 Model manifest (`assets/models/manifest.json`) lists URL, size, hash, licence per variant; updates compare hashes.
- FR-M4-03 Deleting Supertonic sets `tts_engine = system`; deleting Hy-MT sets `mt_enabled = 0`.
- FR-M4-04 Hy-MT download button is enabled only when build flag `ENABLE_HYMT_DOWNLOAD` is true (licence gate, see `03-domain/translation.md`); the licence link opens the full text.
- FR-M4-05 Voice preview plays "Guten Tag! Ich bin Anna." with the chosen voice.

**Tests.** state machine with a fake downloader; hash failure → Failed; delete side-effects.
