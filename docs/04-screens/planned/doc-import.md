# D1 · Learn from a document *(planned, v1.2.0, #1227–#1229)*

**Purpose.** Bring German text into Sogda: paste it, share it from another app, choose a PDF, or photograph it.

**Prototype.** `DocImport`, `DocImportProcessing`, `DocImportCorrect` (#1222).

**Reached from.**
- R1 idle: *Learn from a document*, under *Add a word I found*;
- **Android's share sheet:** "Share → Sogda" with text, a PDF or images. It opens D1 straight into processing, even mid-session, but never over a running exam (the deep-link rules);
- D3's *New document*.

**Leads to.** D2 when processing ends.

**Layout.**
- Four large choices:
  - *Take photos*: the camera, several pages, with "Page 2 of 3 · Add a page · Done";
  - *Choose images*: the gallery;
  - *Choose a PDF*: the file picker;
  - *Paste text*: the clipboard, shown in an editable box first.
- "Everything stays on this phone" under them (BR-DOC-01).

**Processing.**
- "Reading page 2 of 4…", then "Finding your words…", with a progress bar and *Cancel*.
- **A photo with low OCR confidence** opens *Check the text*: the extracted text, editable, the low-confidence words marked, and *Take again* or *Continue*.
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
- **Camera permission denied:** an explanation, with *Open settings*.
- **OCR or PDF failure:** an error panel (`SgErrorPanel`) with *Try again*.

**Data.** It writes `documents` (and the images under `<appSupport>/documents/<id>/`), then hands the text to the matcher (`03-domain/document-matcher.md`).

**Developer notes.**
- **ML Kit text recognition, Latin script, bundled model** (no download from Google Play services). Its licence and terms go in `licences.py` and M8.
- **A PDF's text layer** (#1228, ADR 31): pdfbox-android, from Kotlin over `sogda/pdf` (`PdfText.kt`), and `services/pdf_text.dart`'s `readPdf`, page by page:
  - *Cancel* stops between two pages, and the document is closed however reading ends;
  - at most 30 pages are read (BR-DOC-02), and `pageCount` says how many the file has, for the cut's note;
  - **a scan** is a PDF with no page of 25 letters or more in its text layer: D1 then shows "This PDF is a scan…" with *Choose images*;
  - a password-protected file is `PdfLocked`, anything unreadable `PdfUnreadable`: D1's error panel.
  - `integration_test/pdf_probe.dart` runs it on a release build, where R8 runs, for a device check.
- **The share target:** an `ACTION_SEND` / `ACTION_SEND_MULTIPLE` intent filter for `text/plain`, `application/pdf` and `image/*`.
- The APK's growth is measured in `perf.py size`.

**Tests.**
- FR-D1-01 to 06; goldens for the choices, processing and checking the text.
- The share intent in an integration test.
