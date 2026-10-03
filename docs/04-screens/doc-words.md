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
   - a *Show words I probably know* switch (`doc_show_probably_known`). To a screen reader it is one node, «Show words I probably know, switch», as M3's switches are; the legend below reads apart from it (#1309).
2. **The text,** as extracted, scrollable, in reading size:
   - new course words have an underline and a soft fill in their level's colour (the CEFR colours of L1);
   - words that are mine carry a small "My word" mark;
   - words outside the course get a dotted underline;
   - probably-known words are dimmed when the switch is on, and plain otherwise;
   - a word that appears several times is marked each time, and its card lists every sentence.
3. **The bulk bar,** pinned at the bottom:
   - *Add my level* and *Add my level and one above*, side by side (one height for the pair), stacked above 100 % text. A button that would add what *Add all new* adds is left out (#1294);
   - *Add all new*, and the number each would add;
   - the cap note, "5 a day: the other 7 start tomorrow or later" (BR-PLAN-11), when more are new than today takes. This visit's adds that start today take their slots off it (#1294), and so do the words already waiting in the queue, which today's free slots take first (BR-PLAN-11, #1341): after the backlog pause lifts mid-day, those fill today, and the note says the rest start tomorrow or later. When no day can be said, it says the words wait instead (#1334, `PlanEngine.docQueueHold`, the same rule as *Add*'s): at a cap of 0 (the setting, read at once: no later day takes them), "0 a day from documents: the other 16 wait in your queue until you raise it in Settings"; under the backlog pause (BR-PLAN-07), "Backlog first: what you add waits in your queue until it's cleared";
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
  - Hy-MT2's meaning, the first meaning language's bare-word answer, labelled "Machine-translated" (`docWordsCardMachine`). With none, and only while Hy-MT2 isn't on the phone and the phone has the memory for it (`translationDownloadableProvider`, #1300), the card offers "No meaning yet: download Hy-MT2 translation" (`docWordsCardNoMeaning`), a link to M4. With the model there (translation off in M3, or a run that found nothing) or below the floor, a download would bring nothing, so the card says nothing of a meaning. Nothing shows while it runs (#1233, `outsideMeaningProvider`);
  - *Add as my word* opens R2 pre-filled (BR-DOC-04);
  - a compound shows its parts as a hint: "Nebenkosten + Abrechnung".
- **An ambiguous word** («Weg» or «weg») asks which one, before *Add*. Each choice says its step and first meaning, «ausfallen · A2.2 · to be cancelled», since two readings can share a spelling and an article. Its mark takes the lowest reading's level, the one a learner meets first (#1294).
- **A word already mine** says so, and *Keep this sentence* keeps the document's sentence with it (FR-D2-06).
- **Machine-translated meanings** (#1233, #1300): on the card, the first language's answer, labelled. In R2 they're tappable suggestions, never a pre-filled meaning (#1278): every language's bare-word answer, then the in-sentence ones as «here: …».

**Functional requirements**
- FR-D2-01 Each lemma is shown in its class from BR-DOC-03; stop words are never marked.
- FR-D2-02 *Add* on a course word puts it in the document queue with its sentence (BR-DOC-04, BR-PLAN-11); the toast says when it starts: "Added der Termin: you'll learn it today" when it joined today's plan, or "… from Thursday" (BR-PLAN-11's *Today*).
- FR-D2-03 The bulk actions add every new course word of the chosen levels in one write, under the cap, and say how many: "Added 9: 5 today, the rest later"; "Added 5, all for today" when every one starts today; "Added 25: they start tomorrow or later" when today's slots are taken; and "Added 25: they wait in your queue" while no day can be said (the backlog pause, a cap of 0), as a single *Add* says (#1311).
- FR-D2-04 *I know this* rates the word Easy (W1's *Mark known*), with W1's Undo. *Ignore* takes the mark away for this visit only.
- FR-D2-05 A word outside the course opens R2 with the German, the sentence as *Example* and the document's title as *Where I saw it*. The meaning is the learner's to write: Hy-MT2's answers come as labelled suggestions under the empty meaning field, never filled in, and none without a model (#1278, #1279, #1300).
- FR-D2-06 A word already mine gets the sentence added to its contexts, and no second word.
- FR-D2-07 The document and what it found are saved (BR-DOC-05): D3 counts from `document_words`. Reopening it from D3 runs the matcher again on the saved text (under 500 ms), so its marks follow what the learner has learnt since, and what was added stays added.

**Business rules applied.** BR-DOC-03, BR-DOC-04, BR-DOC-05, BR-DOC-07, BR-PLAN-11, BR-STATUS (Mark known), BR-PRIV-01.

**States.**
- **Processing** happens in D1.
- **No new words:** "You know every word in this text" plus the counts, with *Show words I probably know*.
- **Not German:** a warning from D1, with *Continue anyway*.
- **Ambiguous words** are marked with a "?" (a small circled one after the word, on the word's line, #1333), and a screen reader hears "fällt, new, A2, two readings". Once a reading is added the word is settled: the check takes the "?"'s place.
- **A very long text** shows its first 20,000 characters, with a note (BR-DOC-02).

**Interactions & motion.**
- Tapping a word opens its card.
- A long press on a new word adds it directly, with haptic feedback: a sighted shortcut, kept out of semantics (a screen reader adds from the card). On a word already added it does nothing.
- A word's chip and its check or "?" stay on the word's line, at any width and text size, unless the chip and its word together are wider than a line (#1339). They are text, not widgets inside the text, since a line may always break on either side of one of those: the check and the "?" are the icon font's glyphs, and the chip is its label between no-break spaces, its outline drawn around it, the artboard's size. A screen reader doesn't read them: the word's label says what they show.
- Back from R2 after *Add as my word*, the document is read again, so the word shows as mine.
- *Add* marks the word "added" with a check. It doesn't animate (#1230): the check needs no motion, so reduce motion has nothing to skip.

**Data.**
- Read: `document_words`, `word_state`, `custom_words`, `settings`, and the matcher's classes.
- Write: `doc_queue`, `word_contexts`, `word_state` (*Mark known*), and `custom_words` through R2.

**Developer notes.**
- The text is built lazily, a paragraph per item of a list, so a 20,000-character text (about 3,000 words) never builds at once. Each marked word is its own semantics node, read as "Termin, new, A1", and TalkBack adds its own "Double-tap to activate", once (agent-1's review: a "double tap" in the label would repeat it). The plain text between two marked words is a node too, unless it has nothing to hear (a space or a full stop): then it has no label, and a screen reader doesn't stop on it (#1344). Only there: beside plain text (a known word, or a probably known one while hidden) such a run is part of that node, and keeps its spaces and commas, «am kommenden Montag, fällt» (#1361). `perf.py` measures the long text's first frame (`03-domain/document-matcher.md`, *Tests*).
- The bulk bar keeps its height at 200 %, with its counts on a second line.
- Routes and providers are added to `navigation.md` and `state-management.md` with the code.

**Tests.**
- FR-D2-01 to 07, each by its id.
- Goldens in light, dark and glass, phone and tablet (iOS chrome is Later), plus empty and long.
- `tapsInsideTaps`, and the 150/200 % audit in English and Bangla.
- Bulk under the cap: 9 added, 5 today.
