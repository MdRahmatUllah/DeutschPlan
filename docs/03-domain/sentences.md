# Practice sentence picker

`domain/sentence_picker.dart`, persisted through `sentence_log`.

1. Candidates: `word_examples` of words with status learning/done (not suspended), excluding (word_uid, ord) shown within `sentence_repeat_gap_days`; random 400.
2. Coverage score: share of the sentence's tokens (len > 2) whose `searchKey` is a learned word's key or starts with one of at least 4 letters that is no function word (stem match, as the cloze has it: "er" is no stem of "erklärt", #654; nor "sie" of "sieben", "man" of "Mann", or "sich" of "sicher", #842) — plus a small seeded jitter.
3. Pick `sentence_count` sentences with distinct headwords, highest coverage first, skipping a sentence where the headword can't be found for T5's underline (`clozeGap`, #325); persist to `sentence_log(shown_on = today)`. The write re-reads the day in its transaction: a pick that raced another (Today, T3 and T5 all call `forDay`) returns the set recorded first rather than adding a second (#750).
4. Ratings: Understood / Partly / Not yet → `self_rating` 3/2/1; Not yet also rates the headword Hard (BR-FSRS-04), with the sentence's first answer only: a changed answer changes `self_rating`, not the word (#662). Tapping a word opens its course meaning; unknown words use the translation model when enabled.
