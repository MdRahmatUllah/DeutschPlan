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

**Data.** It writes `documents` (and the images under `<appSupport>/documents/<id>/`), then opens D2 on its id, and D2 runs the matcher (`03-domain/document-matcher.md`).
- **The text saved** is the clean one (`cleanPages`), cut to the limit (`limitText`: the last sentence end before 20,000 characters, else the last word end), since `match` reads `body` as it is. The note is a toast, and under the pasted text's box while it's over the limit.
- **The German check** (FR-D1-04) runs before anything is saved: `DocumentRepository.germanShareOf(body)`, the lemmatiser in an isolate. *Continue anyway* saves; *Cancel* saves nothing.
- **The title** is the text's first line with a letter in it, cut at a word end to 60 characters, or "Text of 2 Oct" when it has none (#1227). D2 lets the learner change it.
- **`source`:** `paste` or `share` (#1227), `pdf` (#1228), `photo` (#1229).

**Developer notes.**
- **ML Kit text recognition, Latin script, bundled model** (no download from Google Play services). Its licence and terms go in `licences.py` and M8.
- **The share target:** an `ACTION_SEND` / `ACTION_SEND_MULTIPLE` intent filter for `text/plain`, `application/pdf` and `image/*`. Text is #1227's; the PDF and the images join it in #1228 and #1229.
  - **`ShareActivity`**, with no window of its own, holds the filter. It opens `MainActivity` as the widget does (`NEW_TASK | CLEAR_TOP`), with the link `sogda://import` alone. So the share lands in the app's own task and its one Flutter engine, never in the sender's task as a second copy of the app with `user.db` open twice.
  - **The text stays in the process** (`ShareActivity.take`), never on an intent and never as data (#613). `MainActivity` is exported and BROWSABLE, so an extra on its intent could come from any app, or from a web page's `intent://` link, and D1 would save it with no share sheet chosen. It reads none. D1 takes the text once (`sogda/share`, `SharedText.take`); a launch restored after the process died finds none, so the same document isn't saved twice.
  - **The link** is an arrival like any other (`navigation.md`): a running exam holds it, a study session doesn't, and each share is numbered (`?arrival=`), so a second one onto D1 is read too.
- **R1 idle's** *Learn from a document*, under *Add a word I found*, pushes D1 (`/search/import`); back returns to R1. Back from the pasted text's box, or from processing, returns to the choices.
- The APK's growth is measured in `perf.py size`.

**Tests.**
- FR-D1-01 to 06; goldens for the choices, processing and checking the text.
- The share intent in an integration test.
