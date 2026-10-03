# The launch-day kit (#1210)

*agent-5, 2026-10-03. Everything the owner posts and sends in launch week, ready to paste, in the order of [`calendar.md`](../calendar.md)'s launch week. Each post names its channel, its time, its asset and its link.*

*Facts are `{tokens}` from [`site-facts.json`](../../05-dev-guide/site-facts.json), filled in each language's way by `tools/media/posts.py`, or by hand from the file. **Blanks in angle brackets are the owner's:** `<play-link …>`, `<name>`, and the few lines only the owner can write. A text marked *draft* waits for its native review: agent-1 bn and pl, agent-2 ru, agent-0 en and de and every fact. **Nothing here is posted by an agent.***

## The link

Every post carries its own referrer, so Play Console counts installs per channel ([`messaging.md`](../messaging.md), *The Play link*). `<play-link SOURCE/MEDIUM>` means:

```
https://play.google.com/store/apps/details?id={app.package}&referrer=utm_source%3DSOURCE%26utm_medium%3DMEDIUM%26utm_campaign%3Dlaunch
```

## The owner's launch day, in order

On L, the first Tuesday or Wednesday after the listing is live:

1. [ ] **Morning (DE): open the listing on a phone,** in each listing language. Check the title, the screenshots, the feature graphic and the video.
2. [ ] **Fill in every `<play-link …>`** below, and tell agent-4, who switches on sogda.de's Play badge (sogda-website #45).
3. [ ] **Email the testers and the O4 list** (§1).
4. [ ] **16:00 DE:** Sogda's Facebook Page and YouTube channel (§2, §3).
5. [ ] **16:00–17:00 DE** (20:00–21:00 in Bangladesh; before 25 Oct, after it an hour earlier in Germany): BDSAG and BSAAG, as their admins allowed (§4).
6. [ ] **17:30 DE:** УКРАЇНЦІ В НІМЕЧЧИНІ, in the language its admins asked for (§5).
7. [ ] **19:00 DE:** Polacy w Niemczech / Krefeld … (§6).
8. [ ] **14:00 UTC:** Discord, only if its rules allow (§8).
9. [ ] **Through the week:**
   - L+1: DaF – Lehrer (§7);
   - L+1: AlternativeTo's link (§11);
   - L+2: Show HN (§10);
   - the r/languagelearning thread while it's open (§9);
   - the pitches (#1212).
10. [ ] **Every evening:** answer every comment as the maker (§12). Forward bugs, questions and wishes to agent-5, who files each as an issue.

## 1. Email: the testers and everyone who asked to be told (en; bn, ru, pl drafts)

**Subject:** Sogda is on Google Play

> Hello,
>
> Sogda is on Google Play now: <play-link email/post>
>
> Thank you for <testing it before anyone else | asking to be told>. If you've used it, an honest review on Play helps other learners find it. And if something is wrong or missing, just reply to this email.
>
> <name>

- **bn** (*draft*): «Sogda এখন Google Play-তে: <play-link email/post>। <আগে পরীক্ষা করার | জানাতে বলার> জন্য ধন্যবাদ। ব্যবহার করে থাকলে Play-তে আপনার সৎ মতামত অন্যদের অ্যাপটি খুঁজে পেতে সাহায্য করবে। কিছু ভুল থাকলে বা কিছু না থাকলে, এই ইমেইলের উত্তরে জানান।»
- **ru** (*draft*): «Sogda уже в Google Play: <play-link email/post>. Спасибо, что <тестировал(а) её первым | попросил(а) сообщить>. Если ты уже пользуешься, честный отзыв в Google Play поможет другим найти приложение. А если что-то не так или чего-то не хватает, просто ответь на это письмо.»
- **pl** (*draft*): «Aplikacja Sogda jest już w Google Play: <play-link email/post>. Dziękuję za <testowanie jej jako pierwsi | prośbę o wiadomość>. Jeśli już z niej korzystasz, szczera opinia w Google Play pomoże innym ją znaleźć. A jeśli coś nie działa albo czegoś brakuje, po prostu odpowiedz na tego maila.»

**Never** offer anything for a review, and never ask for five stars (Play's policy).

## 2. Sogda's Facebook Page (bn, then en), 16:00 DE

**Asset:** the flight-mode clip (#1245), from the `media` branch: `2026-10-03-1245-flight-mode/`, the bn cut and then the en one.

> **bn:** জার্মানি যাওয়ার প্রস্তুতি নিচ্ছেন? A1 থেকে C2 পর্যন্ত জার্মান শিখুন, প্রতিটি শব্দের অর্থ বাংলায় আর উচ্চারণ বাংলা অক্ষরে, ইন্টারনেট ছাড়াই।
>
> Sogda এখন Google Play-তে: <play-link facebook/post>
> বাংলায় আরও: https://www.sogda.de/bn/learn-german-in-bangla

> **en:** A whole German course on your phone: A1 to C2, with mock exams for every step. Offline, no account.
>
> Sogda is on Google Play: <play-link facebook/post>
> More: https://www.sogda.de/en

The promises are `messaging.md`'s reviewed lines.

## 3. YouTube: the promo video (en), 16:00 DE

**Asset:** the promo video (#1211), unlisted or public, ads off. It's also the listing's video.

- **Title:** Sogda: German A1–C2, offline: a 30-second look
- **Description:**

> Sogda is an offline German course app for Android: A1 to C2 in {totals.steps} steps, with {totals.words} words, {totals.grammar_topics} grammar topics and {totals.mock_exams} mock exams, and meanings and a pronunciation guide in English, Bangla, Russian or Polish, no account needed.
>
> Google Play: <play-link youtube/video>
> sogda.de: https://www.sogda.de
>
> The mock exams are practice, not official Goethe or telc papers.

## 4. BDSAG and BSAAG (bn), 20:00–21:00 in Bangladesh, as the admins allowed

**Asset:** the bn flight-mode clip, or the bn feature graphic (`docs/05-dev-guide/store/feature-graphic/bn.png`).

> (*draft*) আমি Sogda তৈরি করি, আর এই গ্রুপের অ্যাডমিনদের অনুমতি নিয়ে একবার জানাচ্ছি।
>
> Sogda হলো Android-এর জন্য একটি অফলাইন জার্মান কোর্স: A1 থেকে C2 পর্যন্ত {totals.steps}টি ধাপ, {totals.words}টি শব্দ, {totals.grammar_topics}টি ব্যাকরণ বিষয় আর {totals.mock_exams}টি মক পরীক্ষা। প্রতিটি শব্দের অর্থ বাংলায়, উচ্চারণ বাংলা অক্ষরে, আর অ্যাপটিও বাংলায় চালানো যায়। অ্যাকাউন্ট লাগে না।
>
> ভিসা, বিশ্ববিদ্যালয় বা Ausbildung-এর জন্য যাঁরা জার্মান শিখছেন, তাঁদের কাজে লাগতে পারে। মক পরীক্ষাগুলো অনুশীলনের জন্য, Goethe বা telc-এর অফিসিয়াল প্রশ্নপত্র নয়।
>
> Google Play: <play-link facebook/post>
> বাংলায় বিস্তারিত: https://www.sogda.de/bn/learn-german-in-bangla
>
> যেকোনো প্রশ্নের উত্তর কমেন্টে দেব।

**BSAAG's rule 8:** if its admins prefer the article route, share the germanprobashe.com guide (#1246) instead.

## 5. УКРАЇНЦІ В НІМЕЧЧИНІ (ru, or the language its admins asked for), 17:30 DE

> **ru** (*draft*): Я делаю Sogda и пишу сюда один раз, с разрешения администраторов.
>
> Sogda — приложение с офлайн-курсом немецкого для Android: от A1 до C2 за {totals.steps} этапов, {totals.words} слов, {totals.grammar_topics} грамматические темы и {totals.mock_exams} пробных экзаменов. Значения, переводы примеров и правила — на русском, произношение записано кириллицей. Без аккаунта.
>
> Пробные экзамены — для практики, это не официальные задания Goethe или telc.
>
> Google Play: <play-link telegram/post>
> Подробнее: https://www.sogda.de/ru/learn-german-from-scratch
>
> На вопросы отвечу здесь.

> **en, if the admins prefer it:** I make Sogda, and I'm posting once, with the admins' OK. It's an offline German course for Android, A1 to C2, with meanings and a pronunciation guide in English, Bangla, Russian or Polish (no Ukrainian yet), and no account. Google Play: <play-link telegram/post>

## 6. Polacy w Niemczech / Krefeld … (pl), 19:00 DE

> (*draft*) Tworzę aplikację Sogda i piszę tu raz, za zgodą administratorów.
>
> Sogda to kurs niemieckiego offline na Androida: od A1 do C2 w {totals.steps} etapach, {totals.words} słów, {totals.grammar_topics} tematy gramatyczne i {totals.mock_exams} egzaminów próbnych. Znaczenia, tłumaczenia przykładów i reguły są po polsku, a wymowa jest zapisana polskimi literami. Bez konta.
>
> Egzaminy próbne są do ćwiczenia, to nie są oficjalne arkusze Goethe ani telc.
>
> Google Play: <play-link facebook/post>
> Więcej: https://www.sogda.de/pl/learn-german-from-scratch
>
> Chętnie odpowiem na pytania w komentarzach.

## 7. DaF – Lehrer (de), L+1, 14:00 DE, as the moderators agreed

> (*draft*) Guten Tag, ich entwickle Sogda und poste hier einmal, nach Absprache mit den Moderatorinnen.
>
> Sogda ist eine Offline-Deutschkurs-App für Android: von A1 bis C2 in {totals.steps} Stufen, mit {totals.words} Wörtern, {totals.grammar_topics} Grammatikthemen und {totals.mock_exams} Probeprüfungen. Bedeutungen und eine Aussprachehilfe gibt es auf Englisch, Bangla, Russisch oder Polnisch. Ohne Konto: Der Fortschritt bleibt auf dem Handy, es gibt also nichts einzurichten.
>
> Vielleicht passt sie für Lernende, die zwischen den Stunden üben möchten. Die Probeprüfungen sind Übung, keine offiziellen Goethe- oder telc-Prüfungen.
>
> Google Play: <play-link facebook/post>
> Mehr: https://www.sogda.de/de
>
> Über Rückmeldungen aus dem Unterricht freue ich mich.

## 8. German Learning and Discussion (Discord, en), 14:00 UTC, only if its rules allow

> I make Sogda, an offline German course for Android: A1 to C2 in {totals.steps} steps, with mock exams for every step (practice, not official papers). Meanings and a pronunciation guide in English, Bangla, Russian or Polish, and no account. If it's useful to anyone here: <play-link discord/post>. Feedback very welcome.

## 9. r/languagelearning, the "Share Your Resources" thread (en), while it's open

The only place there that allows it ([rules](https://www.reddit.com/r/languagelearning/wiki/rules_for_promotion/)): one comment, saying "I made it", once in six months.

> **Sogda: an offline German course for Android (I made it)**
>
> A1 to C2 in {totals.steps} steps: {totals.words} words, {totals.grammar_topics} grammar topics with short rules, spaced revision, and {totals.mock_exams} mock exams with listening, writing and speaking (practice, not official papers). Meanings and a pronunciation guide in English, Bangla, Russian or Polish. No account, and it works offline. It's not an AI tool.
>
> Who it's for: learners who want a structured path to C2 and exam practice on their phone, especially from Bangla, Russian or Polish.
>
> Google Play: <play-link reddit/comment> · https://www.sogda.de/en
>
> I'd love to hear what's missing.

## 10. Show HN (en), L+2, a weekday morning in the US

- **Title** (80 characters at most): `Show HN: Sogda – an offline German course for Android, A1 to C2, no account`
- **URL:** https://www.sogda.de/en (the site links the listing)
- **Text:**

> <Why I built it, in the owner's own words: two or three sentences. HN rewards the maker's story, not a pitch.>
>
> Sogda is an offline German course: A1 to C2 in {totals.steps} steps, {totals.words} words and {totals.grammar_topics} grammar topics, spaced revision (FSRS), and {totals.mock_exams} mock exams with listening, writing and speaking. Meanings and a pronunciation guide in English, Bangla, Russian or Polish. No account and nothing to sign in to; the progress stays on the phone.
>
> What it isn't: official exam papers, or an AI tutor. It's Android only for now.
>
> Happy to answer anything about the course or how it's built.

The owner answers every comment the first day. A correction someone points out becomes an issue at once.

## 11. AlternativeTo (en)

Suggested in week −2 with the website; on L+1, add the Play link.

- **Name:** Sogda
- **Alternative to:** Duolingo, Anki, Babbel
- **Description:** Sogda is an offline German course app for Android: A1 to C2 in {totals.steps} steps, with {totals.words} words, {totals.grammar_topics} grammar topics and {totals.mock_exams} mock exams, and meanings and a pronunciation guide in English, Bangla, Russian or Polish, no account needed.
- **Platforms:** Android. **Link:** <play-link alternativeto/post>

## 12. Answering comments: the playbook

The owner answers as the maker, kindly, in the commenter's language where possible. Every answer stays inside the facts.

| They ask | The answer |
|---|---|
| "Is it free?" / "What does it cost?" | **The owner's own answer (D5 in [`plan.md`](../plan.md)).** Our posts never say "free" or a price |
| "Is there an iPhone version?" | Android only for now. No date is promised |
| "How is it different from Duolingo / Anki?" | Don't argue. Link the fair comparisons: https://www.sogda.de/en/sogda-vs-duolingo and https://www.sogda.de/en/sogda-vs-anki |
| "Are the mock exams the real Goethe / telc exams?" | No. They're practice, with listening, writing and speaking, plus vocabulary and grammar, and no reading part. Not official papers |
| "Does it work offline?" | The whole course does. The sound uses the phone's German voice, or Supertonic, an optional voice downloaded once |
| "Where does my data go?" | Nowhere: there's no account, and the progress stays on the phone. A backup is a file you choose to share |
| "I found a bug" | Thank them, and ask for the phone, the Android version and the app version (*About*). agent-5 files it the same day |
| "Can you add <language>?" | Thank them and note it. New meaning languages are the owner's call |
| Anything angry or unfair | One calm, factual answer, then let it be. Never argue, and never ask anyone to change a rating |

**Never:**
- a price or "free" in a post;
- a rating or a user count;
- a testimonial;
- a pass promise;
- a second post in the same community.
