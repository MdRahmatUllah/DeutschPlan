# 1 · Business

Sogda is a complete German course, A1.1 to C2.2, that runs entirely on
an Android phone, for adults who learn German for work, study or residence.
Its first audience is Bangla speakers, who get every meaning in Bangla and
every word's pronunciation written in Bangla letters; English speakers are
the second. It needs no account, shows no ads, collects nothing, and works
without a signal. Since v1.2.0 it also reads the German the learner meets, a
letter or a page, and turns it into words to learn, on the phone. This
chapter makes the case for it: the problem, the audience, how it compares
with the alternatives, the principles it keeps, the open business
questions, the risks, and how the design can grow into more languages.

> The detailed specs in [`docs/`](../README.md) are the source of truth. If
> anything here disagrees with them, the spec wins and this page is wrong.

State described: v1.2.0 as built on main by 2026-10-03 (`f5151b64`), ahead of
its release commit (#1235). Counts marked v1.0.1 are that release's.

## The problem

The product brief ([`overview.md`](../00-product/overview.md)) names the
audience: adults learning German for work, study or residence. It also names
their constraints, and the product is built around them:

- **They study on a phone, in short sessions.** A typical session is 10–20
  minutes, often without signal.
- **They need the whole path, not a taster.** The target is an exam level
  (Goethe and telc are named only to describe the level), from the first
  word to C2.
- **They need to know what to do today.** A long course fails when every
  day starts with choosing what to study.
- **Many think in Bangla.** The course's differentiator is its Bangla
  meaning and Bangla pronunciation columns (`overview.md`, "Who it is for").
  With them, a Bangla speaker learns German without going through English.
- **They meet German they didn't choose.** A landlord's letter, a
  Jobcenter's, a health insurer's, a school's note, an article: the kinds of
  text the documents feature is tested on
  ([`document-matcher.md`](../03-domain/document-matcher.md)). The course
  teaches words in its own order, not the ones on the page in front of the
  learner. Since v1.2.0 they can bring that page (epic #1219): Sogda marks
  the words they don't know yet, by level, and adds the ones they choose,
  each with the sentence it was met in.

## The audience

| Group | What they get | Settings |
|---|---|---|
| **Bangla speakers** (first) | Meanings in Bangla, or Bangla and English together; the pronunciation of all 5,069 words in Bangla letters; the app itself in Bangla, with Bangla digits; interference tips (false friends, traps) in Bangla | Meaning language বাংলা or Both; app language বাংলা |
| **English speakers** (second) | Meanings and the app in English; the pronunciation as an English respelling (v1.1.0), the Bangla line off by default | Meaning language English |
| **Russian speakers** (v1.1.0) | Meanings, the pronunciation in Russian letters, example sentences, grammar rules, interference tips and category names in Russian; the app in Russian | Meaning language Русский; app language Русский |
| **Polish speakers** (v1.1.0) | The same in Polish, the pronunciation in Polish spelling; the app in Polish | Meaning language Polski; app language Polski |

The meaning language and the app language are separate settings. Setup asks
for each (the app language first, the phone's by default), and Settings can
change them apart. Since v1.1.0 the meaning language is a first language and
an optional second shown under it: any one or two of English, Bangla,
Russian and Polish (#1081)
([`settings.md`](../04-screens/settings.md)).

## The value proposition

One sentence, from the product brief: *an exam-structured, fully offline
German study plan from A1.1 to C2.2 that tells the learner exactly what to
do today, revises what they have learned with spaced repetition, and lets
them verify each step with generated mock exams, with meanings in English
and Bangla.*

In numbers, at v1.0.1:

- **A complete course.** 12 steps, 5,069 words, 10,545 example sentences,
  182 grammar topics, 159 word categories and 622 interference tips, in one
  read-only database that ships inside the app.
- **A plan for every day.** Revision scheduled by FSRS-4.5 (target
  retention 90 % by default), 7 new words a day by default, the week's
  grammar topic and 3 practice sentences. Rest days and a backlog without
  deadlines are built in.
- **Proof of progress.** Three generated mock exams per step: 40 questions
  plus a writing and a speaking task, 48 points, about 20 minutes, pass mark
  60 %.
- **A voice.** The phone's German voice, or Supertonic, an optional
  on-device voice of about 400 MB.
- **Nothing to sign up for.** No account, no ads, no analytics. Progress
  stays on the phone and moves only in an export file the learner shares.

v1.2.0 adds two things on the same terms:

- **The learner's own German** ([`doc-import.md`](../04-screens/planned/doc-import.md)).
  Pasted, shared from another app, a PDF of up to 30 pages, or photographed:
  up to 20,000 characters a document (BR-DOC-02). Its words join the day
  under their own cap, 5 a day by default, on top of the course's new words
  (BR-PLAN-11). Free, with no limits (BR-DOC-08, the owner, #1220).
- **Translation on the phone.** Hy-MT2-1.8B, an optional 1.1 GB download
  under Apache-2.0, offered in every build (ADR 30,
  [`translation.md`](../03-domain/translation.md)).

## Why offline matters

Offline is not a feature added on top: the whole design follows from it.

1. **The learner has no signal when they have time.** Every study feature
   works in airplane mode, and there is no "no connection" screen for core
   features ([`accessibility-performance.md`](../01-architecture/accessibility-performance.md),
   *Offline*).
2. **Privacy is structural, not a policy.** With no server, there is nothing
   to breach and nothing to sell. The Play data-safety form says "no data
   collected, none shared" and it is true by construction
   ([`release.md`](../05-dev-guide/release.md)).
3. **It costs almost nothing to run.** There is no backend. The course ships
   inside the app, and the optional voice downloads from its maker's public
   model repository. A thousand learners or a million cost the project the
   same.
4. **It is fast.** A search answers in about 18 ms (median, on the
   emulator), and a card rating writes locally with no round trip.

The only network use the app makes itself is a model download the learner
starts. Web-search links, *Report a problem* and Me's *Rate Sogda on Google
Play* open a page or the Play Store when the learner taps them (BR-PRIV-01,
BR-SEARCH-04, FR-M1-05). Reading a document needs no network either: a PDF's
text, a photo's words and the lemmas are all worked out on the phone
(BR-DOC-01).

## Positioning

A fair comparison with what a German learner would otherwise use. The
competitors' column describes their public offer as the team understands it;
it was **not verified for this handbook** and products change often, so
check each row before quoting it outside the team.

| | Model | Account | Works offline | Bangla | Structure | Revision |
|---|---|---|---|---|---|---|
| **Sogda** | Undecided (see below); no ads | None | Fully | Meanings, pronunciation, UI, tips | 12 steps A1.1–C2.2, a plan per day, generated mock exams | FSRS-4.5 |
| **Duolingo** | Free with ads, or a subscription | Yes | Partly | No Bangla-to-German course that we know of | Gamified path of short lessons | Its own review system |
| **Babbel** | Subscription | Yes | Partly (downloads) | No | Courses by CEFR level, dialogues | Review sessions |
| **Busuu** | Free tier and subscription | Yes | Partly (premium) | No | CEFR courses; native speakers correct your writing | Vocabulary review |
| **Memrise** | Free tier and subscription | Yes | Partly | No | Vocabulary with videos of native speakers | Spaced repetition |
| **Anki** (AnkiDroid) | Free, open source | Optional (sync) | Fully | Only if a deck has it | None: decks are user-made | SM-2 or FSRS |
| **Goethe / telc prep books** | One-off purchase | — | Paper | Rarely | One exam level per book, official formats | None |

What Sogda offers that none of them combine: the whole A1.1–C2.2 path,
Bangla throughout, a daily plan decided for the learner, and no account or
connection at all. Since v1.2.0, also the learner's own letters and pages
turned into words to learn, with the course's levels, on the phone.

What they offer that Sogda does not (and a learner may still want):

- **Human feedback.** Writing and speaking are self-assessed here, with app
  checks (length, target words, connectors). Busuu's community and a
  teacher correct them.
- **Recorded native audio.** Sogda speaks through a synthetic voice.
- **Motivation by game and social pressure.** Sogda is deliberately
  not a game: no hearts, lives or leaderboards, and a quiet streak.
- **Official exam papers.** The mock exams are generated from the course and
  say so. Prep books follow the official formats.
- **Sync across devices, and iOS.** Sogda moves progress by export
  file, and ships on Android only for now.
- **Depth at B1.** B1 has 379 words against A1's 1,315 (see *Risks*).

## The principles

These are decided and recorded; changing one is an owner decision with an
ADR.

| Principle | Where it is decided |
|---|---|
| No account, no server | ADR 13; [`overview.md`](../00-product/overview.md) "What it is not" |
| No analytics, no telemetry | ADR 13; `overview.md` "Success measures" |
| No ads, no upsells, no share prompts | FR-T6-03 ([`day-complete.md`](../04-screens/day-complete.md)); the data-safety declaration |
| Data stays on the phone | BR-PRIV-02: all learner data in `user.db` and app-private files |
| No network call without a user action | BR-PRIV-01 (web link, model download, export share) |
| Not a game | `overview.md`: no hearts, lives or leaderboards; streaks exist but are quiet |
| Not an official exam | `overview.md`; L10's note "not official Goethe or telc papers" |
| Honest sizes | The voice is offered as "About 400 MB, over Wi-Fi, downloaded once" (the owner, #245); Hy-MT2 as 1.1 GB ([`model-manager.md`](../04-screens/model-manager.md)) |
| Documents stay on the phone | BR-DOC-01: extraction, OCR, lemmatising and translation all run on the phone; BR-DOC-05: a kept photo loses its metadata |
| A machine's meaning says so | BR-DOC-07: labelled until the learner edits it |
| No pressure to rate | BR-RATE-01: Play's review card once, after the first passed mock exam, with no question before it, no incentive and no button that triggers it |
| Missing a day is not failing | BR-PLAN-06: the backlog has no deadline and is never shown as overdue |

## Privacy

- **Play data safety:** no data collected and none shared
  ([`release.md`](../05-dev-guide/release.md)). There is no account, no
  analytics and no ads.
- **Model downloads** fetch files from the model's host and send nothing of
  the app's own.
- **Speaking recordings** stay on the phone, and are not even included in an
  export.
- **Export** is a JSON file the learner shares through the system share
  sheet, to wherever they choose. It never passes through a server of ours
  ([`export-import.md`](../04-screens/export-import.md)).
- ***Report a problem*** opens a pre-filled GitHub issue page in the browser,
  with the card's id. The learner sends it, or doesn't.
- **Documents** (v1.2.0) are read and kept on the phone (BR-DOC-01,
  BR-DOC-05): the text always, and the photos while *Save original images*
  is on, in app-private storage. A kept photo loses its metadata (EXIF and
  GPS, XMP, IPTC, a phone's trailer) before it is written, and the photo
  picker's or a share's own copy of a page or a PDF is deleted once it is
  read ([`document-matcher.md`](../03-domain/document-matcher.md), *Data*).
  *Auto-delete documents* (after 30, 90 or 365 days) is off by default. An
  export carries a document's text, never its photos (BR-DOC-06).
- **ML Kit's usage metrics never leave.** Its text recogniser queues them
  for Google even with its model bundled; the manifest removes the
  DataTransport backend that would send them (BR-PRIV-01, #1229).
- **Translation** runs on the phone, once Hy-MT2 is downloaded: no text goes
  to a translation service ([`translation.md`](../03-domain/translation.md)).
- **The rating card** (v1.2.0) is the Play Store's own UI, asked for once.
  Sogda sends nothing about the learner with it, and keeps only that it has
  asked (BR-RATE-01).
- **Permissions** are asked only when a feature needs them: the microphone on
  the first Speaking recording, notifications when the reminder is switched on
  or a model download starts. v1.2.0 adds none: *Take photos* opens the
  phone's camera app and *Choose images* the system photo picker, so Sogda
  holds neither ([`doc-import.md`](../04-screens/planned/doc-import.md),
  *States*). The full list is in
  [chapter 3](03-capabilities.md#privacy-and-permissions).

## The licences stance

In practice (ADR 9), the project ships a model only if its licence covers
every country where the app is offered. That has already cost a feature.

- **On-device translation was off until v1.2.0 (ADR 9, #173).** The
  planned translator, Hy-MT 1.5 (1.8B), was under the Tencent HY Community
  License, which excludes the EU, the UK and South Korea. One Play build
  cannot keep the download out of those regions, and many learners are in
  Germany, so v1.0 and v1.1 shipped with it off.
- **Hy-MT2 brings it back (ADR 30, #154; the owner, #533).** Hy-MT2-1.8B
  is Apache-2.0, with no regional exclusions, so v1.2.0 offers its 1.1 GB
  download in every build. The other candidates (#494) lost on that: the
  Firefox/Bergamot tiny models, Google ML Kit (a download from Google, usage
  metrics), and NLLB-200 (a non-commercial licence)
  ([`translation.md`](../03-domain/translation.md)).
- **The voice is Supertonic 3 under BigScience OpenRAIL-M**, a licence that
  allows commercial use with use-based restrictions. Its text ships in the
  app's Licences screen (M8), with the MIT licence of the SDK whose text
  front end the app ports.
- **Reading documents (v1.2.0).** OCR is Google's ML Kit text recognition,
  the Latin model bundled, chosen by the owner over Tesseract (#1220). It
  comes under Google's terms rather than a licence text, so M8 names those
  terms with their links. A PDF's text layer is read by pdfbox-android
  (Apache-2.0, with Apache PDFBox's NOTICE), which brings Bouncy Castle (MIT)
  for encrypted files (ADR 31). Play's in-app review library, behind
  BR-RATE-01's card, is listed the same way as ML Kit
  ([`about-licences.md`](../04-screens/about-licences.md)).
- **Fonts** are Inter and Noto Sans Bengali, SIL OFL 1.1, bundled.
- **Packages** are listed from Flutter's `LicenseRegistry`. The release
  checklist runs `tools/licences.py check`, which fails if a bundled licence
  differs from its maker's or a package ships none.

## The business model

> **Undecided.** Nothing in `docs/`, the ADRs or the team board decides how
> Sogda earns money, or whether it should. The options below are
> questions for the owner, not recommendations.

What is already fixed narrows the choice: no ads, no account, no analytics
and no server. The options that remain:

| # | Option (question for the owner) | Fits the principles? | What it would take |
|---|---|---|---|
| Q1 | **Free, with no revenue**: a public-good or portfolio project | Yes | Nothing new. The costs are the store account and the owner's time; there is no server bill |
| Q2 | **Paid up front** on Google Play | Yes: Play handles the payment, the app stays account-free | A price decision, and whether a price shuts out the audience the app was built for |
| Q3 | **Free, with a one-time unlock** (for example, later steps or the mock exams) | Mostly | Google Play Billing, a new dependency and a network call at purchase; a check of the data-safety form and BR-PRIV-01 |
| Q4 | **Donations or sponsorship**, a link in About | Yes | A link out, like the existing web links |
| Q5 | **Licences for organisations** (schools, training centres) | Yes, if the app stays as it is | A sales channel; perhaps content or branding per organisation |
| Q6 | **Subscription** | Yes, technically | Play Billing, and an answer to what a learner renews for when the course is fixed and offline |

Two related questions are also open:

- **Q7 · The source code.** The repository is public and has no licence file,
  so by default all rights are reserved. Should it carry an open-source
  licence, or become private?
- **Q8 · The content's provenance.** The course is compiled from four German
  tracker workbooks. The docs don't record who holds the rights to them
  (especially the example sentences) or on what terms. A commercial release
  should write that down.

## Success metrics

There is no telemetry, by design, so success cannot be measured inside the
app. `overview.md` names what counts instead:

- **Store reviews and ratings.**
- **Support.** *Report a problem* and the About screen's *Contact* both lead
  to the project's GitHub issues: the app has no email address or server.
- **The learner's own dashboard.** Me and Progress show the streak, 12 weeks
  of activity, words done and retention against the target.

Design targets the build is held to:

| Target | Value | Source |
|---|---|---|
| A returning learner reaches the first card | 2 taps, under 3 s | `overview.md` |
| A 20-card day | about 12 minutes | `overview.md` |
| Cold start to Today | < 1.5 s on a mid-range 2022 Android phone | `accessibility-performance.md` |
| Warm start | < 500 ms | same |
| Search | < 50 ms a keystroke | same |
| App size | at most 3 % over the baseline (the arm64 APK; 54.12 MB in `tools/perf_baseline.json` since #1293) | same, ADR 27, ADR 31 |
| Release quality | no P1 from the SQA pass (v1.0.0's pass 4 found none, and its three P2s were fixed and rechecked) | the team board |

**Questions for the owner:** Google Play Console gives aggregate installs,
ratings and Android vitals (crash and ANR rates, collected by Google from
users who opted in, not by the app). Should those count as success measures?
And is there a target (learners, rating, retention) the owner wants to hold
the product to?

## Risks

| Risk | Why it matters | What limits it today | Open action |
|---|---|---|---|
| **Licences** | A model licence can exclude a market (Hy-MT 1.5 did) | Hy-MT2 is Apache-2.0 (ADR 30); `licences.py check` at release | — |
| **Models hosted by third parties** | The voice and Hy-MT2 download from their makers' Hugging Face repositories. If the files move, downloads fail until an app update, since the manifest ships in the app | SHA-256 checks; the phone's voice always works as a fallback | Consider mirroring the model files |
| **Thin B1** | B1 has 379 words (A1 1,315, B2 1,023); `overview.md` marks it "to be expanded" | Mock exams at A1.1–B1.2 reuse a grammar topic or two and say so | New content in the workbooks |
| **English-only content parts** | Grammar rules, example translations and category names are in English, even in the Bangla UI (#425) | Meanings, pronunciation, tips and the whole UI are in Bangla | Bangla translations through the workbooks and the pipeline |
| **One platform** | iOS users can't install it | iOS code paths are built and tested (adaptive chrome, iOS goldens) | A Mac for #171, #161, #398 |
| **No telemetry** | Crashes and confusion are invisible unless reported | 4,598 Flutter tests (goldens included), a dedicated SQA agent, *Report a problem* | Decide on Play vitals (above) |
| **Low-end phones** | With Supertonic's sessions open the app uses about 520 MB of memory (PSS, on the emulator); the voice is 399 MB to download, Hy-MT2 1.1 GB | The voice and the translator are optional; a 100 MB free-space margin is enforced; the phone voice is the fallback; Hy-MT2 loads on the first translation and is released in the background (`translation.md`) | Owner: a memory budget (none yet) |
| **Machine translation quality** | In #1278's spot check of 50 words outside the course per language, Hy-MT2's meaning was wrong for 17 in Polish, 15 in Bangla and 13 in Russian | Labelled machine-translated (BR-DOC-07); offered as suggestions to check, never a pre-filled meaning (the lead's call on #1278) | The owner may change that call |
| **Personal documents on the phone** | A letter can be a bank statement or a doctor's | App-private storage, Android backup off (BR-PRIV-02), photo metadata removed, copies deleted once read, optional auto-delete, photos never exported (BR-DOC-05, BR-DOC-06) | — |
| **App size** | v1.2.0 adds ML Kit's text recognition (about 12 MB a phone, `doc-import.md`), pdfbox-android (+1.8 MiB, ADR 31) and llama.cpp's CPU libraries (about 21 MB at ADR 29's measure, ADR 30) | One-ABI downloads from the App Bundle; the models download separately | #1318 trims pdfbox's CJK CMaps; #1306 measures v1.2.0 feature by feature |
| **Release depends on the owner** | Release builds fail without the upload key unless they opt in to the debug key, as the agents' device checks do (#705); start time on a real phone is unchecked | `tools/release_android.py` reports the signing key | Owner: upload key, real-phone check |
| **The app id is permanent** | `de.sogda.app` can never change once on Play | Chosen by the owner (ADR 28, #601) | — |
| **Exam claims and trademarks** | Implying official exams would mislead | Mock exams are labelled generated; Goethe and telc named only for the level | Recheck the store texts (`store-listing.md`) before each upload; the brand kit (`docs/sogda-brand-kit/`) names no exam body |
| **Store policy** | Foreground-service and notification rules change | Declarations listed in `release.md` | Recheck each Play upload |

## Growth: more languages to learn, and more meaning languages

The owner's stated direction (2026-09-26, #595) is to go beyond German and
Bangla: more languages to learn, and more meaning languages later. This
section says what in the current design already helps, and what would have
to change. It is an analysis, not a plan.

**Meaning languages: done in v1.1.0** (M8, epic #1085). Russian and Polish
came through the workbooks' columns, and Polish and Russian became app
languages. The fixed columns and enums in the table's meaning-language
column below are what it replaced:
- meanings, examples, grammar, tips and category names by language
  (`word_meanings`, `word_example_translations`, `grammar_translations`,
  `word_tips`, `category_translations`), each shipped only when complete
  (PIPE-08);
- a first and an optional second language (`MeaningChoice`);
- quiz directions by language (`de>ru`, `ru>de`);
- typed answers folded per script.

A next meaning language is a workbook column, a review and a content build.
The column for more languages to learn stands as written.

### What already helps

- **The content pipeline is data-driven.** Courses are authored in Excel
  workbooks listed in `content/manifest.yaml`, read by header name, and
  compiled into one read-only SQLite file
  ([`content-pipeline.md`](../02-data/content-pipeline.md)). A new course is
  new workbooks and a new build, not new app code for the content itself.
- **Content and progress are separate databases** (ADR 2). Content updates
  already keep progress, keyed by each word's uid (BR-CONTENT-01).
- **The course structure is CEFR's.** Six levels, twelve steps, which apply
  to any language.
- **Most engines are language-neutral.** FSRS, the daily plan, the backlog,
  the streak, quiz selection, the exam's sections and seeds, export and
  import, reminders and the widget know nothing about German.
- **The meaning language is its own concept.** The meaning languages
  (`meaning_primary`, `meaning_secondary`) are settings apart from
  `ui_language`, and every screen that shows a meaning already asks which.
- **All UI copy is in ARB files.** 972 strings in each of English and
  Bangla, and `test/l10n_test.dart` fails on a missing translation or a
  hard-coded string. A new UI language is a new ARB file.
- **A second script is proven.** Bangla has its own font, its own digits,
  per-script runs sized a step larger, line breaks between aksharas, and
  screen-reader voice tags (`bn-BD`) inside mixed text. That work is the
  template for another non-Latin script.
- **Voices sit behind an interface** (`TtsEngine`), with the phone's own
  voice as the fallback for any language it has.

### What would have to change

| Layer | German- or Bangla-specific today | For more meaning languages | For more languages to learn |
|---|---|---|---|
| **Schema** | `words` has fixed `german`, `english`, `bangla` and `pron_bn` columns; `interference_tips` has `tip_en` and `tip_bn`; `word_examples` has `german` and `english` only; `grammar_topics` has `example_de`, `example_en` and an English rule | A meanings table (word, language, text), or a column per language; translations of examples and rules | The same, with the target language generalised from `german` |
| **Word identity** | `uid = sha1(level\|german\|pos\|english)`: English is part of a word's identity (PIPE-03) | Fine as it is | Needs a course id in the key, or one database per course |
| **Settings** | `MeaningLanguage { english, bangla, both }`, `UiLanguage { english, bangla }`; quiz directions `deEn`, `deBn`, `enDe` | Open-ended language codes; "both" becomes "these two" | Directions named by language pair |
| **Answer checking and search** | Umlaut folding (ä/ae/a, ß/ss) shared by Python and Dart (`text_norm`); article stripping | Checking typed meanings in a new language | A normaliser per language |
| **Learning logic** | Articles der/die/das with their colours and spoken gender; the cloze's separable verbs and reflexive *sich*; grammar practice's German inflection classes; Writing's verb-stem matching; the umlaut row; placement's article questions | None | Rewritten or made pluggable per language |
| **Voice and text** | `SystemTts` speaks `de-DE`; Supertonic's input is tagged `<de>`; course text is tagged `de-DE` for screen readers; Today's date is always German | None | A voice per language (whether Supertonic speaks it is unchecked) |
| **Links and names** | Web links to Duden and DWDS | None | New dictionaries. The name already fits every language: Sogda (ADR 28), whose mark changes only its front tile per course (É for French, Ñ for Spanish; `docs/sogda-brand-kit/`) |
| **One course per install** | `content.db` is one course, and progress assumes it | None | A course picker, and progress kept per course |
| **Documents** (v1.2.0) | The lemmatiser's rules, its strong-verb and stop-word tables, the German check, and OCR's Latin model | Hy-MT2 translates between German and the four meaning languages (`translation.md`); a new one needs its directions checked | A lemmatiser, tables and a check per language, and OCR for its script |

Adding a meaning language is mostly data (translations through the
workbooks), a schema change, and widening two enums. Adding a language to
learn touches the learning logic itself. Which comes first, and which
languages, are the owner's call.
