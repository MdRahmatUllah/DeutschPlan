# Messaging: one true thing, said per audience (#1203)

Every post, pitch, caption and comment says the same true thing about Sogda, in the voice its audience needs. This page is where that thing is written down. The calendar ([`calendar.md`](calendar.md)) says when and where each piece goes out; the post drafts (#1207) fill these lines in.

**Facts are tokens, never typed.** `{totals.words}` means "the number in [`site-facts.json`](../05-dev-guide/site-facts.json) at `totals.words`". The drafts fill it in the way each language writes numbers (bn in Bangla digits, pl and ru with no separator for four digits). `tools/tests/test_marketing_docs.py` fails on a typed count, and on a token that isn't in the file.

**Native review:** agent-1 checks pl and bn, and agent-2 checks ru. The owner has the last word on bn nuance. agent-0 checks en, de and every fact. A line marked *draft* hasn't been reviewed yet.

## The sentence everything comes from

> Sogda is an offline German course app for Android: A1 to C2 in {totals.steps} steps, with {totals.words} words, {totals.grammar_topics} grammar topics and {totals.mock_exams} mock exams, and meanings and a pronunciation guide in English, Bangla, Russian or Polish, no account needed.

This is sogda.de's positioning sentence (sogda-website `docs/MASTER-PLAN.md` §4). **In bn, pl and ru, use the store listing's own sentence:** the second paragraph of each full description in [`store-listing.md`](../05-dev-guide/store-listing.md), which is approved and reviewed. Never re-translate it. In de, it is the first paragraph of sogda.de/de.

## What every message keeps

- **The combination is the message.** No rival has all of it together: offline, no account, A1 to C2, mock exams for every step, spaced repetition, and meanings in the learner's own script. Each rival has two or three of these (sogda-website `docs/research/2026-09-30-website-review.md` §6). Lead with the combination, never with one feature that a bigger app also has.
- **Show, don't claim.** We have no ratings, reviews or user counts, and the rules forbid inventing them. So the proof is the product: a real screen, a real word card, a real mock-exam section.
- **Never** say:
  - a price, "free", "no ads" or a rating;
  - "best", "#1" or "fastest";
  - a fake deadline ("only today");
  - a learner's story we didn't get from a real learner.
- **Goethe and telc** are only described: the mock exams test listening, writing and speaking, plus vocabulary and grammar; **they have no reading part, and they're not official Goethe or telc papers.** Never in a headline next to "Sogda".
- **Name a competitor only when asked,** and only with facts from its own public pages, in the "Choose X if…" form of sogda.de's comparisons ([`/en/sogda-vs-duolingo`](https://www.sogda.de/en/sogda-vs-duolingo), [`/en/sogda-vs-anki`](https://www.sogda.de/en/sogda-vs-anki)).
- **"I make this app."** Every community post discloses that the owner makes Sogda, in the community's language.

## The audiences

Each block has:
- the **promise** (the one line a post leads with);
- three **proof points** (each one a fact the app shows);
- the **objection** the audience has, and our honest answer;
- the **call to action** and the page to send people to.

### 1. Bangla speakers in Bangladesh, on the way to Germany (bn)

Students, Ausbildung and job seekers who need A1 to B2 for a visa, a university or a contract, often on a phone with expensive data.

- **Promise** (*draft*): জার্মানি যাওয়ার প্রস্তুতি? A1 থেকে C2 পর্যন্ত জার্মান শিখুন, প্রতিটি শব্দের অর্থ বাংলায় আর উচ্চারণ বাংলা অক্ষরে, ইন্টারনেট ছাড়াই।
  *(Preparing to go to Germany? Learn German from A1 to C2, every word's meaning in Bangla and its pronunciation in Bangla letters, without internet.)*
- **Proof:**
  1. Every word has a Bangla meaning and a guide in Bangla letters (*Termin* → {featured.1.guide.bn}). An English meaning can show under it.
  2. {totals.steps} steps from A1.1 to C2.2, with {totals.mock_exams_per_step} mock exams for every step.
  3. The app runs in Bangla, offline, with no account.
- **Objection:** "The good apps teach German through English." **Answer:** here the meanings and the pronunciation are in Bangla, and the app itself is in Bangla. (The example lines and grammar rules are in English for Bangla learners: never claim them in Bangla.)
- **Call to action:** sogda.de/bn/learn-german-in-bangla, then the Play link.

### 2. Bangla speakers in Germany (bn, or en for mixed groups)

People living the paperwork: the Anmeldung, the Ausländerbehörde, a Termin.

- **Promise** (*draft*): জার্মানিতে থাকেন? Anmeldung, Termin, Ausländerbehörde: দৈনন্দিন জীবনের জার্মান শিখুন বাংলায়, অফলাইনে।
  *(Living in Germany? Anmeldung, Termin, Ausländerbehörde: learn everyday German in Bangla, offline.)*
- **Proof:**
  1. The words of daily life are in the course: {featured.0.article} {featured.0.german}, {featured.1.article} {featured.1.german} and {featured.4.article} {featured.4.german}, each with its article and a guide in Bangla letters.
  2. Spaced revision brings each word back just before you'd forget it.
  3. The path goes on past the paperwork, step by step to C2.
- **Objection:** "No time for a course." **Answer:** the plan for today is a few new words and what's due to revise. You choose the rest days.
- **Call to action:** sogda.de/bn, then the Play link.

### 3. Russian speakers, and Ukrainians who choose Russian (ru)

- **Promise** (*draft*): Немецкий от A1 до C2, и всё на русском: значения, примеры, правила и произношение кириллицей. Без интернета и без аккаунта.
  *(German from A1 to C2, all in Russian: meanings, examples, rules and pronunciation in Cyrillic. Offline, no account.)*
- **Proof:**
  1. In Russian, the meanings, example sentences and grammar rules are all Russian (`languages.grammar_in`), and the guide is in Cyrillic (*Termin* → {featured.1.guide.ru}).
  2. {totals.words} words and {totals.grammar_topics} grammar topics, from A1.1 to C2.2.
  3. {totals.mock_exams_per_step} mock exams for every step, with listening, writing and speaking.
- **Objection:** "Courses in Russian stop at the basics." **Answer:** this one goes to C2.
- **Care:** Russian copy goes to Russian-language spaces only. In a Ukrainian-language community, post in English (the app has no Ukrainian) or not at all. The owner decides case by case.
- **Call to action:** sogda.de/ru/learn-german-from-scratch, then the Play link.

### 4. Polish speakers (pl)

Work in Germany, school German, and Poles already living there.

- **Promise** (*draft*): Niemiecki od zera do C2, w całości po polsku: znaczenia, przykłady, reguły i wymowa zapisana polskimi literami. Offline, bez konta.
  *(German from zero to C2, entirely in Polish: meanings, examples, rules and pronunciation in Polish letters. Offline, no account.)*
- **Proof:**
  1. Meanings, example sentences and grammar rules are in Polish, and the guide is in Polish letters (*Termin* → {featured.1.guide.pl}).
  2. The course goes to C2. Polish-language apps found in the site review stop at A1 to B1.
  3. {totals.mock_exams_per_step} mock exams for every step.
- **Objection:** "Another vocabulary app." **Answer:** it's a course: {totals.grammar_topics} grammar topics with rules and practice, a plan for every day, and mock exams.
- **Call to action:** sogda.de/pl/learn-german-from-scratch, then the Play link.

### 5. English-speaking learners anywhere (en)

The biggest audience, and the most crowded.

- **Promise:** A whole German course on your phone: A1 to C2, with mock exams for every step. Offline, no account.
- **Proof:**
  1. {totals.steps} steps, {totals.words} words, {totals.grammar_topics} grammar topics and {totals.mock_exams} mock exams.
  2. Spaced revision with {fsrs.version}: a word you know comes back after {fsrs.good_days.0} days, then {fsrs.good_days.1}, then {fsrs.good_days.2}.
  3. Two meaning languages at once, for people who learn from a second language.
- **Objection:** "I already use Duolingo or Anki." **Answer:** don't argue it. Point to the "Choose X if…" pages, which say when each one fits. Sogda fits when you want a path to C2 and exam practice, offline.
- **Call to action:** sogda.de/en, then the Play link.

### 6. Exam candidates, any language (en, bn, pl, ru)

- **Promise:** Practise for your German exam at every level, A1 to C2: mock exams with listening, writing and speaking, on your phone.
- **Proof:**
  1. {totals.mock_exams_per_step} mock exams per step, {totals.mock_exams} in all.
  2. Each one has {mock_exam.questions} questions and {mock_exam.tasks} tasks: vocabulary, articles, word forms, gap fill, grammar and listening, plus a writing and a speaking task. The writing asks for at least {mock_exam.writing_min_words.B1} words at B1.
  3. A result for each section, so you know what to practise.
- **Objection:** "Is it the real exam?" **Answer:** no. They are not official Goethe or telc papers, and there's no reading part. They practise the same skills, at your level.
- **Call to action:** sogda.de/<locale>/mock-exams, then the Play link.

### 7. People in Germany who recommend (de)

Teachers, integration-course staff, volunteers who help newcomers, and international offices. They don't learn German; they pass Sogda on.

- **Promise** (*draft*): Eine Deutschkurs-App zum Weiterempfehlen: offline, ohne Konto, von A1 bis C2, mit Bedeutungen auf Englisch, Bangla, Russisch oder Polnisch.
- **Proof:**
  1. No account, and the progress stays on the phone (the listing's own words): nothing to set up for a class.
  2. Meanings and a pronunciation guide in the learner's own script.
  3. The vocabulary of arrival: {featured.0.article} {featured.0.german}, {featured.4.article} {featured.4.german}, {featured.3.article} {featured.3.german}.
- **Objection:** "Does it replace the course?" **Answer:** no. It's practice between lessons, with spaced revision.
- **Call to action:** sogda.de/de, plus the Play link to pass on.

## The Play link

Every link we prepare carries a referrer, so Play Console counts installs per channel (agent-5's README, *How it measures*):

```
https://play.google.com/store/apps/details?id={app.package}&referrer=utm_source%3D<source>%26utm_medium%3D<medium>%26utm_campaign%3D<campaign>
```

| Part | Values |
|---|---|
| `<source>` | `reddit`, `facebook`, `telegram`, `vk`, `wykop`, `youtube`, `instagram`, `tiktok`, `email` (outreach), `alternativeto`, `sogda.de` (the site's own, #45) |
| `<medium>` | `post`, `comment`, `pitch`, `video`, `bio` |
| `<campaign>` | `launch` (weeks −2 to +1), then `w2` … `w6`, then `evergreen` |

Until the app is on Play, every draft says `<play-link>`.
