# W1 · Word detail

**Purpose.** Everything about one word, plus every action on it. Opens over any tab and returns to exactly where it came from.

**Prototype.** `WordDetail` (sheet over Search for "die Straße").

**Reached from.** R1, T2 overflow, T4, L2 Words, L6, L14, W2 column, deep link `sogda://word/<uid>`. **Leads to.** W2 (*Compare a synonym set*), R2 (*Edit* for custom words), in-app browser.

**Presentation.** Phones: bottom sheet with medium/large detents; tablets: right pane; deep link: full page.
- The sheet opens at the large detent (740 of 844 px, as the artboard draws it). Medium is half the screen. Dragging below medium closes it.
- A tablet is a shortest side of 600 dp or more. Its pane is 420 dp wide, along the right edge, over a scrim that closes it when tapped. The opener stays as it is underneath.
- `?speak=1` on the deep link plays the headword once, when it has loaded (FR-X1-02). It plays on every *Pronounce*, even onto the word already open, and for the same link twice. The router numbers each speaking link (`&arrival=N`), and W1 plays again for a new number, since a link onto the open word keeps its page (#442).

**Layout.** Gender-tinted header strip: article + headword (display), speaker, step chip "A1.1", status chip "Done", and an *Updated* chip after it for a word whose meaning a course update changed in the last 7 days (BR-CONTENT-02, #451). Caption "Nomen · die Straße, -n · /স্ট্রাসে/": the pronunciation guide (`/…/`) is the first meaning language's, or the second's where the first has none (#1119); the Bangla one shows only while Bangla is a meaning language and *Show Bangla pronunciation* is on; with no Bangla chosen it never shows, however the language was set, and a change in M3 reaches the screen at once (#1077). Under a guide in a language with a key (English, Russian, Polish), the line *How to read the pronunciation* (ⓘ, link colour, a 48 dp target) opens the key in a sheet: how that guide's capitals and letters read, written in the guide's language, under a title in the app's (#1122). Once the learner has opened a key, the line is the ⓘ alone (`pron_key_seen`). Bangla's guide has no key, and shows none. Meanings: the first meaning language's, the second's under it, "street, road / রাস্তা"; English stands in where the course has no meaning in the first. **Examples** (all, with play + the translation in the first meaning language, English where the course has none: Bangla, #598). "⟶ die Straße überqueren · auf der Straße · die Straße entlang". "≈ Gasse = narrow street · Weg = path, way". Interference tip callout if any: one for each chosen meaning language whose speakers the course has a tip for (#1119). *Compare a synonym set (…)* when applicable. History caption "Next review in 8 days · reviewed 5 times · last: Good". Actions row: *Add to today* (To-do only) · *Mark known* · *Suspend* / *Resume* · *Reset word* · *Plain card / Cloze card* toggle · *Translate* (if `mt_enabled`) · *Copy* · web chips Duden · DWDS · Wiktionary.

**Filled in by #140** (the artboard shows only a reviewed noun):
- The header is the gender's colour. On paper, the article and headword take that colour's ink. The article is still printed, so the gender is never shown by colour alone. Under glass the header is a wash, and the article keeps its usual colour. A word with no article sits on Oat.
- **The *Updated* chip (#451).** The status chip's look (Oat, bold caption) without a dot; a screen reader hears "Meaning updated". The word lists (T4, L2, L6, R1) do not show it: their rows are dense, and W1 shows it once the word is opened. T2's back shows it too (`study-session.md`).
- The history caption shows only for a word reviewed at least once: "Next review in N days" (or "Due today", "Next review tomorrow") · "reviewed N times" · "last: <rating>". It counts every `review_log` row. A suspended word has no next review, so that part is left out.
- **The actions row (#141).** In this order:
  - *Add to today*, for a To-do word only. The row goes in the active step's plan, or the word's own step's when no step is under way. A word already planned and not studied keeps its one row: a backlog row moves to today (unskipped), and back on *Undo*.
  - *Mark known*, except for a suspended word, which is out of review until resumed (BR-STATUS-03). Its *Undo* takes back only the rating it made: when a rating was made since, on a screen with no *Undo* of its own, of another word (#728) or of this one (an L8 answer, #888), nothing changes.
  - *Suspend*, or *Resume* for a suspended word. *Suspend* takes the word out of today's plan, so Today no longer counts it and the session doesn't serve it (#351). It drops today's open revision, and skips today's open `new` row, which is backlog from tomorrow. Its backlog rows stay, as T4's own *Suspend* keeps them, and a done row is history (#368). T4 lists a suspended word without studying it. A new word needs its row, since only the active step's new words are planned: a word from an earlier step, or one moved to today by *Add to today*, would have no other way back. *Undo* restores exactly what went. *Resume* brings back nothing more; the plan picks the word up again.
  - *Reset word*, when the word has a state to reset.
  - *Copy*.
  - *Translate*, only with `mt_enabled`, into Bangla. A learner with English as their only meaning language isn't offered it, since the examples come in English already.
  - Then the *Plain card / Cloze card* chips, and the Duden · DWDS · Wiktionary chips.
- **Mark known** also closes every open plan row for the word, whether today's or the backlog's, so a known word isn't served again. A skipped row stays skipped, since its day is already complete (BR-PLAN-10). The rating and the rows it closes are one write (#717): a failure saves neither, nor an undo entry.
- **Reset word** clears `word_state`, the word's open plan rows from today on, and every `new` row, done or not. A word with a `new` row is never planned again (`DriftPlanStore.unplannedWords`), and a reset word is To do again, so it goes back into the pool. Done revisions stay, because they are the day's history, and so do `daily_stats` and `review_log`; a rating from before the reset isn't one of BR-FSRS-06's two in a row (#700). *Undo* restores exactly what went.
- **Undo** restores the row as it was. For a word never met, that means no `word_state` row at all.
- **One action at a time.** A second tap while one is running does nothing.
- **A note or a comparison** (BR-CONTENT-04, #630: "beantworten — Präfix be-", "machen ↔ tun") has no status chip, and none of *Add to today*, *Mark known*, *Suspend* / *Resume* or the card chips: it is never studied. *Reset word* (for one met before it was a note), *Copy*, *Translate* and the web chips stay. The word lists (L2, L6, R1) show it without a status chip too; L2 lists it under *All* only.

**Functional requirements**
- FR-W1-01 *Add to today* inserts a `plan_items(today, uid, 'new')` row for the active step (allowed for any step's To-do word).
- FR-W1-02 *Mark known* = rate Easy; *Suspend* / *Resume* per BR-STATUS-03; *Reset word* deletes `word_state` and future `plan_items` for the uid after a confirm (and its `new` rows, above).
- FR-W1-03 Card mode toggle writes `word_state.card_mode` and `card_mode_manual = 1`, so BR-FSRS-06's rule keeps the choice from then on. *Undo* and *Reset word* give the card back to the rule.
- FR-W1-04 Every action shows a snackbar with *Undo*; audio never closes the sheet.
- FR-W1-05 *Translate* runs the examples through the translator (cached) and shows results inline.
- A link to a word's old uid, written before a course update re-keyed it (a widget or reminder link tapped before the next launch rewrites it), opens the word it became, by the course's PIPE-09 `aliases` (#854).
- FR-W1-06 *Compare* is offered when the headword contains " / " or the word has a `compare_group` (from register notes). content.db has no `compare_group` yet, so today only the " / " rule applies — and not to a word-formation entry whose parts are affixes ("Adjektive auf -bar / -lich / -sam"), which W2 has nothing to compare in (#142, `compare.md`).

**Data.** `wordDetailProvider(uid)` (word + state + examples + tips + last review).

**Tests.** action side-effects on tables; sheet returns to the opener with scroll preserved (widget test).
