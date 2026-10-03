# D3 · My documents *(planned, v1.2.0, #1226/#1230)*

**Purpose.** The documents the learner has brought, kept as the owner decided (#1220), to reopen, rename or delete.

**Prototype.** `MyDocuments`, `MyDocumentsEmpty` (#1222).

**Reached from.** Me (*My documents · 4*, or *My documents* with none kept), and R1 idle's *Learn from a document* when documents exist (D1 while none are). **Leads to.** D2 (a row), D1 (*New document*), M3 (*Settings*).

**Where it sits** (#1295). D3 is `/search/documents`, in the search's stack with D1 and D2, so a row's D2 and *New document*'s D1 (whose end is D2, in its place) come back to D3. Me's link is a cross-tab jump (`navigation.md`): the Search tab opens on R1 → D3, and back returns to R1. The artboard draws the Me tab; one stack for the three document screens is worth that difference.

**Layout.**
- A list, newest first. Each row has the title, the source icon (photo, PDF, text), the date ("2 Oct"), and "12 words added" ("nothing new" at none): the distinct lemmas added from it, a sentence kept for a word of my own (FR-D2-06) included.
  - A row is one button; its ⋮ is another, named "Options for <title>".
- A row's menu (a sheet): *Rename*, *Delete*.
  - *Rename* asks for the title in a sheet, as Me's name does. A blank one keeps the title.
  - *Delete* confirms (FR-D3-02), then says "Deleted '<title>'".
- At the top, *New document*.
- At the bottom, the storage line: "4 documents · 18 MB (images)" (the bytes under `documents/`, rounded up to the next MB), with *Settings* opening M3; "4 documents" alone while no photo is kept.

**The settings** (in M3, under *Learn from documents*, #1296; `settings.md`):
- *Words a day from documents* (5; BR-PLAN-11);
- *Save original images* (on);
- *Auto-delete documents* (never, or after 30, 90 or 365 days).

D2's *Show words I probably know* (off) is D2's own switch.

**Functional requirements**
- FR-D3-01 The list shows every saved document; a row opens D2, which matches it again (FR-D2-07).
- FR-D3-02 *Delete* asks first ("Delete 'Letter of 2 Oct'? The words you added stay.") and removes the document, its images and what it found, never the words or their sentences (BR-DOC-05).
- FR-D3-03 *Auto-delete* removes documents older than the setting when the app opens, the same way (`DocumentRepository.deleteOlderThan`, from `wireApp` after the start, #1296).
- FR-D3-04 Turning *Save original images* off asks whether to delete the images already kept (M3, #1296): only when some are.

**Business rules applied.** BR-DOC-05, BR-DOC-06, BR-PLAN-11.

**States.** **Empty:** "Bring the German you meet", then "A letter, a page, an article: Sogda marks the words you don't know yet, by level, and adds the ones you choose.", with *New document*, and no storage line.

**Data.** It reads `documents` and `document_words` (counts). It writes deletes, and the settings.

**Tests.** FR-D3-01 to 04; goldens for the list, empty and the delete dialog.
