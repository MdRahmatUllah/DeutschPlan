# Play Console: the first upload, form by form (#1404)

*agent-5, 2026-10-03, for the owner's first upload of v1.2.0 (the closed test, then Production). Each form is listed in the Console's own order with the answer to give, where that answer comes from in the repo, and **owner** where the choice is yours, with a recommendation. Agents never open the Console: you fill it in. agent-3 checks the answers against the app's real behaviour.*

**Before you start:**
- **Fix the privacy policy.** sogda.de's privacy page says it covers the website, and gives the app one sentence. Play wants a policy that describes the app (sogda-website #145, see §1).
- **The release build:** `python tools/release_android.py --require-upload-key` has passed on the v1.2.0 tag (#1312, `release.md`'s checklist).

## 1. App content (Policy and programs → App content)

| Form | Answer | Source |
|---|---|---|
| **Privacy policy** | `https://www.sogda.de/en/datenschutz` (the English page; the site serves the same policy in every language) | sogda-website `app/[locale]/datenschutz`. **Blocker:** its §7 says «This policy covers the website». Play requires a policy that describes how *the app* handles data. The page needs an app section first (sogda-website #145), covering everything in the data safety row below |
| **App access** | **All functionality is available without any special access.** There's no login or account. A download (the voice, the translator) is offered in the app and needs no credentials | `release.md` (*Data safety*: «There is no account») |
| **Ads** | **No, my app does not contain ads** | `release.md` (*Data safety*: «no ads») |
| **Content rating** | The IARC questionnaire, below | the course, checked on 2026-10-03 |
| **Target audience and content** | **owner**, below | — |
| **News apps** | **No** | — |
| **Health apps** | **My app does not have any health features** | — |
| **Government apps** | **No** | — |
| **Financial features** | **My app doesn't provide any financial features** | — |
| **Data safety** | **No data collected and none shared**, below | `release.md` (*Data safety*), BR-PRIV-01, BR-PRIV-02, BR-DOC-01 |
| **Advertising ID** | **No**, the app doesn't use an advertising ID. The merged release manifest has no `com.google.android.gms.permission.AD_ID` | the merged manifest; `release_android.py` fails on any permission `release.md` doesn't list |

**Forms that don't apply** (the Console only shows them when their permission is there):
- **foreground service:** none (`release.md`);
- **photo and video permissions:** the app asks for no `READ_MEDIA_*`. Documents come in by share, by the system's picker, or by the camera app;
- **exact alarms, full-screen intents and the Accessibility API:** none asked for;
- **account deletion:** there are no accounts.

### Data safety

The form's first question decides the rest:

- **Does your app collect or share any of the required user data types?** **No.** Then:
  - the form skips encryption in transit and deletion requests;
  - the listing shows «No data collected» and «No data shared with third parties».

Why that's true, and what agent-3 checks on the release build:

| What the app does | Why it isn't collection | Source |
|---|---|---|
| The course, the plan, the progress | They stay in `user.db` and app-private files. Backup and device transfer are off | BR-PRIV-02, #607 |
| The learner's documents (text, photos, PDFs) | Extraction, OCR, word marking and translation all run on the phone. Nothing is sent anywhere | BR-DOC-01 |
| ML Kit's text recognition | The model is bundled. Its usage metrics are cut off in the manifest: DataTransport's backend and schedulers are removed (#1229). The merged manifest keeps only ML Kit's component registrars (`com.google.firebase.components:…Registrar` meta-data), which it needs to run, and sends nothing | BR-PRIV-01; the merged release manifest |
| The voice and the translator | The learner starts the download. It fetches files from huggingface.co (Supertonic 3, Hy-MT2) and sends nothing about the learner. Wi-Fi only | BR-PRIV-01; `app/assets/models/manifest.json` |
| The Speaking exam's recording | Recorded with `RECORD_AUDIO`, kept on the phone | `release.md` (*Permissions*) |
| *Report a problem* | Opens a pre-filled GitHub issue page in the phone's browser. The learner sends it there, or doesn't; the app sends nothing | `release.md` (*Data safety*) |
| Look a word up on the web (Duden, Wiktionary, DWDS, Linguee, Google) | Opens the phone's browser, on the learner's tap | BR-PRIV-01 |
| The review card | Play's own In-App Review UI, after a pass. Sogda sends nothing about the learner | BR-RATE-01 |
| Export | A JSON file the learner shares themselves | BR-PRIV-02 |

### Content rating (IARC)

- **Email:** the address IARC writes to (**owner**).
- **Category:** **Reference, News, or Educational**.
- **The answers:**

| Topic | Answer | What the course has |
|---|---|---|
| Violence, blood, fear | **No** | No depiction. *Krieg* is a vocabulary word with history sentences («Nie wieder Krieg.») |
| Sexuality, nudity | **No** | None |
| Language (profanity, crude humour) | **No** | None of the course's {totals.words} words is a swear word |
| Controlled substances | **owner**: answer **references, not encouraged** | Alcohol and tobacco appear only as everyday words in neutral sentences («Ich trinke nie Alkohol.», «Hier darf man nicht rauchen.», «Bayern ist bekannt für Bier.»). No drugs, and nothing shows use positively. IARC asks about references, so the honest answer is yes to a reference and no to use or encouragement. Expect a low age rating either way |
| Gambling, simulated gambling | **No** | None |
| Users interact or share content | **No** | There's no chat, no profiles and no sharing between learners. Documents stay on the phone |
| Shares the user's location | **No** | No location permission |
| Digital purchases | **No** | None |
| Unrestricted internet or a web browser | **No** | Web look-ups open the phone's own browser. There's no in-app browser |

### Target audience and content (**owner**)

- **Age groups.** **Recommendation:** 13–15, 16–17 and 18 and over. The audiences include school learners (pl, `messaging.md`) as well as adults. Leave out every group under 13: including one puts the app under the Families policy (teacher-approved rules, a separate review), which a course for teens and adults doesn't need.
- **Could the store listing unintentionally appeal to children?** **No.** It's a German course for exams, visas and work, with real screens and no mascots (`store-listing.md`).

## 2. The store listing (Grow → Store presence)

**Main store listing** (en-US), then a **translation** each for **bn-BD**, **pl-PL** and **ru-RU**. All of it comes from `docs/05-dev-guide/store-listing.md`:

| Field | Where it is |
|---|---|
| App name (30) | each language's *Title* |
| Short description (80) | each language's *Short description* |
| Full description (4000) | each language's *Full description* |
| App icon (512 × 512) | `docs/sogda-brand-kit/png/play-store-icon-512.png` (`store-listing.md`, *Website and icon*) |
| Feature graphic (1024 × 500) | `docs/05-dev-guide/store/feature-graphic/<lang>.png` (#1200; re-rendered with the v1.2.0 sets, #1392) |
| Phone screenshots | all eight in every language's first set, the six then `07-document` and `08-document-card` (the owner, #1383): `store/phone-light/` for en, `store/bn-phone-light/`, `store/pl-phone-light/`, `store/ru-phone-light/` |
| Tablet screenshots (7" and 10") | `store/tablet-light/` (en, used for every language) |
| Video (YouTube URL) | the promo (#1211): en for the main listing, and each translation its own (`kit.md` §3) |

`test_store_listing.py` holds the texts to Play's limits.

**Store settings:**
- **App or game:** **App**; **category:** **Education**.
- **Tags:** up to five from Play's list (**owner**). Recommendation: Language learning, then Education.
- **Contact details:**
  - **email (required, public): owner.** Use the address on sogda.de's Impressum, so one address answers both;
  - **website:** `https://sogda.de` (`store-listing.md`, *Website and icon*);
  - **phone:** optional, **owner**. Recommendation: leave it empty.

## 3. Pricing and distribution

- **Price:** **Free** (a Console setting). No purchases, no ads. A free app can never become paid; that's fine, as there are no plans to charge. Marketing copy still never says "free" (`plan.md`).
- **Countries and regions:** **owner**. Recommendation: every country Play offers. The audiences are in Bangladesh, Germany, Poland and Ukraine, Russian speakers in many countries, and English learners anywhere (`messaging.md`). The same list goes on the closed track and on Production.
- **Declarations:** the content guidelines and US export laws checkboxes.

## 4. Release

1. **App signing (the first upload):** choose **Let Google manage and protect your app signing key** (Play App Signing). You sign the bundle with your upload key (`app/android/key.properties`, never committed: `release.md` *Signing*), and Google re-signs it for devices. If the upload key is ever lost, Google can reset it; the app signing key can't be lost.
2. **Closed testing:**
   - create the track and add the testers;
   - upload `app-release.aab` (1.2.0+10);
   - paste the release notes per language: `store-listing.md`'s *What's new (1.2.0)*, from #1312;
   - roll it out.

   Every step, the 12 testers for 14 days, the feedback log and the "Apply for production" answers: [`closed-test.md`](closed-test.md) (#1239).
3. **The pre-launch report:** Play runs it on every upload to a test track. Read it before Production: crashes, accessibility, and screenshots on real devices. agent-3 files anything it finds.
4. **Apply for production:** after 14 days with 12 testers opted in. The questionnaire's drafts are in `closed-test.md`.
5. **Production:** the same bundle (or a fix build), the same notes, the countries from §3.
   - **Rollout: owner.** Recommendation: 100 %, since the launch posts send people straight to the listing (`calendar.md`, L).
   - **Managed publishing** isn't offered on a first release.

## 5. The owner's decisions, in one place

| # | Decision | Recommendation |
|---|---|---|
| 1 | The public contact email (Store settings, IARC) | sogda.de's Impressum address |
| 2 | Target age groups | 13–15, 16–17, 18 and over |
| 3 | IARC: controlled substances | A reference, not encouraged |
| 4 | Countries and regions | Every country Play offers |
| 5 | Tags | Language learning, Education |
| 6 | Production rollout | 100 % on launch day |
