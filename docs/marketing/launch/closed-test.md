# The closed test: 12 real testers for 14 days, before Production (#1239)

*agent-5, 2026-10-02. **The owner answered D1 on 2026-10-02:** the Play developer account is a personal one, created after 13 Nov 2023. So Google Play opens Production only after a closed test with **at least 12 testers opted in for 14 days in a row** (https://support.google.com/googleplay/android-developer/answer/14151465, read 2026-10-02). This is the first campaign of [the launch plan](../plan.md), and it sets the launch date.*

*Facts are `{tokens}` from [`site-facts.json`](../../05-dev-guide/site-facts.json), filled in per language when a text is sent. `<group-link>`, `<opt-in-link>` and `<feedback-address>` are filled in by the owner. **The repo is public:** testers appear here only as codes (T01, T02 …); the owner keeps the real list outside git.*

## How the rule works (Google's words)

- **Who:** "personal developer accounts created after November 13, 2023".
- **What:** "a closed test for their app with a minimum of 12 testers who have been opted in continuously for at least 14 days".
- **Opting out resets:** "Testers who opt in, test for fewer than 14 days, and then opt out do not count … If a tester opts out and opts back in later, the 14 days must be consecutive to count."
- **What stays locked until then:**
  - Production;
  - pre-registration;
  - open testing ("Open testing becomes available after you gain production access").
- **The application:** "Apply for production" on the Dashboard, in three parts:
  - about your closed test;
  - about your app;
  - about your production readiness.
- **Review:** it "usually takes seven days or less". With too few testers or "insufficient tester engagement", Google may ask for more testing.
- **Google's tips:**
  - "The most common way to recruit testers is to use personal and professional networks";
  - "Provide a clear feedback channel";
  - "Maintain a record of received feedback."

## The owner's steps

Play Console's labels are from Google's help pages (https://support.google.com/googleplay/android-developer/answer/9845334, read 2026-10-02) and may differ slightly on screen.

**Day −1: set up**
1. [ ] **Finish the app setup** the Dashboard asks for: privacy policy (sogda.de's Datenschutz page), data safety, content rating, target audience, ads, and app access.
2. [ ] **Create the Google Group** at groups.google.com, for example `sogda-testers@googlegroups.com`, and set it so anyone can join. Testers add themselves, so there's no list to keep.
3. [ ] **Set up the closed track** under **Test and release › Testing › Closed testing › Manage track**:
   - **Testers tab:** choose **Google Groups** and enter the group's address.
   - **Feedback:** the contact address from sogda.de's Impressum. It shows on the testers' opt-in page.
   - **Countries:** at least Bangladesh, Germany, Poland, and the other countries where testers live.
4. [ ] **Build the signed AAB** with the upload key (the release's steps: v1.2.0, 1.2.0+10, #1312; including `release_android.py --require-upload-key`).
5. [ ] **Create a release on the closed track,** upload the AAB, and roll it out. Google reviews it. The opt-in link appears only once the status reads "Published".

**Day 0: open the test**
6. [ ] **Your own phone first.** Every APK the team handed out is debug-signed, and Play won't install its upload-key build over a `de.sogda.app` signed otherwise: the install fails, and uninstalling wipes the progress. So on your phone, and on any phone you gave a test APK:
   - *Me › Settings › Export / import › Save to device*;
   - uninstall Sogda;
   - install it from the opt-in link;
   - *Export / import › Import*, then *Replace*.
7. [ ] **Copy the opt-in link** (Testers tab › Copy link). Open it once with the phone in Polish and once in Russian, and check the button's label against the calls («Zostań testerem», «Стать тестировщиком»).
8. [ ] **Send the call for testers** (below). Send it first to the people who asked sogda.de to be told (O4), then to your own network, then to each community whose admins said yes.
9. [ ] **Note in the log** the day each tester opts in. **The 14 days count from the day the 12th tester is in.**

**Days 1–14: keep them in**
10. [ ] Send the three short messages to the group (day 1, day 7, day 13, below).
11. [ ] Log every piece of feedback. agent-5 files each bug or idea as an issue, and agent-0 triages.
12. [ ] Keep at least 12 opted in. **Aim for 20** so that drop-outs don't reset the count.

**Day 14+: apply**
13. [ ] **Dashboard › Apply for production,** with the answers drafted below and filled in from the log.
14. [ ] **After approval,** release the tested build to Production. The day the listing is live is *Live*, and launch day L is the first Tuesday or Wednesday after it ([`calendar.md`](../calendar.md)).

**In all, about three to four weeks:** a day or so for the closed release's review, 14 days of testing, up to about 7 days for the application's review, then the production release's own review.

## Who to ask, in order

1. **The people who asked to be told** when Sogda is out: sogda.de's mailto (O4). They chose to hear from you.
2. **Your own network:** Google's first tip. Friends and colleagues who learn German, or know someone who does.
3. **The communities, once, through their admins** ([`channels.md`](../channels.md)):
   - BDSAG and BSAAG (bn);
   - УКРАЇНЦІ В НІМЕЧЧИНІ (ru/uk);
   - Polacy w Niemczech / Krefeld … (pl);
   - DaF – Lehrer (de).

   Ask each admin **once, for both posts**: this call now, and the launch post later. If they allow only one, keep the launch post.
4. **Never** tester-swap groups or paid tester services. Google's form asks whether engagement matched real use.

**No incentive of any kind** for testing or for a review, and no "5 stars" ask (Play's policy on ratings).

## The call for testers

One message per community or person. bn and pl had agent-1's native review, ru agent-2's, en and de agent-0's (#1254).

**To anyone you sent a test APK,** add a line (agent-3, #1254): *"You have a test version from me: first save your progress (Me › Settings › Export / import › Save to device), uninstall it, install from the link, then Import › Replace."*

### en

> **Help test Sogda before it's on Google Play**
>
> I make Sogda, an offline German course app for Android: A1 to C2 in {totals.steps} steps, with {totals.words} words, {totals.grammar_topics} grammar topics and {totals.mock_exams} mock exams, and meanings and a pronunciation guide in English, Bangla, Russian or Polish. No account needed.
>
> Before a new app can go public, Google Play asks for 14 days of testing by real people. I'm looking for German learners who'd like to use it first and tell me what's wrong or missing.
>
> 1. Join the testers' group with the Google account your phone's Play Store uses: <group-link>
> 2. Open <opt-in-link>, tap "Become a tester", and install Sogda from Google Play.
> 3. Stay in the test for 14 days in a row, and use it for a few minutes on most days.
> 4. Tell me what you find: <feedback-address>, or Play's private feedback.
>
> It needs Android {app.min_android} or newer. Thank you!

### bn

> **Google Play-তে আসার আগে Sogda পরীক্ষা করতে সাহায্য করবেন?**
>
> আমি Sogda তৈরি করি, Android-এর জন্য একটি অফলাইন জার্মান কোর্স অ্যাপ: A1 থেকে C2 পর্যন্ত {totals.steps}টি ধাপ, {totals.words}টি শব্দ, {totals.grammar_topics}টি ব্যাকরণ বিষয় আর {totals.mock_exams}টি মক পরীক্ষা। প্রতিটি শব্দের অর্থ বাংলায়, উচ্চারণ বাংলা অক্ষরে। কোনো অ্যাকাউন্ট লাগে না।
>
> নতুন অ্যাপ সবার জন্য খোলার আগে Google Play চায়, আসল মানুষ ১৪ দিন সেটি পরীক্ষা করুক। তাই জার্মান শিখছেন এমন কয়েকজনকে খুঁজছি, যাঁরা আগে ব্যবহার করে জানাবেন কী ভুল আছে বা কী নেই।
>
> ১. ফোনের Play Store-এ যে Google অ্যাকাউন্ট আছে, সেটি দিয়ে টেস্টারদের গ্রুপে যোগ দিন: <group-link>
> ২. <opt-in-link> খুলে টেস্টার হওয়ার বোতামটি চাপুন (ফোনের ভাষা ইংরেজি হলে "Become a tester"), তারপর Google Play থেকে Sogda ইনস্টল করুন।
> ৩. টানা ১৪ দিন টেস্টে থাকুন, আর বেশিরভাগ দিন কয়েক মিনিট ব্যবহার করুন।
> ৪. যা চোখে পড়ে জানান: <feedback-address>, অথবা Play-এর প্রাইভেট ফিডব্যাকে।
>
> Android {app.min_android} বা তার পরের সংস্করণ লাগবে। ধন্যবাদ!

### pl

> **Pomóż przetestować Sogdę, zanim trafi do Google Play**
>
> Tworzę Sogdę, aplikację z kursem niemieckiego offline na Androida: od A1 do C2 w {totals.steps} etapach; słowa: {totals.words}, tematy gramatyczne: {totals.grammar_topics}, egzaminy próbne: {totals.mock_exams}. Znaczenia, tłumaczenia przykładów i reguły są po polsku, a wymowa jest zapisana polskimi literami. Bez konta.
>
> Zanim nowa aplikacja stanie się dostępna dla wszystkich, Google Play wymaga, by przez 14 dni testowali ją prawdziwi ludzie. Szukam osób, które uczą się niemieckiego i chcą korzystać z niej jako pierwsze, a potem powiedzieć mi, co nie działa albo czego brakuje.
>
> 1. Dołącz do grupy testerów z kontem Google, którego używasz w Sklepie Play na telefonie: <group-link>
> 2. Otwórz <opt-in-link>, stuknij „Zostań testerem” i zainstaluj Sogdę z Google Play.
> 3. Zostań w teście przez 14 dni z rzędu i zaglądaj do aplikacji na kilka minut przez większość tych dni.
> 4. Napisz, co zauważysz, na <feedback-address> albo w prywatnej opinii w Google Play.
>
> Potrzebny jest Android {app.min_android} lub nowszy. Dziękuję!

*The tokens fill numbers, not forms, so Polish and Russian write a count as «label: count» («słowa: {totals.words}», «слов: {totals.words}»), which agrees with any number (agent-1, #1377). A typed «słów» after the count turns wrong whenever the count ends in 2–4 (not 12–14), which takes «słowa». `test_marketing_docs.py` stops a noun typed after a count.*

### ru

> **Помоги протестировать Sogda до выхода в Google Play**
>
> Я делаю Sogda — приложение с офлайн-курсом немецкого для Android: от A1 до C2 за {totals.steps} этапов; слов: {totals.words}, грамматических тем: {totals.grammar_topics}, пробных экзаменов: {totals.mock_exams}. Значения, переводы примеров и правила — на русском, а произношение записано кириллицей. Без аккаунта.
>
> Прежде чем открыть новое приложение для всех, Google Play требует, чтобы его 14 дней тестировали живые люди. Ищу тех, кто учит немецкий, хочет первым попробовать Sogda, а потом рассказать, что не так или чего не хватает.
>
> 1. Вступи в группу тестировщиков с тем Google-аккаунтом, который используется в Google Play на телефоне: <group-link>
> 2. Открой <opt-in-link>, нажми «Стать тестировщиком» (если телефон на английском — «Become a tester») и установи Sogda из Google Play.
> 3. Оставайся в тесте 14 дней подряд и открывай приложение хотя бы на несколько минут почти каждый день.
> 4. Пиши, что заметишь: <feedback-address> — или отправь отзыв разработчику прямо в Google Play.
>
> Нужен Android {app.min_android} или новее. Спасибо!

### de

> **Sogda vor dem Start auf Google Play testen?**
>
> Ich entwickle Sogda, eine Offline-Deutschkurs-App für Android: von A1 bis C2 in {totals.steps} Stufen, mit {totals.words} Wörtern, {totals.grammar_topics} Grammatikthemen und {totals.mock_exams} Probeprüfungen, dazu Bedeutungen und eine Aussprachehilfe auf Englisch, Bangla, Russisch oder Polnisch. Ohne Konto.
>
> Bevor eine neue App für alle erscheint, verlangt Google Play, dass echte Menschen sie 14 Tage lang testen. Ich suche Deutschlernende, die Sogda als Erste nutzen und mir sagen, was nicht stimmt oder fehlt – und Lehrkräfte, die die App mit ihren Kursen ausprobieren möchten.
>
> 1. Treten Sie mit dem Google-Konto, das Ihr Handy im Play Store nutzt, der Testgruppe bei: <group-link>
> 2. Öffnen Sie <opt-in-link>, tippen Sie auf die Schaltfläche, um Tester zu werden („Become a tester“), und installieren Sie Sogda aus Google Play.
> 3. Bleiben Sie 14 Tage am Stück im Test, und nutzen Sie die App an den meisten Tagen ein paar Minuten.
> 4. Schreiben Sie mir, was Ihnen auffällt: <feedback-address>, oder über das private Feedback in Google Play.
>
> Nötig ist Android {app.min_android} oder neuer. Vielen Dank!

## Asking an admin (once, before posting)

> **en:** Hello, I make Sogda, an offline German course app for Android with meanings in English, Bangla, Russian or Polish. Your group's rules ask for your OK before anything like this, so I'm asking first. May I post once, in two parts: a call for testers now (Google Play asks new apps for 14 days of testing), and a short note when it's on Google Play? I'll follow your rules for the format, and I'll say clearly that I make it. Thank you either way.

The bn, pl, ru and de versions are in the launch kit (#1210). Until then, the owner writes the ask in their own words. Admins answer people, not templates.

## The three messages to the group

> **Day 1:** Thank you for testing Sogda! Besides the course, try learning from your own German: paste or share a text, choose a PDF, or photograph a letter (*Search › Learn from a document*), and see its new words marked by level. If anything looks wrong or confusing, or something's missing, write to <feedback-address>, or use Play's private feedback. The app's own *Report a problem* opens a public GitHub page, so use it only if you're happy to be seen there. Every report becomes a fix or a reply. Please stay in the test for 14 days in a row: leaving resets the count.
>
> **Day 7:** Halfway there. If you've tried a mock exam, the speaking task or the voice, I'd love to hear how it went. Thank you for staying in.
>
> **Day 13:** Tomorrow is day 14. Thank you! Please stay in until I write that the test is over. Sogda goes to Google Play soon after, and you'll hear first.

## The feedback log

agent-5 keeps it from what the owner forwards. **Codes only**, never a name or an address. A report made through the app's *Report a problem* is a public GitHub issue already: log it under the tester's code and link the issue.

Each entry carries what a fix needs (agent-3, #1254): what they did, what happened and what they expected; the version (*Me › About & privacy*, 1.2.0 (build 10) in the first release); the phone and its Android version; and the app language with the meaning language(s), which half of 1.1.0's bugs depended on.

| Date | Tester | Version | Phone, Android | App / meaning languages | Where in the app | Did, happened, expected | Issue | Changed? |
|---|---|---|---|---|---|---|---|---|
| — | T01 | — | — | — | — | — | — | — |

**Opted in** (the 14 days run from the 12th):

| Tester | Opted in on | Still in on day 14? |
|---|---|---|
| T01 | — | — |

## Drafts for "Apply for production"

agent-5 fills these from the log on day 14; the owner checks and submits.

**About your closed test**
- **How easy was it to recruit testers?** *(from the log: where they came from, and how long it took to reach 12)*
- **Which features did testers use?** *(from the log)* The candidates:
  - setup and the placement check;
  - today's plan;
  - new words and revision;
  - the course by step;
  - grammar;
  - quizzes;
  - the mock exams with writing and speaking;
  - search;
  - the voice.
  - learning from a document: paste, share, a PDF, photos, D2's marks, and *My documents* (D3).
- **Did engagement match what you expected?** *(from the log)*
- **How was feedback collected?** One email address on the opt-in page, Play's private feedback, and messages in the testers' group. Every report was logged, and each bug or idea became a GitHub issue.

**About your app**
- **Who is it for?** Adults learning German, especially from Bangla, Russian or Polish, and people preparing for German exams.
- **What makes it valuable?** Sogda is an offline German course app: A1 to C2 in {totals.steps} steps, with {totals.words} words, {totals.grammar_topics} grammar topics and {totals.mock_exams} mock exams, and meanings and a pronunciation guide in English, Bangla, Russian or Polish, no account needed. *(The listing's positioning sentence.)*
- **Estimated installs in the first year:** the owner's choice, from the ranges the form offers. Agents never guess it.

**About your production readiness**
- **What changed after the test?** *(from the log: the issues fixed, with their numbers)*
- **How did you decide it's ready?**
  - The release candidate, v1.2.0, passed SQA on an emulator in all four app languages (#1234; v1.1.0's was #1124).
  - Every bug from the closed test is fixed or triaged.
  - The fixes are in the build being released.
