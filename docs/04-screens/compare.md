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

**Tests.** set resolution; quiz args.
