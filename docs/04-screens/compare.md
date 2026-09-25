# W2 · Compare words

**Purpose.** Render near-synonym sets as a side-by-side table.

**Prototype.** `Compare` (Grund / Ursache / Anlass).

**Reached from.** W1 *Compare*, R1 result rows of set entries. **Leads to.** W1 (tap a column header), L8 (*Quiz these · 5 items*).

**Layout.** Header "Compare · Grund / Ursache / Anlass", subtitle "Near-synonym set from C1.1 · scroll sideways, first column stays". Columns per word (article + headword + step chip); rows Meaning · Register (chips neutral / technical / formal) · With (case/preposition) · Example (with play) · Use it when. Hint "← drag to see Anlass". Buttons *Quiz these · 5 items*, *Add all three to today*.

**Functional requirements**
- FR-W2-01 Set members come from the headword split on " / " (each resolved to a word by `searchKey`) or from `compare_group`.
- FR-W2-02 Register and "With" rows parse the `synonyms_register` and `collocations` cells; missing cells show "—".
- FR-W2-03 *Quiz these* builds a 5-item pick-the-right-word quiz from the members' examples (source `compareSet`).
- FR-W2-04 First column pinned; horizontal scroll; tablet shows all columns.

**Data (#142).** The course has no `compare_group`: a set is one course word whose `german` contains " / " (`Grund / Ursache / Anlass`, `circa / etwa / rund`), unless it is a word-formation entry — a part that is an affix, a letter with a hyphen at its edge ("Adjektive auf -bar / -lich / -sam", "Präfix voll- / durch- / über-"): those seven are not offered by W1 and W2 shows no set for them (`comparesSet`). Phrase sets ("Grüß Gott / Servus / Pfiat di") are sets. `domain/compare_set.dart` builds the columns; `ContentDao.compareSet` reads the set word, its examples, and the course word each member is.

- **Members** (FR-W2-01): the headword split on " / " and on ", " ("legen / liegen, setzen / …"), trimmed, in order, without a trailing "…" ("Lieber …" → *Lieber*). A leading `der`/`die`/`das` in a member ("die Kohle") is its article.
- **Resolving a member**: the course word with the member's `search_key`, not a phrase and not another set, of the set's part of speech unless the set is a phrase (*rund*, "round", is an adjective and *circa / etwa / rund* an adverb set, so it does not resolve); the set's step first, then the course's order. A member written in lower case is never a noun ("klasse" in *prima / super / klasse* is not *die Klasse*). About a third of the members resolve; the set's own cells carry the rest. A homograph of the same part of speech still resolves wrongly (*das Alter*, "age", for "Alter" in *Digga / Alter*; *die Liebe* in the phrase set *Liebe / Lieber …*): a known limit until content.db can tell senses apart.
- **Meaning**: the set's `english` split on " / " — or on " vs. " ("thrifty (positive) vs. stingy (negative)") — when it has one part per member; else the resolved word's `english`; else "—".
- **Register** (chips): the bracketed labels after the member's name in the set's `synonyms_register` — "etwa (neutral)", and "circa/rund (written)" labels both — of two words at most: "teilen (German verbs exist)" is a note, not a register.
- **With**: the set's `collocations`, split on ";", that name the member ("aus diesem Grund"); else the resolved word's own; else "—".
- **Example** (with play): the resolved word's first example; else the first of the set's examples that is about the member. A set sentence is about one member only: of those it names, the one named by its own search key before one named by a prefix or by one of its words, then the longest gap, then the first ("Lieber Tom, …" is *Lieber*'s, not *Liebe*'s; "… gerade erst erschienen" is *gerade erst*'s, not *eben erst*'s); else "—".
- **Use it when**: the note after "member =" in the set's `synonyms_register` ("Ursache = objective cause"); pairs are split at ";" or at a "," that starts the next pair.
- **Step chip**: the resolved word's step, else the set's. The article is the resolved word's, else the member's own.
- "Names" is the cloze gap's test (`domain/cloze.dart`): the member's search key, inflected or not — "Folgen haben" names *Folge*; "ca." does not name *circa*.
- Missing cells read "—" (FR-W2-02). A header opens W1 only for a resolved member. A screen reader reads the table by position, in the page's direction: a row's label, then its members left to right.
- ***Quiz these*** (FR-W2-03): `QuizArgs(direction: compare, source: compareSet, sourceRef: <set uid>, length: 5)`. Every sentence of the members (their words' examples, and the set's each is about) is asked once, the member gapped as `___` — but only a sentence that names one member: where another is named too, its name gives the answer away or the gap is a guess, so it is skipped. The tiles are the members (four at most), the hint the sentence's English. The button counts the items (5 at most) and is closed when there are none. An answer rates the member's course word only when the learner is already learning it (learning or done; not To do, not suspended) — the other quizzes ask learned words only (BR-QUIZ-01), and a set's members are any words. Every answer still counts in L9's score and mistakes, where a compare mistake shows and speaks the member asked for (not the set word that stands in for a member without one). L9's *Retry mistakes* of a compare quiz asks the same set again, as many items as it had mistakes.
- ***Add all to today***: the resolved members still To do and not already in today's plan join it as new words (FR-W1-01's action), with one *Undo* for them all in the snackbar (FR-W1-04); hidden when there are none. The label counts them ("Add all 3 to today": gen-l10n has no `=3` case for "three").
- **Layout** (FR-W2-04): a 96 dp label column and member columns of 170 dp scroll sideways under the pinned labels on a phone; when every column fits (a tablet), they share the width, the subtitle drops "scroll sideways…" and the "← drag to see …" hint goes.

**Tests.** set resolution; quiz args.
