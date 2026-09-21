# L15 · Grammar practice

**Purpose.** Practise a grammar rule with items generated from its examples.

**Prototype.** `GrammarPractice` (Pick the form).

**Reached from.** L4, L2 Grammar tab (*Practise all due*), T1 Grammar due card, inline in T2. **Leads to.** L4 (*See rule*), T6 if it completes the day, else back.

**Layout.** Top: close, topic title, "3 / 5", progress strip. Item types: Gap fill (text + umlaut row) · Pick the form (3 option tiles with labels like "Konjunktiv II · polite", "your pick · Präsens", "Präteritum") · Spot the error (tappable tokens) · Order the sentence (chips) · Rule recall (4 options). Feedback line: "Not quite — the polite form is *Könnten*. Rule: könnte / würde + infinitive at the end of the sentence." with *See rule*; *Next*.

**Functional requirements**
- FR-L15-01 Items from `GrammarItemGenerator` (`03-domain/grammar-practice.md`); 3–5 per topic; seeded per (topic, day).
- FR-L15-02 Immediate feedback; the rule line shows on a wrong answer.
- FR-L15-03 On the last item the topic is rated as a whole (BR-FSRS-05), written to `grammar_state` and `grammar_practice_log`.
- FR-L15-04 Multiple due topics run back to back with a short banner between them.

**Tests.** generator produces ≥ 2 item types for every topic in content (data test); rating rule.
