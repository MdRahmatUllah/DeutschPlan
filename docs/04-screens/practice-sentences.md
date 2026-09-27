# T5 · Practice sentences

**Purpose.** Read and hear learned words in context.

**Prototype.** `Sentences`.

**Reached from.** T1 Sentences card, T3. **Leads to.** T6 if this completes the day, else T1; W1 mini sheet on word tap.

**Layout.** Full-screen modal, Raspberry band "Sentence 1 of 3", page dots. Sentence in bodyLarge with the target word underlined in its gender colour; big play button (long-press = slow); *Show translation* → EN and/or BN; hint "Tap any word for its meaning. “Not yet” brings the word back sooner."; rating chips *Understood* (Lime) · *Partly* (Tangerine) · *Not yet* (Coral).

**Functional requirements**
- FR-T5-01 Sentences come from `SentencePicker.forDay` and are stable for the day (`sentence_log`). T5 keeps the day it opened on: past midnight the learner pages through the same sentences, and their ratings stay that day's (#660). The day's set is recorded once: Today, T3 and T5 all ask for it, and a pick that finds the day already recorded when it writes returns that set instead of adding its own (#750).
- FR-T5-02 Rating writes `self_rating`; *Not yet* rates the headword Hard (BR-FSRS-04). A rated sentence shows its answer chosen and can be answered again: that changes `self_rating` only. The headword is rated with the sentence's first answer, so *Not yet* tapped again, or chosen after another answer, rates nothing more, and a first *Not yet*'s Hard stays when the answer changes (#662).
- FR-T5-03 Tapping a token opens a mini sheet: course meaning if the token (stem) matches a word; otherwise translation if `mt_enabled`, else Duden link.
  - How a token matches a word (#324): a word (not a phrase) keyed as it is; else a form the course gives in `words.forms` ("ist" is *sein*, "gibt" *geben*, "Häuser" *Haus*; a perfect's auxiliary, a superlative's "am", a split verb's stem and particle — "steht" of "steht auf" — don't count, nor do a phrase's forms); else a phrase keyed as it is; else a word it is plus a noun or adjective ending ("Wohnungen", "leichter"; not -t or -st: "erfolgt" is not *Erfolg*). A compound is not its first part: "Hausfrau" is not *Haus*; a particle is not its verb: "zurück" is not *zurückrufen*. Else, for the sentence's first word or a small-letter word ending in -e, the verb it is the du-imperative or first person of: "Mach" is *machen*, "Sei" *sein*, "habe" *haben* (#724). Elsewhere a bare stem is most often an adjective or a particle ("leid", "wahr", "teil") and a capital a noun ("Stimme" is not *stimmen*), so they stay as they are. A separable verb's particle at the clause's end isn't looked for: "Mach die Lampe an." is *machen*, not *anmachen*. A noun the course lacks may open a verb when it starts the sentence: "Stille" is taken for *stillen*, "Anstoß" for *anstoßen* (2 of the 35 first words the step matches in the course; a `ponytail:`). The forms are indexed in memory on the first tap.
- FR-T5-04 Swipe or *Next* advances; the last rating closes to T6/T1.
- A screen reader hears the sentence whole, in a German voice, then each word as a node to tap; the spaces and punctuation between the words are not nodes of their own (#741).

**Tests.** FR-T5-01 same set on reopen; FR-T5-02 Hard rating recorded with source `sentence`.
