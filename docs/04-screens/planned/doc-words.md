# D2 · The words in your text *(planned, v1.2.0, #1230)*

**Purpose.** Show the learner the German they brought, with the words they don't know yet marked by level, and let them add those words in a few taps.

**Prototype.** `DocWords`, `DocWordsCard`, `DocWordsEmpty` (#1222), in every canvas. The sample is a team-written landlord's letter, classed against `content.db` for a learner placed at A2.1.

**The marks** (#1222):
- **A new word:** a soft fill in its level's colour (L1's band colour at 30 %), and a 2 px underline in ink.
- **A word outside the course:** a dotted ink underline.
- **One of *My words*:** a small "My word" badge.

The ink underline is what makes a word marked, and the fill says its level, which the card's chip also names, so the level is never shown by colour alone. Ink on every level's fill is at least 6.4:1 in all eight canvases (light, dark and glass, Android and iOS), and the underline gives the same margin for the non-text check. `docs/design/cefr-marks.json` has each canvas's surface, ink and blended fills with their ratios, for D2's goldens to pin.

**Reached from.** D1 when processing ends, and D3's row (a saved document opens here and is matched again, so its marks follow what the learner has learnt since, FR-D2-07). **Leads to.**
- the mini card, as a sheet on a phone or a side pane on a tablet, as W1 opens;
- W1 (*Open* on a course word);
- R2, pre-filled, for a word outside the course;
- back to D1 or D3.

**Layout, top to bottom.**
1. **The header:**
   - the document's title (editable; by default its first line with a letter, or "Text of 2 Oct": D1 names it, #1227);
   - the summary: "12 new · 4 probably known · 3 outside the course";
   - a *Show words I probably know* switch (`doc_show_probably_known`).
2. **The text,** as extracted, scrollable, in reading size:
   - new course words have an underline and a soft fill in their level's colour (the CEFR colours of L1);
   - words that are mine carry a small "My word" mark;
   - words outside the course get a dotted underline;
   - probably-known words are dimmed when the switch is on, and plain otherwise;
   - a word that appears several times is marked each time, and its card lists every sentence.
3. **The bulk bar,** pinned at the bottom:
   - *Add my level* and *Add my level and one above*, side by side (one height for the pair), stacked above 100 % text;
   - *Add all new*, and the number each would add;
   - the cap note, "5 a day: the other 7 start tomorrow or later" (BR-PLAN-11), when more are new than today takes;
   - an ambiguous word is in no bulk action: its card asks which it is.

**The mini card (a sheet).**
- **The headword:**
  - for a noun, the article and the plural;
  - for a verb, the 3rd-person present and the participle;
  - the level chip, and the meaning(s) in the learner's meaning languages.
- **The sentence** from the document, with the word bold.
- **Buttons:**
  - *Add* (or *Added*);
  - *I know this* (*Mark known*, FR-W1-02);
  - *Ignore*;
  - *Open* (W1).
- **A word outside the course:**
  - Hy-MT2's meaning, labelled "machine-translated", or "No meaning yet: download translation" (a link to M4);
  - *Add as my word* opens R2 pre-filled (BR-DOC-04);
  - a compound shows its parts as a hint: "Nebenkosten + Abrechnung".
- **An ambiguous word** («Weg» or «weg») asks which one, before *Add*.
- **A word already mine** says so, and *Keep this sentence* keeps the document's sentence with it (FR-D2-06).
- **Machine-translated meanings** come with #1279 (#1233): Hy-MT2's answers are tappable suggestions, never a pre-filled meaning (#1278). Until then, a word outside the course offers *Add as my word* with its German.

**Functional requirements**
- FR-D2-01 Each lemma is shown in its class from BR-DOC-03; stop words are never marked.
- FR-D2-02 *Add* on a course word puts it in the document queue with its sentence (BR-DOC-04, BR-PLAN-11); the toast says when it starts: "Added der Termin: you'll learn it today" when it joined today's plan, or "… from Thursday" (BR-PLAN-11's *Today*).
- FR-D2-03 The bulk actions add every new course word of the chosen levels in one write, under the cap, and say how many: "Added 9 words: 5 today, 4 from tomorrow".
- FR-D2-04 *I know this* rates the word Easy (W1's *Mark known*), with W1's Undo. *Ignore* takes the mark away for this visit only.
- FR-D2-05 A word outside the course opens R2 with the German, the sentence as *Example*, the document's title as *Where I saw it*, and the meaning (Hy-MT2's, labelled, or empty).
- FR-D2-06 A word already mine gets the sentence added to its contexts, and no second word.
- FR-D2-07 The document and what it found are saved (BR-DOC-05): D3 counts from `document_words`. Reopening it from D3 runs the matcher again on the saved text (under 500 ms), so its marks follow what the learner has learnt since, and what was added stays added.

**Business rules applied.** BR-DOC-03, BR-DOC-04, BR-DOC-05, BR-DOC-07, BR-PLAN-11, BR-STATUS (Mark known), BR-PRIV-01.

**States.**
- **Processing** happens in D1.
- **No new words:** "You know every word in this text" plus the counts, with *Show words I probably know*.
- **Not German:** a warning from D1, with *Continue anyway*.
- **Ambiguous words** are marked with a "?".
- **A very long text** shows its first 20,000 characters, with a note (BR-DOC-02).

**Interactions & motion.**
- Tapping a word opens its card.
- A long press on a new word adds it directly, with haptic feedback: a sighted shortcut, kept out of semantics (a screen reader adds from the card).
- *Add* marks the word "added" with a check. It doesn't animate (#1230): the check needs no motion, so reduce motion has nothing to skip.

**Data.**
- Read: `document_words`, `word_state`, `custom_words`, `settings`, and the matcher's classes.
- Write: `doc_queue`, `word_contexts`, `word_state` (*Mark known*), and `custom_words` through R2.

**Developer notes.**
- The text is built lazily, a paragraph per item of a list, so a 20,000-character text (about 3,000 words) never builds at once. Each marked word is its own semantics node, read as "Termin, new, A1.1, double tap for its card". `perf.py` measures the long text's first frame (`03-domain/document-matcher.md`, *Tests*).
- The bulk bar keeps its height at 200 %, with its counts on a second line.
- Routes and providers are added to `navigation.md` and `state-management.md` with the code.

**Tests.**
- FR-D2-01 to 07, each by its id.
- Goldens in light, dark and glass, phone and tablet (iOS chrome is Later), plus empty and long.
- `tapsInsideTaps`, and the 150/200 % audit in English and Bangla.
- Bulk under the cap: 9 added, 5 today.
