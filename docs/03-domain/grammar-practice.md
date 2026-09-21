# Grammar practice generator

`domain/grammar_item_generator.dart` turns one `grammar_topic` into 3–5 items using only its `rule`, `example_de/en` and `watch_out`.

| Item | Built from | Check |
| --- | --- | --- |
| Gap fill | example_de with the target token blanked (token chosen by matching the topic's headword forms or, failing that, the longest token appearing in `rule`) | `checkGerman` |
| Pick the form | the blank plus 3 options: correct form + 2 distractors (other inflections of the same lemma, or the error named in `watch_out`) | exact |
| Spot the error | example with one token replaced by its `watch_out` error form; learner taps the wrong word | token index |
| Order the sentence | example tokens shuffled as chips (word-order topics only, detected by tags `word-order`, `nebensatz`, `v2`) | sequence |
| Rule recall (C1/C2) | question templated from `rule` ("Which case does X take?") with 4 options | exact |

Topics tagged in the pipeline (`grammar_topics.tags`, comma list, derived from topic title keywords) decide which item types apply. Every topic yields at least Gap fill + Pick the form.

Rating: all correct → Good, one wrong → Hard, more → Again; written to `grammar_state` via FSRS (BR-FSRS-05) and logged in `grammar_practice_log`.
