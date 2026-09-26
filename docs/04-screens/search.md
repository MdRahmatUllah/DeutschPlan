# R1 · Search

**Purpose.** Look up any word fast — exact first, then similar, then in sentences — and hand off to the web when the course lacks it.

**Prototype.** `Search` (results for "Straße"), `SearchIdle`, `SearchNone` ("Wohnungsgeberbestätigung").

**Reached from.** Search tab; search icon on L2/L6 (pre-filtered). **Leads to.** W1 (row), W2 (compare rows), R2 (*Add a word I found* / *Add "…" as my word*), in-app browser (web chips).

**Layout.** Raspberry header with the search field "Search German, English or Bangla" (clear button; removable filter chip when pre-filtered). Web row (when a query exists): Duden · DWDS · Wiktionary · Linguee · Google chips. Results grouped: **Exact match · 1**, **Starts with · 2**, **Similar words · 1**, **In sentences · 5** (sentence with the query highlighted, translation, "die Straße · A1.1"). Rows: article-coloured headword, meaning, step chip, status chip, play icon.

**Idle.** "Recent" chips (Clear), "My words · 3" list ("das Pfandflasche — deposit bottle · Rewe receipt · seen 3× · My word"), *Add a word I found*.

**No results.** "Not in the course — 5,593 words, none spelled like this. Typos are tolerated, so it is probably a compound or a rare word."; enlarged web chips; *Add "…" as my word*; footnote "Opens the web in an in-app browser — the only time DeutschPlan goes online."

**Filled in by #137:**
- **FR-R1-07.** The status chips (To do · Learning · Done) and one chip per step in the results each narrow the words. Step chips show only when the results span more than one step. A new search starts unfiltered. A second tap clears a chip. Status and step apply together. A status chip hides the sentences, which have no status.
- **L2's step.** It shows as a chip under the field that keeps words and sentences to that step, in the search itself, before the caps. Tapping the chip removes it by going to `/search`, so a second trip from the step brings it back.
- **Between keystrokes** the last results stay up until the next query answers.
- **FR-R1-06.** The web chips open through `url_launcher`'s in-app browser view, which is a Custom Tab on Android and `SFSafariViewController` on iOS. That is what `flutter_custom_tabs` would give, with no new dependency.
- **In sentences.** The words FTS matched are marked in Sun, from `highlight()`.

**Filled in by #138 (idle):**
- **FR-R1-04.** A search counts once the learner commits to it: the search key, a result or web chip opened, or a recent chip tapped. A pause in typing doesn't count. The same search again moves to the front, compared without case, and the oldest past ten goes. `recent_searches` is a JSON list, newest first. *Clear* forgets them all, and a screen reader hears it as "Clear recent searches".
- A recent chip fills the field and searches at once.
- **My words** lists `custom_words` newest first: the headword with its article's colour, then "meaning · where it was seen · seen N×". The count shows from the second time. A row opens R2 on that word (`/search/add/:id`). A screen reader hears each row as one button: its headword, its line and *My word* (#445).
- With no recents or no words of one's own, that heading is left out, and *Add a word I found* (R2, `/search/add`) is always there.

**Filled in by #139 (no results):**
- The page shows when a search of the whole course finds no word and no sentence. Kept to L2's step, an empty result says nothing about the course, so it stays the list with the web row.
- The count is the course's own, `meta.word_count`, formatted for the language ("5,593"). A course without it says "None of the course words…".
- The web chips are the five of FR-R1-06 at 44 dp (`DpChip(large: true)`, a pill under glass). A chip, like *Add "…" as my word*, counts as a search (FR-R1-04).
- *Add "…" as my word* opens R2 with the word filled in: `/search/add?german=…`.
- A word the learner has saved already is not offered again (#396): when one of `custom_words` keys as the query does (the exact tier's `search_key` or `search_key_alt`, so "Quarkbrotchen" finds the saved "Quarkbrötchen"), the page says "Already one of my words" and *Open "das Quarkbrötchen"* opens it in R2 (`/search/add/:id`) instead of *Add "…" as my word*.

**Functional requirements**
- FR-R1-01 Results per `03-domain/search.md`, debounced 120 ms, isolate-run, < 50 ms per query.
- FR-R1-02 Enter/search key opens the first exact match's detail.
- FR-R1-03 Play icon pronounces without opening.
- FR-R1-04 Recent searches: last 10, persisted; cleared by *Clear*.
- FR-R1-05 Autofocus only when the tab is opened fresh; returning keeps query and scroll.
- FR-R1-06 Web chips open in the in-app browser (`url_launcher`, above); no request is made by the app.
- FR-R1-07 Filter chips (step/status) appear when > 10 results.

**Tests.** tier ordering with fixtures ("strase" → Straße in Similar); no-results state; recent list.
