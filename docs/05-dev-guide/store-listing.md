# Store listing (Google Play)

v1.0 ships on Android only (the owner, 2026-09-26). These are the texts for the Play Console, in English and Bangla (#175), and since v1.1.0 in Polish and Russian (#1143). Play's limits: title 30 characters, short description 80, full description 4,000, *What's new* 500; `tools/tests/test_store_listing.py` checks them. The Bangla, Polish and Russian reuse the app's own wording where it says the same thing (S2's promises, the voice card, the pronunciation key's line), and Polish and Russian speak to the reader as the app does (*ty*, with the courtesy capital *Twój* in Polish). Counts take CLDR's form: Polish writes four digits solid («5142», as sogda.de does), Russian groups them with a no-break space («5 142», as the app and sogda.de do, #1194). A native reader checks the Bangla before the first upload; Polish and Russian ship on an agent's review (the owner, 2026-09-30).

v1.1.0's languages: **the app** in English, Bangla, Polish and Russian; **meanings** in English, Bangla, Russian and Polish, a first language and an optional second shown under it. Each listing leads with its own language; the Bangla listing keeps its audience's texts and adds the new languages.

Translation is not in v1.1.0 (ADR 9 kept Hy-MT off until then), so the listing doesn't mention it. Hy-MT2 arrives with v1.2.0 (ADR 30, #154), whose store notes say so.

**Search (#1176, sogda.de's master plan W4-b):** each title is "Sogda: " plus the phrase people search in that language, within Play's 30 characters. Neither a title nor a short description names "Goethe" or "telc" (their trademarks); `test_store_listing.py` checks both. The short description and the full description's second paragraph are the positioning sentence, the same one sogda.de, its FAQ and `llms.txt` use. The owner approves the wording before the listing changes.

## English (en-US)

### Title
Sogda: Learn German A1–C2

### Short description
Offline German course app: A1 to C2 in 12 steps, 36 mock exams, no account

### Full description
Learn German, one clear day at a time.

Sogda is an offline German course app: A1 to C2 in 12 steps, with 5,142 words, 182 grammar topics and 36 mock exams, and meanings and a pronunciation guide in English, Bangla, Russian or Polish. No account and no signal needed, and your progress stays on this phone.

WHAT YOU LEARN
• 12 steps from A1.1 to C2.2, built around the exams
• 5,142 words, each with examples, its article and forms where it has them, and a pronunciation guide in your meaning language: Bangla, Russian or Polish letters, or an English respelling
• 182 grammar topics, each with its rule and a short practice
• Meanings in English, Bangla, Russian or Polish: one language, or two shown together
• In Russian and Polish, the example sentences and grammar rules too

EVERY DAY
• A plan for today: revise what is due, learn a few new words, practise a grammar topic and some sentences
• Spaced revision (FSRS) brings each word back just before you would forget it
• Rest days you choose, and a daily reminder only when something is due
• A home-screen widget with a word to hear and learn

PRACTISE AND TEST YOURSELF
• Quizzes in every direction: German to your languages and back, articles, listening and word forms
• Three mock exams for every step: vocabulary, grammar, listening, writing and speaking, with a result by section
• Compare near-synonyms side by side, and add the words you meet in daily life

HEAR IT
• Every word and example is spoken with your phone's German voice
• Optional: Supertonic speaks German more naturally and works offline. About 400 MB, over Wi-Fi, downloaded once

MADE FOR YOU
• Start at your level with a short placement check
• Light, dark and glass themes, text up to 200 %, and screen-reader support
• The app in English, Bangla, Polish or Russian

### What's new (1.1.0)
New: the app in Polish and Russian, and meanings in English, Bangla, Russian or Polish: pick one, and a second to show under it. The pronunciation guide follows your meaning language, with a one-line key to read it, and search, quizzes and mock exams use your languages. Also the first release as Sogda, with a new icon and a smaller download, and about a hundred fixes: fairer answer checking, a mock exam that keeps every answer, and restoring a backup at setup.

## Bangla (bn-BD)

### Title
Sogda: জার্মান ভাষা A1–C2

### Short description
অফলাইন জার্মান কোর্স অ্যাপ: A1 থেকে C2, ১২টি ধাপ, ৩৬টি মক পরীক্ষা, বাংলা অর্থসহ

### Full description
প্রতিদিন একটু একটু করে জার্মান শিখুন।

Sogda একটি অফলাইন জার্মান কোর্স অ্যাপ: A1 থেকে C2 পর্যন্ত ১২টি ধাপে ৫,১৪২টি শব্দ, ১৮২টি ব্যাকরণ বিষয় আর ৩৬টি মক পরীক্ষা, সঙ্গে ইংরেজি, বাংলা, রুশ বা পোলিশে অর্থ আর উচ্চারণ নির্দেশিকা। অ্যাকাউন্ট বা ইন্টারনেট লাগে না, আর আপনার অগ্রগতি এই ফোনেই থাকে।

যা শিখবেন
• A1.1 থেকে C2.2 পর্যন্ত ১২টি ধাপ, পরীক্ষার কাঠামো মেনে সাজানো
• ৫,১৪২টি শব্দ, প্রতিটির উদাহরণ আর বাংলা হরফে লেখা উচ্চারণসহ, আর যেখানে আছে সেখানে আর্টিকেল ও রূপ
• ১৮২টি ব্যাকরণ বিষয়, প্রতিটির নিয়ম আর ছোট অনুশীলনসহ
• অর্থ ইংরেজি, বাংলা, রুশ বা পোলিশে: একটি ভাষায়, বা দুটি একসঙ্গে

প্রতিদিন
• আজকের পরিকল্পনা: যা রিভিশনের সময় হয়েছে, কয়েকটি নতুন শব্দ, একটি ব্যাকরণ বিষয় আর কিছু বাক্যের অনুশীলন
• স্পেসড রিভিশন (FSRS) প্রতিটি শব্দ ভুলে যাওয়ার ঠিক আগে ফিরিয়ে আনে
• বিশ্রামের দিন আপনি বেছে নেন, আর দৈনিক রিমাইন্ডার আসে শুধু কিছু বাকি থাকলে
• হোম-স্ক্রিন উইজেটে শোনার ও শেখার জন্য একটি শব্দ

অনুশীলন ও নিজেকে যাচাই
• সব দিকে কুইজ: জার্মান থেকে ইংরেজি, জার্মান থেকে বাংলা, ইংরেজি থেকে জার্মান, আর্টিকেল, শোনা আর শব্দের রূপ
• প্রতিটি ধাপের জন্য তিনটি মক পরীক্ষা: শব্দভান্ডার, ব্যাকরণ, শোনা, লেখা আর বলা, প্রতিটি অংশের ফলসহ
• কাছাকাছি অর্থের শব্দ পাশাপাশি তুলনা করুন, আর দৈনন্দিন জীবনে পাওয়া শব্দ নিজে যোগ করুন

শুনুন
• প্রতিটি শব্দ আর উদাহরণ আপনার ফোনের জার্মান কণ্ঠে শোনা যায়
• ঐচ্ছিক: Supertonic আরও স্বাভাবিকভাবে জার্মান বলে এবং অফলাইনে চলে। প্রায় ৪০০ MB, ওয়াই-ফাইতে, একবারই ডাউনলোড।

আপনার জন্য তৈরি
• ছোট একটি লেভেল যাচাই দিয়ে নিজের স্তর থেকে শুরু করুন
• লাইট, ডার্ক আর গ্লাস থিম, ২০০ % পর্যন্ত বড় লেখা, আর স্ক্রিন রিডার সাপোর্ট
• অ্যাপ ইংরেজি, বাংলা, পোলিশ বা রুশ ভাষায়

### What's new (1.1.0)
নতুন: অ্যাপ এখন পোলিশ ও রুশ ভাষায়, আর অর্থ ইংরেজি, বাংলা, রুশ বা পোলিশে: একটি বেছে নিন, চাইলে তার নিচে আরেকটি। উচ্চারণ লেখা হয় আপনার অর্থের ভাষায়, সঙ্গে "উচ্চারণ কীভাবে পড়বেন" এক লাইনে; সার্চ, কুইজ আর মক পরীক্ষাও আপনার ভাষায়। সঙ্গে Sogda নামে প্রথম রিলিজ: নতুন আইকন, আরও ছোট ডাউনলোড, আর প্রায় একশোটি সংশোধন: উত্তর আরও ন্যায্যভাবে যাচাই হয়, মক পরীক্ষা প্রতিটি উত্তর রাখে, আর সেটআপের সময় ব্যাকআপ ফেরানো যায়।

## Polish (pl-PL)

### Title
Sogda: niemiecki od zera do C2

### Short description
Kurs niemieckiego offline, A1–C2: 12 etapów, 36 egzaminów próbnych, po polsku

### Full description
Ucz się niemieckiego dzień po dniu, z jasnym planem.

Sogda to aplikacja z kursem niemieckiego offline: od A1 do C2 w 12 etapach, z 5142 słowami, 182 tematami gramatycznymi i 36 egzaminami próbnymi, ze znaczeniami i wskazówkami wymowy po angielsku, bengalsku, rosyjsku lub polsku. Bez konta i bez zasięgu, a Twoje postępy zostają na tym telefonie.

CZEGO SIĘ NAUCZYSZ
• 12 etapów od A1.1 do C2.2, ułożonych pod kątem egzaminów
• 5142 słów, każde z przykładami, z rodzajnikiem i formami tam, gdzie je ma, oraz z wymową zapisaną polskimi literami
• 182 tematy gramatyczne, każdy z regułą i krótkim ćwiczeniem; reguły i przykłady są po polsku
• Znaczenia po polsku, a pod nimi, jeśli chcesz, drugi język: angielski, bengalski lub rosyjski

CODZIENNIE
• Plan na dziś: powtórz to, co trzeba, poznaj kilka nowych słów, przećwicz temat gramatyczny i kilka zdań
• Powtórki w odstępach (FSRS) przywołują każde słowo tuż przed tym, zanim je zapomnisz
• Dni wolne wybierasz sam, a codzienne przypomnienie przychodzi tylko wtedy, gdy coś czeka
• Widżet na ekranie głównym ze słowem do posłuchania i nauki

ĆWICZ I SPRAWDZAJ SIĘ
• Quizy w każdą stronę: z niemieckiego na polski, z polskiego na niemiecki, rodzajniki, słuchanie i formy słów
• Trzy egzaminy próbne dla każdego etapu: słownictwo, gramatyka, słuchanie, pisanie i mówienie, z wynikiem dla każdej części
• Porównuj bliskie synonimy obok siebie i dodawaj słowa, które spotykasz na co dzień

POSŁUCHAJ
• Każde słowo i każdy przykład czyta niemiecki głos Twojego telefonu
• Opcjonalnie: Supertonic mówi po niemiecku naturalniej i działa offline. Około 400 MB, przez Wi-Fi, pobierane raz

DLA CIEBIE
• Zacznij od swojego poziomu dzięki krótkiemu testowi poziomującemu
• Motyw jasny, ciemny i szklany, tekst do 200 % i obsługa czytników ekranu
• Aplikacja po polsku, angielsku, bengalsku lub rosyjsku

### What's new (1.1.0)
Nowość: aplikacja po polsku i po rosyjsku, a znaczenia po angielsku, bengalsku, rosyjsku lub polsku: wybierz jeden język i, jeśli chcesz, drugi pod spodem. Wymowa jest zapisana w języku Twoich znaczeń, z jednym wierszem „Jak czytać wymowę”, a wyszukiwanie, quizy i egzaminy próbne działają w Twoich językach. To także pierwsze wydanie jako Sogda: nowa ikona, mniejszy plik do pobrania i około stu poprawek.

## Russian (ru-RU)

### Title
Sogda: немецкий с нуля до C2

### Short description
Курс немецкого офлайн, A1–C2: 12 этапов, 36 пробных экзаменов, всё на русском

### Full description
Учи немецкий день за днём, с ясным планом.

Sogda — приложение с офлайн-курсом немецкого: от A1 до C2 за 12 этапов: 5 142 слов, 182 грамматические темы и 36 пробных экзаменов, а значения и подсказки произношения — на английском, бенгальском, русском или польском. Без аккаунта и без сети: твой прогресс остаётся на этом телефоне.

ЧТО ТЫ ВЫУЧИШЬ
• 12 этапов от A1.1 до C2.2, по структуре экзаменов
• 5 142 слов, у каждого — примеры, артикль и формы, где они есть, и произношение, записанное русскими буквами
• 182 грамматические темы, у каждой — правило и короткая практика; правила и примеры на русском
• Значения на русском, а под ними, если хочешь, второй язык: английский, бенгальский или польский

КАЖДЫЙ ДЕНЬ
• План на сегодня: повтори то, что пора, выучи несколько новых слов, потренируй грамматическую тему и несколько предложений
• Интервальные повторения (FSRS) возвращают каждое слово прямо перед тем, как ты его забудешь
• Выходные ты выбираешь сам, а ежедневное напоминание приходит, только когда что-то ждёт
• Виджет на главном экране со словом, которое можно послушать и выучить

ТРЕНИРУЙСЯ И ПРОВЕРЯЙ СЕБЯ
• Тесты в любом направлении: с немецкого на русский, с русского на немецкий, артикли, аудирование и формы слов
• Три пробных экзамена на каждый этап: лексика, грамматика, аудирование, письмо и говорение, с результатом по каждой части
• Сравнивай близкие синонимы рядом и добавляй слова, которые встречаешь в жизни

СЛУШАЙ
• Каждое слово и каждый пример звучат немецким голосом твоего телефона
• По желанию: Supertonic говорит по-немецки естественнее и работает офлайн. Около 400 МБ, по Wi-Fi, скачивается один раз

ДЛЯ ТЕБЯ
• Начни со своего уровня после короткого теста
• Светлая, тёмная и стеклянная тема, текст до 200 % и поддержка программ экранного доступа
• Приложение на русском, английском, бенгальском или польском

### What's new (1.1.0)
Новое: приложение на польском и русском, а значения — на английском, бенгальском, русском или польском: выбери один язык и, если хочешь, второй под ним. Произношение записано на языке твоих значений, с одной строкой «Как читать произношение», а поиск, тесты и пробные экзамены работают на твоих языках. Это и первый выпуск под именем Sogda: новая иконка, меньший размер загрузки и около ста исправлений.

## Screenshots

`store/phone-light`, `phone-dark`, `tablet-light` and `tablet-dark`, eight each: the first six from the release x86_64 APK of 1.1.0+4 on emulator-5558 (wiped, API 36), English UI and English meanings, the course's own content (re-shot 2026-10-01: the 1.0 set counted 5,594 words):

| File | Screen |
|---|---|
| `01-today.png` | T1, day 1 with three of today's words studied |
| `02-card-front.png` | T2, a new word's card |
| `03-card-back.png` | T2, turned over: meanings, examples, the rating bar |
| `04-course.png` | L1, the course by level |
| `05-step.png` | L2, a step's words |
| `06-word.png` | W1 over L2 (a sheet on the phone, a side pane on the tablet) |
| `07-document.png` | D2 over the landlord's letter, «Nebenkosten 2025»: its words marked by level, the *Show words I probably know* switch, the bulk bar (1.2.0, #1307) |
| `08-document-card.png` | D2's card for *die Nachzahlung*: its step, meaning and the sentence under *In your text* (1.2.0, #1307) |

- **Phone:** 1080 × 2160 (`wm size`), since Play takes at most 2:1.
- **Tablet:** 1600 × 2560 at density 320, a 10-inch tablet.
- **The status bar** is Android's demo mode (10:00, full Wi-Fi and battery). Light and dark follow the system setting.
- **Format:** RGB PNGs without alpha, as Play asks. `test_store_listing.py` checks the format, the sizes and the ratio.
- **D2 and its card (1.2.0, #1307):** in every set, from the release x86_64 APK of main at 1.2.0's content (5,142 words), after #1346. A fresh install, onboarded at A2.1 with the set's languages; the landlord's letter (D2's widget fixture, `artboardLetter`) shared in through `ShareActivity`, renamed «Nebenkosten 2025» in D3, as the artboard titles it, and opened again from D3. Nothing added, so every new word shows its level.
- **Not included:** a mock exam (L12), which unlocks only once 90 % of a step is introduced; day 1 can't reach it. Take one on a device with progress before the upload if the owner wants it.

### Polish and Russian (#1123)

`store/pl-phone-light` and `store/ru-phone-light`, the same eight screens, taken as the English ones were (the release x86_64 APK on emulator-5558, wiped, API 36, 1080 × 2160, the demo status bar), from the course with Russian and Polish (#1100):

- **The app language and the first meaning language** are Polish for `pl-phone-light` and Russian for `ru-phone-light`, with no second meaning. So each card shows that language's meaning, its pronunciation guide and its example lines: *danke* → *dziękuję / dzięki*, `/DAN-ke/`; → *спасибо*, `/дАнкэ/`.
- **Upload them** under the Polish (pl-PL) and Russian (ru-RU) listings. The English phone and tablet sets serve English and any listing without its own set.
- **No dark or tablet sets** in Polish and Russian: Play shows a listing's own screenshots where it has them, and the phone set is what it requires.

### Bangla (#1175)

`store/bn-phone-light`, the same eight screens, taken the same way (the release x86_64 APK on emulator-5558, a fresh install, API 36, 1080 × 2160, the demo status bar with full Wi-Fi):

- **The app language is Bangla, and the meanings are Bangla first and English second**, setup's default for a Bangla app (#1156). So *danke* shows *ধন্যবাদ* with *thanks / thank you* under it, and the Bangla-letter guide `/ডাংকে/`. The course has no Bangla example lines, grammar rules or topic names, so those show in English, as every Bangla learner sees them.
- **Upload them** under the Bangla (bn-BD) listing. sogda.de's `/bn` shows them too (sogda-website #66).
- **The sequence**, which gives the states the Polish set shows: onboarding with the defaults (the meanings as setup offers them, A1.1, 7 new words a day), no name, the voice card dismissed. Then:
  1. Rate the first three new cards *Good*. The fourth, *danke* (4 / 7), is `02-card-front`, and turned over it is `03-card-back`.
  2. Close the session. Today at 3 / 8 is `01-today`.
  3. The course tab is `04-course`, A1.1 is `05-step`, and *Auf Wiedersehen*'s sheet over it is `06-word`.
- **Re-shoot every set with each release** (`release.md`, step 7), so the listings never show an older app's screens or counts.

## Website and icon

- **Website:** https://sogda.de, the brand kit's domain (#602): the Play Console's *Website* under the store listing's contact details.
- **The website's facts** (#1174): [`site-facts.json`](site-facts.json) is what sogda.de states. `tools/export_site_facts.py` writes it; the site's `pnpm sync:facts` fetches it at a pinned commit.
  - **What it holds:**
    - the course's counts from `content.db`;
    - the mock paper's shape (BR-EXAM-02/03 and the app's `ExamSection`);
    - the scheduler's numbers (#1182): BR-FSRS-01, BR-PLAN-02's defaults and `fsrs-scheduler.md`'s reference values, which `fsrs_test.dart` checks against the file;
    - the version and the Android floor from the build files;
    - 25 sample words per step, chosen by a hash of their uid so they only change with the step;
    - these listing texts, verbatim.
  - **When to re-run it:** after a content build, a listing change or a release, run `python tools/export_site_facts.py`. `test_site_facts.py` fails while the file is stale.
- **App icon:** [`docs/sogda-brand-kit/png/play-store-icon-512.png`](../sogda-brand-kit/png/play-store-icon-512.png), 512 × 512, the kit's tiles on full-bleed Lagoon. Play rounds the corners; add no shadow (the kit's rule). Play wants a 32-bit PNG with alpha, and the kit's file is RGB: upload an RGBA copy with an opaque alpha channel, and leave the kit's file as it is. `test_store_listing.py` checks the file and its size.
- **Feature graphic** (1024 × 500, required before the first upload, #1200): one per listing, [`store/feature-graphic/en.png`](store/feature-graphic/en.png) for English (and any listing without its own), [`bn.png`](store/feature-graphic/bn.png) for Bangla, [`pl.png`](store/feature-graphic/pl.png) for Polish and [`ru.png`](store/feature-graphic/ru.png) for Russian. Each is the kit's wordmark (`svg/wordmark-ink.svg`) with the listing's title under it (without "Sogda: ", which the wordmark says), and beside them the listing's own `03-card-back.png` from its Play set, on full-bleed Lagoon, all in the middle, since Play crops the edges in some placements. No tiles: Play advises against branding that repeats the icon shown next to the graphic (#1323). RGB PNGs. `python tools/media/feature_graphic.py` re-renders them from this file's titles and the Play sets, so re-run it whenever a title or a set changes; `test_store_listing.py` checks their size and format.
