# W1 · Word detail

**Purpose.** Everything about one word, plus every action on it. Opens over any tab and returns to exactly where it came from.

**Prototype.** `WordDetail` (sheet over Search for "die Straße").

**Reached from.** R1, T2 overflow, T4, L2 Words, L6, L14, W2 column, deep link `deutschplan://word/<uid>`. **Leads to.** W2 (*Compare a synonym set*), R2 (*Edit* for custom words), in-app browser.

**Presentation.** Phones: bottom sheet with medium/large detents; tablets: right pane; deep link: full page.

**Layout.** Gender-tinted header strip: article + headword (display), speaker, step chip "A1.1", status chip "Done". Caption "Nomen · die Straße, -n · /স্ট্রাসে/". Meanings "street, road / রাস্তা". **Examples** (all, with play + translation). "⟶ die Straße überqueren · auf der Straße · die Straße entlang". "≈ Gasse = narrow street · Weg = path, way". Interference tip callout if any. *Compare a synonym set (…)* when applicable. History caption "Next review in 8 days · reviewed 5 times · last: Good". Actions row: *Add to today* (To-do only) · *Mark known* · *Suspend* / *Resume* · *Reset word* · *Plain card / Cloze card* toggle · *Translate* (if `mt_enabled`) · *Copy* · web chips Duden · DWDS · Wiktionary.

**Functional requirements**
- FR-W1-01 *Add to today* inserts a `plan_items(today, uid, 'new')` row for the active step (allowed for any step's To-do word).
- FR-W1-02 *Mark known* = rate Easy; *Suspend* / *Resume* per BR-STATUS-03; *Reset word* deletes `word_state` and future `plan_items` for the uid after a confirm.
- FR-W1-03 Card mode toggle writes `word_state.card_mode`.
- FR-W1-04 Every action shows a snackbar with *Undo*; audio never closes the sheet.
- FR-W1-05 *Translate* runs the examples through the translator (cached) and shows results inline.
- FR-W1-06 *Compare* is offered when the headword contains " / " or the word has a `compare_group` (from register notes).

**Data.** `wordDetailProvider(uid)` (word + state + examples + tips + last review).

**Tests.** action side-effects on tables; sheet returns to the opener with scroll preserved (widget test).
