# Mock exam generator

`domain/exam_generator.dart` — one algorithm, seeded (BR-EXAM-02).

```
buildExam(ExamPool pool, seed:, listening:, bangla:, sat:) → Exam(items, reused)
```

1. Pool = all words of the step (any status, suspended excluded) and all grammar topics of the step.
2. RNG = `Random(hash(step, seed))`. A step-level exclusion set is built from the *other* seeds' item ids so the three mocks never share an item; when the pool is smaller than 3 × demand, the least-recently-used items are reused and the hub says so.
3. Sections (BR-EXAM-03): Vocabulary 10 (DE→meaning, typed) · Reverse 8 (meaning→DE, typed, article optional) · Articles 6 (nouns only) · Word forms 4 (from `forms`) · Gap fill 6 (example sentence with the headword blanked; cloze check) · Grammar 4 (items from `GrammarItemGenerator` for the step's topics) · Listening 2 (TTS plays the word/sentence; type it; skipped if listening disabled — points redistributed) · Writing 1 · Speaking 1.
4. Points: 1 per item; Writing 4 (app checks 2: ≥ 6 target words used, ≥ minimum length; rubric 2 × 0.5 each) ; Speaking 4 (rubric 4 × 1). Max 48. Score % = points / max.
5. Writing prompt: template per level × topic category with 10 target words from the step; minimum words A1 30 · A2 60 · B1 100 · B2 150 · C1 200 · C2 250. Connector check uses the step's grammar connector list.
6. Speaking prompt: template per level (60 s A1–A2, 90 s B1–B2, 120 s C1–C2); one retake.

Persistence: on *Begin exam* an `exam_attempts` row is created with all `exam_answers` pre-inserted (prompt, options, expected); answering updates rows in place, so a crash resumes exactly. Timer: `duration_sec` accumulates only while running; pauses are recorded.

Grading on submit: `answer_check` per item; Listening compares the typed text with `checkGerman`; Writing app-checks computed from the text; rubric ticks stored in `self_rubric_json`. `passed = score% >= exam_pass_percent`. Passing marks the step (query, not a flag: any finished passed attempt for the step).

## Details the generator settles (#83)

`buildExam(ExamPool pool, seed:, listening:, bangla:, sat:)` in `domain/exam_generator.dart`. `ExamRepository.pool(step)` reads the pool, `satRefs(step)` the papers already sat, and `storedPaper(step, seed)` a seed's stored paper.

- **Items and what never repeats.** An item's ref is:
  - a word's uid, in every word section: a word is asked once in a paper, and in one paper of the three;
  - `<topic uid>#<n>` for the *n*-th grammar item the topic yields, seeded by the topic and the step. What never repeats is the *topic*: a topic's items share their sentence, so two papers never draw the same topic, and a paper asks one item of each topic it draws;
  - `writing:<category id>` or `speaking:<category id>` for the two tasks.
- **Drawing.** The three papers are drawn together, section by section, each from its own `Random(hash(step, seed))` (FNV-1a over `step|mock seed`). An item one paper takes is out of the others' pools. The order is Word forms, Gap fill, Articles, Grammar, Listening, Reverse, Vocabulary, Writing, Speaking:
  - the scarcest sections first, so a small step spends its nouns and forms where only they will do;
  - the two tasks last, so the writing targets can leave out the paper's words.

  The paper itself is in BR-EXAM-03's order.
- **Reuse.** When a section runs out of fresh items, a paper takes the one another paper drew longest ago, never one it already has, and `Exam.reused` tells the hub. Words and tasks never run out on the real course. Grammar needs twelve topics for three papers: A1.1 to B1.2 have 10 or 11, so their third paper reuses one or two topics and says so (a test over the real content.db pins both). A step with fewer than three categories reuses a task the same way.
- **Sittings days apart.** A paper is stored when it is begun (FR-L10-03), and the course can change before the next: a word suspended, listening turned off, a content update. So:
  - L11 passes the refs of every paper already sat as `sat` (`satRefs`). Those seeds are not drawn again, and their refs count as drawn before anything else, so a new paper shares nothing with them.
  - A retake sits the stored paper (`storedPaper`), not a newly drawn one.
- **FR-L10-04.** Without listening, Vocabulary gets 11 items and Reverse 9: still 40 questions and 48 points.
- **Meanings.** With the meaning language set to Bangla, Vocabulary expects the Bangla meaning and Reverse shows it, where the course has one; otherwise English, as the word lists do.
- **What each item asks:**

  | Section | Prompt | Expected | Check |
  |---|---|---|---|
  | Vocabulary | the headword with its article | the meaning list | `checkMeaning` |
  | Reverse | the meaning | the headword (article optional) | `checkGerman` |
  | Articles | the noun; buttons der · die · das | `der`/`die`/`das` | `checkArticle` |
  | Word forms | the word and a form label (`parseForms`) | the form | `checkForm` |
  | Gap fill | one of the word's examples, blanked by the cloze rules (`clozeGap`), with its translation | the form the sentence uses | `checkGerman` |
  | Grammar | an L15 item (`generateItems`), spread over as many topics as there are | the missing word · the right form · the wrong token's index · the words in order, space-separated · the right rule's index | `checkGerman` for a gap fill, exact otherwise |
  | Listening | the headword, played | the headword, typed | `checkGerman` |
  | Writing | see below | — | FR-L12W-03 |
  | Speaking | see below | — | rubric |

- **Stored.** `exam_answers.prompt` is the item as JSON, so every kind comes back whole after a restart (`ExamItem.decode`). `options_json` holds the buttons (Articles, pick the form, rule recall). `item_ref` is the ref above.
- **Writing.** The step's biggest categories go to papers 1, 2 and 3 in turn: a big category gives the most to write about.
  - It has 10 target words, single words from that category (so FR-L12W-01's token match can find them), topped up from the step.
  - The targets never include a word the paper asks, by uid or by spelling. The runner goes back and forth, and a target must not be an answer to copy.
  - The minimum length is FR-L12W-02's.
  - Connectors are the course's conjunctions up to and including the step (course order is `sublevels.ord`), each once. Entries a learner doesn't type as written (`denn ↔ weil`, `obgleich / obschon`, `allein (= aber)`) are left out.
  - content.db has no connector list, and `skill_prompts` holds scraped worksheet cells, not prompts (#294).
- **Speaking.** A category of the step other than the paper's writing, biggest first, one per paper, and FR-L12S-02's length.
- **The task per level.** L12 words these in ARB (#133, #134), with `{category}` the category's German name:

  | Level | Writing | Speaking |
  |---|---|---|
  | A1 | Write a short message to a friend about {category}. | Say what you do and like around {category}. |
  | A2 | Write an email to a friend about {category}. | Describe an experience with {category}. |
  | B1 | Write a personal letter about {category}: what happened and what you think. | Talk about {category}: your experience and your opinion. |
  | B2 | Write a formal letter or opinion text on {category}. | Give your opinion on {category}, with reasons and an example. |
  | C1 | Write an argumentative text on {category}: both sides, then your view. | Argue a position on {category} and answer the other side. |
  | C2 | Write a commentary on {category} for a newspaper. | Give a short talk on {category} as if to an audience. |

  Each writing task adds "Use at least 6 of these words:" with the targets, and "at least {min} words".

## Details grading settles (#84)

`domain/exam_grading.dart` scores a stored paper, and `ExamRepository.grade(attemptId, passPercent:, finishedAt:)` writes it back.

- **Per item.** Each item is checked by `answer_check` with the check in the table above. Points are BR-ANS-04's: correct 1, almost 0.5, wrong article or wrong 0. An empty answer is 0.
- **Writing** (FR-L12W-01, -03). A target counts when a word of the text has a search key starting with the target's ("Heizungen" uses "Heizung"; umlauts fold as search does). 6 targets or more is 1 point, and at least the level's minimum number of words is 1 point. Words are runs of letters. The rubric adds 0.5 for each of its first two ticks.
- **Speaking.** 1 point for each of its four rubric ticks.
- **The rubric.** `self_rubric_json` is a JSON list of booleans in the rubric's order. Ticks beyond a section's count are ignored.
- **The score.** The points add up out of the paper's (48). `passed` means points × 100 ≥ `exam_pass_percent` × max, so exactly the mark passes. `grade` writes every row's points and the attempt's score in one transaction.
  - With `finishedAt` it is the submit: the attempt becomes `finished`, and a pass marks the step through the `stepPassed` query (BR-EXAM-04).
  - Without it, it is L13's re-grade after a rubric tick (FR-L13-03), and the finish time stays as it was.

