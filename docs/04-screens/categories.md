# L5 · Categories and L6 · Category words

**Purpose.** Browse vocabulary by topic across all steps.

**Prototype.** `Categories`, `CategoryWords`.

**Reached from.** L1 → L5 → L6. **Leads to.** W1 (row), L7 (*Quiz* in L6 header), R1 (search icon pre-filtered).

**L5 layout.** Header copy "Every word belongs to one category across all 12 steps." Two-column grid of category cards: name, "412 words", mini segmented bar; card tile colour cycles through the palette.

**L6 layout.** Header "Wohnen & Haushalt" + *Quiz* button; subtitle "412 words · A1.1 → C2.2 · sorted by step, then frequency"; level filter chips All · A1 · A2 · B1 · B2+; rows with step chip and status chip.

**Functional requirements**
- FR-L5-01 Counts and status bars per category from a single grouped query.
- FR-L6-01 Order: `sublevel ord`, then `freq DESC`, then `seq`.
- FR-L6-02 *Quiz* opens L7 with source `category(id)`.

**Tests.** ordering; category quiz args.
