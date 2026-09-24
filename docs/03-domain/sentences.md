# Practice sentence picker

`domain/sentence_picker.dart`, persisted through `sentence_log`.

1. Candidates: `word_examples` of words with status learning/done (not suspended), excluding (word_uid, ord) shown within `sentence_repeat_gap_days`; random 400.
2. Coverage score: share of the sentence's tokens (len > 2) whose `searchKey` is a learned word's key or starts with one (stem match) — plus a small seeded jitter.
3. Pick `sentence_count` sentences with distinct headwords, highest coverage first, skipping a sentence where the headword can't be found for T5's underline (`clozeGap`, #325); persist to `sentence_log(shown_on = today)`.
4. Ratings: Understood / Partly / Not yet → `self_rating` 3/2/1; Not yet also rates the headword Hard (BR-FSRS-04). Tapping a word opens its course meaning; unknown words use the translation model when enabled.
