# Grammar practice generator

`domain/grammar_item_generator.dart` turns one `grammar_topic` into 3–5 items from its `rule`, `example_de/en` and `watch_out`, checked against what the rest of the course says (#330: its words, their `forms`, and `word_examples`).

| Item | Built from | Check |
| --- | --- | --- |
| Gap fill | example_de with the target token blanked: the word that best practises the rule (see below) | `checkGerman` |
| Pick the form | a blank in *another* sentence than the gap fill's, plus 3 options: the correct form + 2 distractors (other inflections of the same lemma, or the error named in `watch_out`) | exact |
| Spot the error | example with one token replaced by its `watch_out` error form; learner taps the wrong word | token index |
| Order the sentence | example tokens shuffled as chips (word-order topics only, detected by tags `word-order`, `nebensatz`, `v2`) | sequence |
| Rule recall (C1/C2) | question templated from `rule` ("Which case does X take?") with 4 options | exact |

Topics tagged in the pipeline (`grammar_topics.tags`, comma list, derived from topic title keywords) decide which item types apply. Every topic with a German example yields at least Gap fill + Pick the form. A topic with none ("—") practises its rule, which is in English: gap fills, one per rule sentence up to three, and the rule recall at C1/C2, but no Pick the form (#386).

Details #330 settles:
- **The blank.** Each word is scored: one point each time the `rule` or `watch_out` names it (hyphen dropped, so "an-" names *an*), one more for a form they name ("Könnten" for "könnte"), two for a member of an inflecting class (article, possessive, *sein*/*haben*/*werden*…) when the topic is tagged for forms, and three fewer for a pronoun, unless the topic is tagged `pronoun` or its title names it ("Sie vs du"). The best wins, the longer of two alike. So *Separable verbs* blanks *ein*/*an*, *Clock time* *halb* or *am*, and *Genitive* *meines*.
- **Pick the form's sentence.** It is never the gap fill's, whose feedback would answer it. It uses the example's next sentence when there is one. Else it borrows a course example (`word_examples`) with a word of the gap's sentence: first a word the rule or *watch out* points at (so *Clock time* doesn't borrow "hängt am Ofen"), the best-scored and then the longest first; any word only after that.
- **Its word** has two *real* wrong forms, where the sentence has one. Real means its classes' other members (the inflecting ones above, plus the prepositions, *am/im/um*, the da-/wo-compounds and the question words), the forms the rule names, or an ending or umlaut changed into a form the course uses. A made-up form ("warteen", "Montager") is only a last resort, for a word with nothing better. Topics with no example ask no Pick the form at all (#386), so across the shipped course none is left outside the course, against 71 % before #330. `grammar_item_generator_test.dart` holds that at 5 %. The question words are not a choice set: "[Wo] kann man hier parken?" also takes *wann* and *warum*.
- The course's words and examples are read once per open database (`data/repositories/course_text.dart`, about 17,000 rows): L4, L15 and the mocks share them.

Rating: all correct → Good, one wrong → Hard, more → Again; written to `grammar_state` via FSRS (BR-FSRS-05) and logged in `grammar_practice_log`.
