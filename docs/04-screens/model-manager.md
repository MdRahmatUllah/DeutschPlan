# M4 · Model manager (Voice & translation)

**Prototype.** `ModelManager`.

**Reached from.** M1, M3 (Voice engine, Translation), T1 voice card, S2 page 5. **Leads to.** —

**Layout.** Storage card "Phone storage · 12.4 GB free of 64 GB · Models: 540 MB". Card **Supertonic 3 voice** "98 MB · OpenRAIL-M licence" · status *Ready* · voice chips Anna / Jonas / Lena with preview play · *Delete · free 98 MB* · *Check for update*. Card **Hy-MT 1.5 translation** "4-bit build · 1.1 GB · licence →" · status *Downloading · 42% · 454 MB of 1.1 GB · Wi-Fi* with note "Continues in the background with a system notification · pauses off Wi-Fi" · switch *Wi-Fi only* · *Pause*. The artboard's "1.25-bit build · 440 MB" and its option *Better quality · 2-bit, 575 MB* describe builds that don't exist: one build is offered, Q4_K_M (#409), so the card has no build option. Footer "Both models run entirely on the phone. Deleting the voice falls back to the phone's German voice; deleting the translation model turns translation off."

**States per model.** Not downloaded · Downloading n % (pausable) · Verifying · Ready · Update available · Failed (*Retry*) · Not enough space (button disabled with shortfall).

**The download manager, #156** (`services/model_downloads.dart`; the card that draws it is #155):
- **At launch** `attach()` sets one progress notification for every model file ("Downloading models · 2 of 5 files", with a progress bar on Android), listens to the downloader, and calls its `start()`. Tasks the system or the learner killed are scheduled again, and a download that finished while the app was away reports now. A file that finished in an *earlier* session never reports again, so the downloader's records stand in for it: a model whose last file lands after a restart, or which was killed while verifying, still verifies. Running tasks aren't rescheduled at launch.
- ***Wi-Fi only*** is `models_wifi_only`, on by default, and the downloader's rule for every task, running ones included. A queued model under that rule reads as *waiting for Wi-Fi*, the card's "Paused — resumes on Wi-Fi".
- **Progress** is the bytes arrived over the variant's bytes, file by file, and the phase is the files' combined: one failed fails the model, one paused pauses it, one running runs it.
- **Activation:** only when every file of the variant is complete are the checksums read (*Verifying*). The variant is put in place only if every one passes (`ModelRepository.activate`); otherwise the phase is *Failed*, and nothing is in place. A rename that fails (a full disk) is *Failed* too. Either way the model's download records are then cleared, so the next launch doesn't verify it again.
- **Only pinned files are fetched:** `start` refuses a variant with a file that has no SHA-256, which could never verify. Onboarding's *Download now* then reports that it couldn't start.
- ***Pause* / *Resume*** act on the model's own files. ***Retry*** cancels the failed attempt's tasks, whose late updates are then ignored. After a network failure it keeps the files that arrived and queues the rest. After a checksum failure it throws staging away (a corrupt file resumed would never verify) and queues every file.
- **Space:** `DeviceStorage.space()` asks the platform (Android `StatFs` on the app's files, iOS capacity for important usage) over `deutschplan/storage`. `shortfall(needed:, space:)` gives the bytes a download lacks, which is what the disabled button states. It's 0 when the phone won't say, so a guess never blocks a download.

**Functional requirements**
- FR-M4-01 Downloads via `background_downloader`: resumable, Wi-Fi-only flag, progress notification, checksum (SHA-256 from the model manifest) verified before activation; partial files never activate.
- FR-M4-02 Model manifest (`assets/models/manifest.json`) lists URL, size, hash, licence per variant; updates compare hashes. A manifest that adds a file to an installed model is an update too, not a failure: the stamp is compared before the files are counted (#152, when the voice gained `M1.json` and `F2.json`).
- FR-M4-03 Deleting Supertonic sets `tts_engine = system`; deleting Hy-MT sets `mt_enabled = 0`.
- FR-M4-04 Hy-MT download button is enabled only when build flag `ENABLE_HYMT_DOWNLOAD` is true (licence gate, see `03-domain/translation.md`); the licence link opens the full text.
- FR-M4-05 Voice preview plays "Guten Tag! Ich bin Anna." with the chosen voice.

**Tests.** state machine with a fake downloader; hash failure → Failed; delete side-effects.
