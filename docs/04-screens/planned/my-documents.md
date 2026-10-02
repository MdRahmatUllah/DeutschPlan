# D3 · My documents *(planned, v1.2.0, #1226/#1230)*

**Purpose.** The documents the learner has brought, kept as the owner decided (#1220), to reopen, rename or delete.

**Prototype.** `MyDocuments`, `MyDocumentsEmpty` (#1222).

**Reached from.** Me (*My documents · 4*), and R1 idle's *Learn from a document* when documents exist. **Leads to.** D2 (a row), D1 (*New document*).

**Layout.**
- A list, newest first. Each row has the title, the source icon (photo, PDF, text), the date, and "12 words added".
- A row's menu: *Rename*, *Delete*.
- At the top, *New document*.
- At the bottom, the storage line: "4 documents · 18 MB (images)", linking to the settings below.

**The settings** (in M3, under *Documents*):
- *Save original images* (on);
- *Delete documents after* (never, 30, 90 or 365 days);
- *Words from documents a day* (5; BR-PLAN-11);
- *Show words I probably know* (off).

**Functional requirements**
- FR-D3-01 The list shows every saved document; a row opens D2, which matches it again (FR-D2-07).
- FR-D3-02 *Delete* asks first ("Delete 'Letter of 2 Oct'? The words you added stay.") and removes the document, its images and what it found, never the words or their sentences (BR-DOC-05).
- FR-D3-03 *Auto-delete* removes documents older than the setting when the app opens, the same way.
- FR-D3-04 Turning *Save original images* off asks whether to delete the images already kept.

**Business rules applied.** BR-DOC-05, BR-DOC-06, BR-PLAN-11.

**States.** **Empty:** "Bring the German you meet: a letter, a page, an article", with *New document*.

**Data.** It reads `documents` and `document_words` (counts). It writes deletes, and the settings.

**Tests.** FR-D3-01 to 04; goldens for the list, empty and the delete dialog.
