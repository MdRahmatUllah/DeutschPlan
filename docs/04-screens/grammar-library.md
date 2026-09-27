# L3 · Grammar library

**Purpose.** Browse all 182 grammar topics across the course.

**Prototype.** `GrammarLibrary`.

**Reached from.** L1. **Leads to.** L4.

**Layout.** Filter chips All · 182, Not learned yet · 145, Due · 2. Sticky level headers (A1 · Anfänger …); rows: topic title + step chip; status dot. The dot has no caption, so a screen reader hears its state in L2's words: "due today", "next practice in 4 d", "Suspended" or "not learned yet" (#668).

**Functional requirements**
- FR-L3-01 Grouped by `level_code`, ordered by `seq`.
- FR-L3-02 Filters read `grammar_state` (status, due ≤ today).

**Tests.** filter counts; each dot's state in the row's label (#668).
