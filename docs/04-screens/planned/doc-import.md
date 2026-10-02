# D1 · Learn from a document *(planned, v1.2.0, #1227–#1229)*

**Purpose.** Bring German text into Sogda: paste it, share it from another app, choose a PDF, or photograph it.

**Prototype.** `DocImport`, `DocImportProcessing`, `DocImportCorrect` (#1222).

**Reached from.**
- R1 idle: *Learn from a document*, under *Add a word I found*;
- **Android's share sheet:** "Share → Sogda" with text, a PDF or images. It opens D1 straight into processing, even mid-session, but never over a running exam (the deep-link rules). There, a toast says «Finish the exam first, then share it again.» (#1282): the learner shared from another app and would see nothing happen. What was shared isn't kept for later; the next share replaces it;
- D3's *New document*.

**Leads to.** D2 when processing ends.

**Layout.**
- Four large choices:
  - *Take photos*: the camera, a page at a time. The pages taken are listed («Page 1», «Page 2»), with *Done* and *Add a page* (#1229); at 30, *Add a page* is off and says why;
  - *Choose images*: the gallery;
  - *Choose a PDF*: the file picker;
  - *Paste text*: the clipboard, shown in an editable box first.
- "Everything stays on this phone" under them (BR-DOC-01).

**Processing.**
- "Reading page 2 of 4…", then "Finding your words…", with a progress bar and *Cancel*.
- **Photos** are read in turn on the phone: «Reading page 2 of 4…», with the bar at the pages done.
- **A photo with low OCR confidence** opens *Check the text*: the extracted text, editable, the low-confidence words marked, and *Take again* or *Continue*.
  - It opens for each such page in turn («Photo 2 was hard to read»), after all of them are read.
  - The pill counts the marked words the text still holds, so it falls as the learner fixes them.
  - *Take again* photographs that page again and reads it, and the new photo takes the old one's place.
  - What the learner leaves is the page's text. Then the pages go through the same clean-up, limit, German check and save as text, as `photo`, with the page count.
- **No text on any photo:** «No text found on the photos. Take them again in good light.», back to the choices.
- **A PDF without a text layer:** "This PDF is a scan: take photos of it instead", with *Choose images*.

**Functional requirements**
- FR-D1-01 Text comes from paste, share (text, PDF, image), a PDF's text layer or OCR on photos (ML Kit, bundled), all on the phone (BR-DOC-01, BR-DOC-02).
- FR-D1-02 At most 30 pages or 20,000 characters; the rest is cut, and the learner told.
- FR-D1-03 Low-confidence OCR (the page's mean element confidence below 0.7; #1229 tunes the number on the fixtures' blurred photo, and the test asserts it) offers *Check the text* before processing; the learner's edits are the text that's processed and saved.
- FR-D1-04 Text that isn't German (the matcher's threshold, `03-domain/document-matcher.md`) warns ("This doesn't look like German") with *Continue anyway*.
- FR-D1-05 *Cancel* stops processing and saves nothing.
- FR-D1-06 The document is saved with its text, and its images while *Save original images* is on (BR-DOC-05).

**Business rules applied.** BR-DOC-01, BR-DOC-02, BR-DOC-05, BR-PRIV-01.

**States.**
- **Empty clipboard:** *Paste text* is off, and says why.
- **Camera permission:** none is asked (#1229, a spec gap named). *Take photos* opens the phone's own camera app through `image_picker` (`ACTION_IMAGE_CAPTURE`), and *Choose images* the system photo picker, so Sogda holds neither the camera nor the gallery and there is nothing to deny. Backing out of the camera before a photo leaves D1 on its choices.
- **OCR or PDF failure:** an error panel (`SgErrorPanel`) with *Try again*.

**Data.** It writes `documents` (and the images under `<appSupport>/documents/<id>/`), then opens D2 on its id, and D2 runs the matcher (`03-domain/document-matcher.md`).
- **The text saved** is the clean one (`cleanPages`), cut to the limit (`limitText`: the last sentence end before 20,000 characters, else the last word end), since `match` reads `body` as it is. The note is a toast, and under the pasted text's box while it's over the limit.
- **The German check** (FR-D1-04) runs before anything is saved: `DocumentRepository.germanShareOf(body)`, the lemmatiser in an isolate. *Continue anyway* saves; *Cancel* saves nothing.
- **The title** is the text's first line with a letter in it, cut at a word end to 60 characters, or "Text of 2 Oct" when it has none (#1227). A letter's salutation alone on its line («Sehr geehrte Damen und Herren,», «Liebe Eltern,») is passed over, since it says who the letter is to, not what it's about, and a trailing comma or colon goes. D2 lets the learner change it.
- **`source`:** `paste` or `share` (#1227), `pdf` (#1228), `photo` (#1229).
- **The photos** (BR-DOC-05), while *Save original images* is on, are copied to `<appSupport>/documents/<id>/page-1.jpg`, `page-2.jpg`… in page order. `image_paths` lists them relative to `<appSupport>`, so a moved app folder keeps them. Taken at most 2,400 px wide at JPEG quality 90, about 1 MB a page. *Reset everything* and an import's *Replace*, whose documents come without photos (BR-DOC-06), delete the folder, after the data and best effort, as the recordings go.

**Developer notes.**
- **ML Kit text recognition, Latin script, bundled model** (no download from Google Play services; `google_mlkit_text_recognition`). Its licence and terms go in `licences.py` and M8.
  - **About 12 MB per phone** through the App Bundle's per-ABI split: `libmlkit_google_ocr_pipeline.so`, 11 MB on arm64, and the 1.3 MB Latin models. A universal APK carries all three ABIs (+31 MB). Measured on #1229.
  - **Release builds need R8 rules** (`proguard-rules.pro`): keep `com.google.mlkit.**` and `com.google.android.gms.internal.mlkit_**`, and `-dontwarn` the scripts not bundled. Without them, a release build crashed at launch or failed its first read; a debug run shows neither.
  - **Its usage metrics are never uploaded (BR-PRIV-01).** ML Kit, its model bundled, still queues device, app and latency metrics for Google through DataTransport's Clearcut backend, a network call no user action makes. The manifest removes DataTransport's backend discovery and its two schedulers (`tools:node="remove"`), so the events have nowhere to go. On the device, the build without that ran DataTransport's upload job after an OCR run, and the build with it has none, while OCR reads the same (#1229). `test/services/page_photos_test.dart` pins it.
  - **M8** lists ML Kit with its terms and their links, written in the app (`licences_screen.dart`), since the terms are web pages, not a licence text `licences.py` could fetch and compare.
  - **FR-D1-03's 0.7 is checked on the phone** by `integration_test/ocr_threshold_test.dart`, on a letter it draws: 0.87 sharp, 0.80 lightly blurred (two slips), 0.41 heavily blurred (garbled). A word's confidence marks where to look on a bad page, not which word is wrong: on the light blur, the words below 0.7 were read right.
- **A PDF's text layer** (#1228, ADR 31): pdfbox-android, from Kotlin over `sogda/pdf` (`PdfText.kt`), and `services/pdf_text.dart`'s `readPdf`, page by page:
  - *Cancel* stops between two pages, and the document is closed however reading ends;
  - at most 30 pages are read (BR-DOC-02), and `pageCount` says how many the file has, for the cut's note;
  - **a scan** is a PDF with no page of 25 letters or more in its text layer: D1 then shows "This PDF is a scan…" with *Choose images*;
  - a password-protected file is `PdfLocked`, anything unreadable `PdfUnreadable`: D1's error panel.
  - `integration_test/pdf_probe.dart` runs it on a release build, where R8 runs, for a device check.
- **The share target:** an `ACTION_SEND` / `ACTION_SEND_MULTIPLE` intent filter for `text/plain`, `application/pdf` and `image/*`. Text is #1227's; the PDF and the images join it in #1228 and #1229.
  - **`ShareActivity`**, with no window of its own, holds the filter. It opens `MainActivity` as the widget does (`NEW_TASK | CLEAR_TOP`), with the link `sogda://import` alone. So the share lands in the app's own task and its one Flutter engine, never in the sender's task as a second copy of the app with `user.db` open twice.
  - **The text stays in the process** (`ShareActivity.take`), never on an intent and never as data (#613). `MainActivity` is exported and BROWSABLE, so an extra on its intent could come from any app, or from a web page's `intent://` link, and D1 would save it with no share sheet chosen. It reads none. D1 takes the text once (`sogda/share`, `SharedText.take`); a launch restored after the process died finds none, so the same document isn't saved twice.
  - **The link** is an arrival like any other (`navigation.md`): a running exam holds it, and says so (#1282), a study session doesn't, and each share is numbered (`?arrival=`), so a second one onto D1 is read too.
- **R1 idle's** *Learn from a document*, under *Add a word I found*, pushes D1 (`/search/import`); back returns to R1. Once a document is kept it pushes D3 instead, whose *New document* is D1 (#1295). Back from the pasted text's box, or from processing, returns to the choices.
- The APK's growth is measured in `perf.py size`.

**Tests.**
- FR-D1-01 to 06; goldens for the choices, processing and checking the text.
- The share intent in an integration test.
