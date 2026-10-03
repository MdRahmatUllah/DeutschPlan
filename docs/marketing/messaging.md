# Messaging: one true thing, said per audience (#1203)

Every post, pitch, caption and comment says the same true thing about Sogda, in the voice its audience needs. This page is where that thing is written down. The calendar ([`calendar.md`](calendar.md)) says when and where each piece goes out; the post drafts (#1207) fill these lines in.

**Facts are tokens, never typed.** `{totals.words}` means "the number in [`site-facts.json`](../05-dev-guide/site-facts.json) at `totals.words`". The drafts fill it in the way each language writes numbers (bn in Bangla digits; pl with no separator for four digits; ru with a no-break space before the last three, as #1194 settled for the listing, the app and sogda.de; de with a full stop for thousands). `tools/tests/test_marketing_docs.py` fails on a typed count, and on a token that isn't in the file.

**Native review:** agent-1 checks pl and bn, and agent-2 checks ru. The owner has the last word on bn nuance. agent-0 checks en, de and every fact. A line marked *draft* hasn't been reviewed yet.

## The sentence everything comes from

> Sogda is an offline German course app for Android: A1 to C2 in {totals.steps} steps, with {totals.words} words, {totals.grammar_topics} grammar topics and {totals.mock_exams} mock exams, and meanings and a pronunciation guide in English, Bangla, Russian or Polish, no account needed.

This is sogda.de's positioning sentence (sogda-website `docs/MASTER-PLAN.md` §4). **In bn, pl and ru, use the store listing's own sentence:** the second paragraph of each full description in [`store-listing.md`](../05-dev-guide/store-listing.md), which is approved and reviewed. Never re-translate it. In de, it is the first paragraph of sogda.de/de.

## What every message keeps

- **The combination is the message.** No rival has all of it together: offline, no account, A1 to C2, mock exams for every step, spaced repetition, and meanings in the learner's own script. Each rival has two or three of these (sogda-website `docs/research/2026-09-30-website-review.md` §6). Lead with the combination, never with one feature that a bigger app also has.
- **Offline means the course.** Words, the day's plan, revision, grammar and the mock exams all run in flight mode (agent-3's E2E check). **The sound needs a German voice:** Supertonic, downloaded once, or a German voice the phone keeps offline. Never promise offline audio. Where sound is the point, say "with the voice downloaded".
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

- **Promise:** জার্মানি যাওয়ার প্রস্তুতি নিচ্ছেন? A1 থেকে C2 পর্যন্ত জার্মান শিখুন, প্রতিটি শব্দের অর্থ বাংলায় আর উচ্চারণ বাংলা অক্ষরে, ইন্টারনেট ছাড়াই।
  *(Preparing to go to Germany? Learn German from A1 to C2, every word's meaning in Bangla and its pronunciation in Bangla letters, without internet.)*
- **Proof:**
  1. Every word has a Bangla meaning and a guide in Bangla letters (*Termin* → {featured.1.guide.bn}). An English meaning can show under it.
  2. {totals.steps} steps from A1.1 to C2.2, with {totals.mock_exams_per_step} mock exams for every step.
  3. The app runs in Bangla, offline, with no account.
- **Objection:** "The good apps teach German through English." **Answer:** here the meanings and the pronunciation are in Bangla, and the app itself is in Bangla. (The example lines and grammar rules are in English for Bangla learners: never claim them in Bangla.)
- **Call to action:** sogda.de/bn/learn-german-in-bangla, then the Play link.

### 2. Bangla speakers in Germany (bn, or en for mixed groups)

People living the paperwork: the Anmeldung, the Ausländerbehörde, a Termin.

- **Promise:** জার্মানিতে থাকেন? Anmeldung, Termin, Ausländerbehörde: দৈনন্দিন জীবনের জার্মান শিখুন বাংলায়, অফলাইনে।
  *(Living in Germany? Anmeldung, Termin, Ausländerbehörde: learn everyday German in Bangla, offline.)*
- **Proof:**
  1. The words of daily life are in the course: {featured.0.article} {featured.0.german}, {featured.1.article} {featured.1.german} and {featured.4.article} {featured.4.german}, each with its article and a guide in Bangla letters.
  2. Spaced revision brings each word back just before you'd forget it.
  3. The path goes on past the paperwork, step by step to C2.
- **Objection:** "No time for a course." **Answer:** the plan for today is a few new words and what's due to revise. You choose the rest days.
- **Call to action:** sogda.de/bn, then the Play link.

### 3. Russian speakers, and Ukrainians who choose Russian (ru)

- **Promise:** Немецкий от A1 до C2, и всё на русском: значения, переводы примеров, правила и подсказки произношения кириллицей. Без интернета и без аккаунта.
  *(German from A1 to C2, all in Russian: meanings, examples, rules and pronunciation in Cyrillic. Offline, no account.)*
- **Proof:**
  1. In Russian, the meanings, the example sentences' translations and the grammar rules are all Russian (`languages.grammar_in`), and the guide is in Cyrillic (*Termin* → {featured.1.guide.ru}).
  2. {totals.words} words and {totals.grammar_topics} grammar topics, from A1.1 to C2.2.
  3. {totals.mock_exams_per_step} mock exams for every step, with listening, writing and speaking.
- **Objection:** "Is it only for beginners?" (the most-watched Russian courses are). **Answer:** no. It goes from A1.1 to C2.2, with mock exams for every step.
- **Care:** Russian copy goes to Russian-language spaces. In a Ukrainian or mixed community, the owner asks the admins which language they want: Russian only where the chat itself writes Russian, otherwise English (D8 in [`plan.md`](plan.md)).
- **Call to action:** sogda.de/ru/learn-german-from-scratch, then the Play link.

### 4. Polish speakers (pl)

Work in Germany, school German, and Poles already living there.

- **Promise:** Niemiecki od zera do C2, w całości po polsku: znaczenia, przykłady z tłumaczeniem, reguły gramatyki i wymowa zapisana polskimi literami. Offline, bez konta.
  *(German from zero to C2, entirely in Polish: meanings, examples, rules and pronunciation in Polish letters. Offline, no account.)*
- **Proof:**
  1. The meanings, the example sentences' translations and the grammar rules are in Polish, and the guide is in Polish letters (*Termin* → {featured.1.guide.pl}).
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
| `<source>` | `reddit`, `facebook`, `telegram`, `discord`, `youtube`, `instagram`, `tiktok`, `email` (outreach), `alternativeto`, `sogda.de` (the site's own, #45) |
| `<medium>` | `post`, `comment`, `pitch`, `video`, `bio` |
| `<campaign>` | `launch` (weeks −2 to +1), then `w2` … `w6`, then `evergreen` |

Until the app is on Play, every draft says `<play-link>`.

## What's new in 1.2.0: learn from the German you meet (#1236)

The story of the update: **learn the German you actually meet, on your phone, private.** The store notes are #1312's *What's new* (`store-listing.md`); the blocks below are for posts (`tools/media/posts.py --week 1.2.0`). Every promise is a *draft* until its native review, and the referrer's campaign is `v1.2.0`.

What every 1.2.0 message keeps:
- **Only what ships:** paste a text; share a text, a PDF or photos from another app (photos since #1332); choose a PDF; or photograph a letter.
- **Private, in the store notes' words:** it reads on the phone, and "nothing leaves your phone". Hy-MT2's translation is an optional download, offered on phones with the memory for it, and then works on the phone (#154).
- **No number for the daily limit:** the learner sets it, so we say "a daily limit of their own".
- **Synthetic documents only** in every image and video, never a real person's letter.

### 1. Bangla speakers (bn)

- **Promise** (*draft*): যে জার্মান আপনি রোজ দেখেন, সেটাই শিখুন: চিঠির ছবি তুলুন বা লেখা পেস্ট করুন, Sogda আপনার অজানা শব্দগুলো লেভেল ধরে চিহ্নিত করবে। সবকিছু আপনার ফোনেই।
  *(Learn the German you see every day: photograph a letter or paste a text, and Sogda marks the words you don't know yet, by level. All on your phone.)*
- **Proof:**
  1. Ausländerbehörde-এর চিঠি, ভাড়ার চুক্তি, চাকরির বিজ্ঞাপন: Sogda ফোনেই সেটা পড়ে, আর কোর্সের নতুন শব্দগুলো লেভেল ধরে চিহ্নিত করে।
  2. যে শব্দগুলো বেছে নেবেন, সেগুলো যে বাক্যে পেয়েছেন সেই বাক্য আর বাংলা অর্থসহ আপনার পরিকল্পনায় যোগ হয়।
  3. এগুলোর আলাদা দৈনিক সীমা আছে, তাই লম্বা চিঠিও আপনার দিনটা ভারী করে না।
- **Call to action:** Google Play-তে Sogda আপডেট করুন, অথবা ইনস্টল করুন: sogda.de/bn।

### 2. Russian speakers (ru)

- **Promise** (*draft*): Учи тот немецкий, который встречаешь: сфотографируй письмо или вставь текст — Sogda отметит незнакомые слова по уровням. Всё остаётся на телефоне.
  *(Learn the German you meet: photograph a letter or paste a text, and Sogda marks the unknown words by level. Everything stays on the phone.)*
- **Proof:**
  1. Письмо из Jobcenter, договор аренды, объявление о работе: Sogda читает такой текст прямо на телефоне и отмечает новые для тебя слова по уровням курса.
  2. Выбранные слова попадают в план вместе с предложением из твоего текста и значением на русском.
  3. У них свой дневной лимит, поэтому длинное письмо не перегрузит твой день.
- **Call to action:** обнови Sogda в Google Play или установи с sogda.de/ru.

### 3. Polish speakers (pl)

- **Promise** (*draft*): Ucz się niemieckiego, który spotykasz na co dzień: zrób zdjęcie listu albo wklej tekst, a Sogda zaznaczy nieznane słowa według poziomu. Wszystko zostaje na telefonie.
  *(Learn the German you meet every day: photograph a letter or paste a text, and Sogda marks the unknown words by level. Everything stays on the phone.)*
- **Proof:**
  1. List z urzędu, umowa najmu, ogłoszenie o pracy: Sogda czyta taki tekst na telefonie i zaznacza nowe słowa z kursu według poziomu.
  2. Wybrane słowa trafiają do planu razem ze zdaniem z twojego tekstu i ze znaczeniem po polsku.
  3. Mają własny dzienny limit, więc długi list nie zasypie ci dnia.
- **Call to action:** zaktualizuj aplikację Sogda w Google Play albo ją zainstaluj: sogda.de/pl.

### 4. English-speaking learners (en)

- **Promise** (*draft*): Learn the German you actually meet: photograph a letter or paste a text, and Sogda marks the words you don't know yet, by level. On your phone, private.
- **Proof:**
  1. Paste a text, share a text or a photo from another app, choose a PDF, or photograph a letter: Sogda reads it on the phone.
  2. The words you pick join your plan with the sentence you met them in.
  3. Optional, on phones with the memory for it: Hy-MT2 translates on the phone, for sentences and for words outside the course.
- **Call to action:** update Sogda on Google Play, or install it: sogda.de/en.

### 5. People in Germany who recommend (de)

- **Promise** (*draft*): Lernende bringen ihre eigenen Texte mit: Brief fotografieren oder Text einfügen, und Sogda markiert die unbekannten Wörter nach Niveau. Alles bleibt auf dem Handy.
  *(Learners bring their own texts: photograph a letter or paste a text, and Sogda marks the unknown words by level. Everything stays on the phone.)*
- **Proof:**
  1. Ein Brief vom Amt, ein Arbeitsvertrag, ein Text aus dem Unterricht: Sogda liest ihn auf dem Handy und markiert die neuen Wörter aus dem Kurs nach ihrem Niveau.
  2. Die gewählten Wörter kommen mit ihrem Satz in den Lernplan, mit einem eigenen Tageslimit.
  3. Nichts wird hochgeladen: Texterkennung und Übersetzung laufen auf dem Gerät.
- **Call to action:** sogda.de/de, und der Link zu Google Play zum Weitergeben.
