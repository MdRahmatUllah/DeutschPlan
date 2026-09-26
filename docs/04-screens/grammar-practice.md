# L15 · Grammar practice

**Purpose.** Practise a grammar rule with items generated from its examples.

**Prototype.** `GrammarPractice` (Pick the form).

**Reached from.** L4, L2 Grammar tab (*Practise all due*), T1 Grammar due card, inline in T2. **Leads to.** L4 (*See rule*), T6 if it completes the day, else back.

**Layout.** Top: close, topic title, "3 / 5", progress strip. Item types: Gap fill (text + umlaut row) · Pick the form (3 option tiles with labels like "Konjunktiv II · polite", "your pick · Präsens", "Präteritum") · Spot the error (tappable tokens) · Order the sentence (chips) · Rule recall (4 options). Feedback line: "Not quite — the polite form is *Könnten*. Rule: könnte / würde + infinitive at the end of the sentence." with *See rule*; *Next*.

**Typing at large text** (#557, as L8's #554): past 130 % with the keyboard up, the gap's field and umlaut row alone filled the room above it and the sentence scrolled away. The header gives up its row (close, the topic and "3 / 5"; its colour stays behind the status bar), and so does *Next*, which is off until the answer is checked. The sentence and its translation then show above the field. Both come back when the keyboard goes, and *Next* stays once the answer is checked. At 130 % and below nothing changes.

**Functional requirements**
- FR-L15-01 Items from `GrammarItemGenerator` (`03-domain/grammar-practice.md`); 3–5 per topic; seeded per (topic, day).
- FR-L15-02 Immediate feedback; the rule line shows on a wrong answer. A typed gap fill that is *almost* (BR-ANS-01) says "Almost · it's hätte", as T2's cloze does, with no rule line, and counts as right for the topic's rating (BR-FSRS-05): a set whose only misses are *almost* is Good (the lead's call, #345).
- FR-L15-03 On the last item the topic is rated as a whole (BR-FSRS-05), written to `grammar_state` and `grammar_practice_log`.
- FR-L15-04 Multiple due topics run back to back with a short banner between them.

**Tests.** generator produces ≥ 2 item types for every topic in content (data test); rating rule.
