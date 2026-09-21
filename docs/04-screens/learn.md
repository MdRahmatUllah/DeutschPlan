# L1 · Learn (course map)

**Purpose.** Show the whole course as a path and the learner's place on it.

**Prototype.** `Learn`.

**Reached from.** Learn tab; T1 step chip (opens L1, then pushes L2). **Leads to.** L2 (tile), L3 (Grammar library card), L5 (Word categories card), T2 (current tile *Study*).

**Layout.** Sun header "Your course · 1,248 of 5,594 words · 37 of 182 grammar topics" with a course-wide segmented bar. Level bands (A1 · Anfänger, A2 · Grundstufe, B1 · Mittelstufe, B2, C1, C2) each containing two step tiles: code, badge (*Passed* Lime / *Current* Sun / *Exams unlocked* Lagoon / lock for not started), segmented bar, "540 words · 10 grammar topics". The current tile is expanded: "Today · 8 cards left" + *Study*. Below: cards *Grammar library* ("182 topics · 37 learned") and *Word categories* ("Browse by topic across all steps").

**Functional requirements**
- FR-L1-01 Tiles read `stepProgressProvider` (todo/learning/done counts, grammar done, passed = any finished passed exam attempt, unlocked = introduced ≥ `exam_unlock_percent`).
- FR-L1-02 The current tile MUST be scrolled into view on open.
- FR-L1-03 Locked tiles are tappable (browse), never blocked.
- FR-L1-04 *Study* opens T2 with today's open blocks (same as Today's button).

**Business rules.** BR-COURSE-01/04, BR-EXAM-01/04.

**Tests.** FR-L1-01 badge logic; golden.
