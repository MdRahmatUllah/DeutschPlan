# W1 · Word detail

**Purpose.** Everything about one word, plus every action on it. Opens over any tab and returns to exactly where it came from.

**Prototype.** `WordDetail` (sheet over Search for "die Straße").

**Reached from.** R1, T2 overflow, T4, L2 Words, L6, L14, W2 column, deep link `deutschplan://word/<uid>`. **Leads to.** W2 (*Compare a synonym set*), R2 (*Edit* for custom words), in-app browser.

**Presentation.** Phones: bottom sheet with medium/large detents; tablets: right pane; deep link: full page.
- The sheet opens at the large detent (740 of 844 px, as the artboard draws it). Medium is half the screen. Dragging below medium closes it.
- A tablet is a shortest side of 600 dp or more. Its pane is 420 dp wide, along the right edge, over a scrim that closes it when tapped. The opener stays as it is underneath.
- `?speak=1` on the deep link plays the headword once, when it has loaded (FR-X1-02).

**Layout.** Gender-tinted header strip: article + headword (display), speaker, step chip "A1.1", status chip "Done". Caption "Nomen · die Straße, -n · /স্ট্রাসে/". Meanings "street, road / রাস্তা". **Examples** (all, with play + translation). "⟶ die Straße überqueren · auf der Straße · die Straße entlang". "≈ Gasse = narrow street · Weg = path, way". Interference tip callout if any. *Compare a synonym set (…)* when applicable. History caption "Next review in 8 days · reviewed 5 times · last: Good". Actions row: *Add to today* (To-do only) · *Mark known* · *Suspend* / *Resume* · *Reset word* · *Plain card / Cloze card* toggle · *Translate* (if `mt_enabled`) · *Copy* · web chips Duden · DWDS · Wiktionary.

**Filled in by #140** (the artboard shows only a reviewed noun):
- The header is the gender's colour. On paper, the article and headword take that colour's ink. The article is still printed, so the gender is never shown by colour alone. Under glass the header is a wash, and the article keeps its usual colour. A word with no article sits on Oat.
- The history caption shows only for a word reviewed at least once: "Next review in N days" (or "Due today", "Next review tomorrow") · "reviewed N times" · "last: <rating>". It counts every `review_log` row. A suspended word has no next review, so that part is left out.
- **The actions row (#141).** In this order:
  - *Add to today*, for a To-do word only. The row goes in the active step's plan, or the word's own step's when no step is under way.
  - *Mark known*.
  - *Suspend*, or *Resume* for a suspended word.
  - *Reset word*, when the word has a state to reset.
  - *Copy*.
  - *Translate*, only with `mt_enabled`.
  - Then the *Plain card / Cloze card* chips, and the Duden · DWDS · Wiktionary chips.
- **Mark known** also closes an open plan row for the word, whether today's or the backlog's, so a known word isn't served as new.
- **Reset word** clears `word_state` and the word's plan rows from today on. Rows already done stay, because they are the day's history, and `review_log` stays. *Undo* restores exactly what went.
- **One action at a time.** A second tap while one is running does nothing.

**Functional requirements**
- FR-W1-01 *Add to today* inserts a `plan_items(today, uid, 'new')` row for the active step (allowed for any step's To-do word).
- FR-W1-02 *Mark known* = rate Easy; *Suspend* / *Resume* per BR-STATUS-03; *Reset word* deletes `word_state` and future `plan_items` for the uid after a confirm.
- FR-W1-03 Card mode toggle writes `word_state.card_mode`.
- FR-W1-04 Every action shows a snackbar with *Undo*; audio never closes the sheet.
- FR-W1-05 *Translate* runs the examples through the translator (cached) and shows results inline.
- FR-W1-06 *Compare* is offered when the headword contains " / " or the word has a `compare_group` (from register notes). content.db has no `compare_group` yet, so today only the " / " rule applies (#142).

**Data.** `wordDetailProvider(uid)` (word + state + examples + tips + last review).

**Tests.** action side-effects on tables; sheet returns to the opener with scroll preserved (widget test).
