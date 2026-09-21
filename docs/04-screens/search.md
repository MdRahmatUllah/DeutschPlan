# R1 · Search

**Purpose.** Look up any word fast — exact first, then similar, then in sentences — and hand off to the web when the course lacks it.

**Prototype.** `Search` (results for "Straße"), `SearchIdle`, `SearchNone` ("Wohnungsgeberbestätigung").

**Reached from.** Search tab; search icon on L2/L6 (pre-filtered). **Leads to.** W1 (row), W2 (compare rows), R2 (*Add a word I found* / *Add "…" as my word*), in-app browser (web chips).

**Layout.** Raspberry header with the search field "Search German, English or Bangla" (clear button; removable filter chip when pre-filtered). Web row (when a query exists): Duden · DWDS · Wiktionary · Linguee · Google chips. Results grouped: **Exact match · 1**, **Starts with · 2**, **Similar words · 1**, **In sentences · 5** (sentence with the query highlighted, translation, "die Straße · A1.1"). Rows: article-coloured headword, meaning, step chip, status chip, play icon.

**Idle.** "Recent" chips (Clear), "My words · 3" list ("das Pfandflasche — deposit bottle · Rewe receipt · seen 3× · My word"), *Add a word I found*.

**No results.** "Not in the course — 5,594 words, none spelled like this. Typos are tolerated, so it is probably a compound or a rare word."; enlarged web chips; *Add "…" as my word*; footnote "Opens the web in an in-app browser — the only time DeutschPlan goes online."

**Functional requirements**
- FR-R1-01 Results per `03-domain/search.md`, debounced 120 ms, isolate-run, < 50 ms per query.
- FR-R1-02 Enter/search key opens the first exact match's detail.
- FR-R1-03 Play icon pronounces without opening.
- FR-R1-04 Recent searches: last 10, persisted; cleared by *Clear*.
- FR-R1-05 Autofocus only when the tab is opened fresh; returning keeps query and scroll.
- FR-R1-06 Web chips open `flutter_custom_tabs`; no request is made by the app.
- FR-R1-07 Filter chips (step/status) appear when > 10 results.

**Tests.** tier ordering with fixtures ("strase" → Straße in Similar); no-results state; recent list.
