# L4 · Grammar topic

**Purpose.** Learn one grammar rule.

**Prototype.** `GrammarTopic`.

**Reached from.** L2 Grammar tab, L3, T1 grammar card, L14 *See rule*. **Leads to.** L15 (*Practise this rule · 5 items*), previous/next topic.

**Layout.** Header: step chip, "Topic 4 of 10", title. **Rule** (bodyLarge, inline code for forms). **Examples**: each German example with play + translation. **Watch out** callout (Tangerine bar). Buttons *Practise this rule · 5 items* (primary) and *Mark as learned*. Footer: previous/next topic titles as arrows.

**Functional requirements**
- FR-L4-01 *Mark as learned* sets `grammar_state.status = learning` with an initial FSRS review rated Good (so it enters the schedule).
- FR-L4-02 *Practise* opens L15 for this topic; completing the set also marks it learned.
- FR-L4-03 Play buttons use TTS on `example_de`.
- FR-L4-04 Prev/next stay within the same step.

**Tests.** FR-L4-01 schedule entry.
