# How competing apps market themselves, and what Sogda takes from it (#1202)

*Read on 2026-10-02, logged out. Every number, link and quote is in the research file, [`research/2026-10-02-competitors-and-play.md`](research/2026-10-02-competitors-and-play.md); this page is the digest. Their websites and SEO were covered in sogda-website's review ([`docs/research/2026-09-30-website-review.md`](https://github.com/MdRahmatUllah/sogda-website/blob/dev/docs/research/2026-09-30-website-review.md)), so this page is about social media and launches.*

## Who does what

| Who | Where | Cadence | What they post | What Sogda takes | What Sogda never does |
|---|---|---|---|---|---|
| **Duolingo** | TikTok (main and a German account), Instagram, YouTube, X | About daily | A mascot in pop-culture skits and brand collaborations; little actual teaching | **Comment prompts** ("translate this, wrong answers only" drew 17,300 comments on 166,500 plays), and words tied to a news moment | A mascot persona (it needs a daily team), streak guilt, purchase-linked promotions, paid reach |
| **Babbel** | TikTok; YouTube and X dormant | About five a week on TikTok | "What do you call this where you're from?", street interviews | **Hooks that invite the viewer's own language** into the comments. Sogda has four meaning languages | "Speaking in 3 weeks", "a semester in 15 hours", or any time promise |
| **Busuu** | TikTok, faded | About two a month now | Tips, polls | **A video reply to a real commenter** (its most-played post ever) | Efficacy claims ("22 hours = a semester"), an account left to fade after a good year |
| **Memrise** | Practically dormant | — | "How to say X in five languages", testimonials | Nothing. Generic "X in five languages" clips don't travel | A "new user testimonial" |
| **Easy German** | YouTube, TikTok daily, Instagram | YouTube about three a week | Street interviews, real learners' stories, **exam walk-throughs** | **Exam videos** (its telc B1 video holds 309,701 views); **a question as the hook** | Staged learners: theirs are real and on camera, and Sogda has none to film yet |
| **DW Learn German** | YouTube, TikTok, Instagram, Facebook | Daily | Daily easy news; Nicos Weg cut into Shorts that all point to one link; article quizzes | **The der/die/das quiz** (5,583 comments); **"answer in a full sentence"** (2.3K comments); many clips, one link | Daily posts without a hook: its news slides reach about 1–5K |
| **Exam creators:** Deutsch lernen mit Dialogen, Benjamin, Deutsche Filme | YouTube | Weekly to monthly | A model answer for a named exam part; filmed mock orals | **A title that names the level and the exam part**, made for YouTube search, where old videos keep pulling views | Pass promises, seat scarcity ("don't wait too long"), next year in the title |
| **Viobean** (an exam app) | TikTok, Instagram | In bursts | Exam-difficulty hooks | — | Its site's rating, user count, price ("less than €0.50 a day") and first-name testimonials; nine near-identical posts in one day |
| **Bangla creators:** Learn German with KKS, Life360 Germany, German from Null | YouTube; Facebook (login-walled) | Weekly to irregular | **Lesson 1, the alphabet and numbers**: 436K–971K views each | **The pronunciation magnet**, shown in Bangla letters, which no creator does in a short video | View counts in titles ("1M+ Views"), fear hooks, success-story uploads |
| **Russian creators:** Немецкий с нуля!, Deutsch Online (Telegram), Dein Sprachcoach, Немецкий из Берлина | YouTube, Telegram | Monthly to daily | Lesson 1 (9.9M views), reading rules (2.7M), phrase lists on Telegram, **prefix cards** (837 shares) | **Save-and-share cards**; phrase lists for Telegram | Discount spam and promo codes ("–70%", «ФОКУС»), "JETZT" urgency, "this METHOD makes you speak" |
| **Polish creators:** Deutsch mit Wojtek, Natalia Kamysz | TikTok (works for pl), YouTube daily | Every 1–3 days | **"A word that fools Polish speakers"** (DZIĘKI ≠ Danke), German for carers | **The false-friend format**, done daily by Polish teachers and by nobody in Bangla | Subscriber-count bragging ("79 000+"); course ads, which got under 450 plays |

## What it adds up to

1. **The big apps teach nothing on social media.** Their reach comes from comedy and paid boosts, which a one-person maker can't copy. **Teachers win** with lesson 1, pronunciation, quizzes, exam parts and word cards. Sogda's posts should look like a teacher's, using real screens.
2. **Comments beat reach.** The posts that ask for an answer (der, die or das; a full sentence) get thousands of comments on modest reach. Comments are also where questions come from, and answering them is how the owner shows "I make this app".
3. **Each audience has its own home.**
   - **Bangla:** YouTube, plus Facebook (login-walled, so unmeasured).
   - **Russian:** YouTube and Telegram.
   - **Polish:** TikTok and YouTube.
   - **English:** TikTok, Shorts and Discord. Reddit bans app promotion; see [`channels.md`](channels.md).
4. **Exam content is search content.** It grows slowly on YouTube and keeps going for years. That makes it a long-term format, not a launch-day one.
5. **Ads underperform teaching.** Even the creators' own course ads get a fraction of their lessons' reach. Every Sogda post teaches something first.

## What we never copy

These are banned by Sogda's rules, and the starred ones by Google Play's Metadata policy too:
- **price, discount, promo-code or "free" claims\***;
- **fake urgency** ("JETZT", "only today", seat scarcity);
- **ratings, user counts, view or subscriber counts\***, and "#1", "best" or "New"\*;
- **testimonials**, staged or first-name\*;
- **pass promises**, and time or efficacy promises;
- **paid reach** used as a benchmark;
- **the same post repeated** to fill a calendar.

## Sogda's five formats

Every format shows real screens from the release build, quotes the app's own meaning and guide text (never retyped), and names no number but tokens. Each caption goes through its native reviewer. Each link carries its referrer ([`messaging.md`](messaging.md)).

### 1. "Say it in your letters"

The pronunciation guide in the viewer's own script.

- **Why:** pronunciation and lesson 1 are the biggest magnets in all three languages (436K–9.9M views). Nobody shows German written in Bangla letters in a short video.
- **Format:** 6–10 s, vertical. The word card, the guide line in the viewer's script, a tap on the speaker, the sound.
- **Example (bn):**
  - **Video:** {featured.0.article} {featured.0.german}, with its guide «{featured.0.guide.bn}» and its sound.
  - **Caption** (*draft*): «Anmeldung কীভাবে বলবেন? বাংলা অক্ষরে লেখা উচ্চারণ, ইন্টারনেট ছাড়াই।»
- **The same clip in ru and pl:** the same video re-cut with «{featured.0.guide.ru}» and «{featured.0.guide.pl}».
- **Series:** the twelve words of `featured` in `site-facts.json`, from *Anmeldung* to *Einbürgerung*. That's one a week for twelve weeks, with no word to invent.

### 2. "der, die or das? Answer in a full sentence"

- **Why:** DW's article quiz drew 5,583 comments, and its full-sentence prompt 2.3K.
- **Format:** a still or a 5 s clip with three nouns. The answer goes in a pinned comment the next day, with the app's card for each.
- **Example:** "Messer, Gabel, Löffel: der, die or das? Answer with a whole sentence, like 'Der Tisch ist groß.' (no hint for the three) The answers come tomorrow, straight from the app."
  - It works because the course has one of each: *das Messer* (A1.2), *die Gabel* (A1.1) and *der Löffel* (A1.2).

### 3. "A mock-exam task in 15 seconds"

- **Why:** exam-part videos are evergreen YouTube search traffic (up to 3.38M views).
- **Format:** a screen recording of one task with the timer visible, then the result screen.
  - The title names the level and the task: listening, writing or speaking.
  - **Never reading:** Sogda's mock exams have no reading part.
- **Example:** "B1 writing in 15 seconds: the task, the timer, the result. A practice task from Sogda's mock exam, which is not an official Goethe or telc paper."
  - The task asks for at least {mock_exam.writing_min_words.B1} words at B1.
- **Where:** YouTube Shorts and long-form, not the TikTok feed.

### 4. "The word that fools [your language] speakers"

- **Why:** Polish teachers do this daily (DZIĘKI ≠ Danke). Babbel's "what's it called where you're from" drew 342,600 plays. Nobody does it in Bangla.
- **Format:** a split card or a 7 s clip. The German word sits beside its look-alike, then the app's own meaning in the viewer's language.
- **Examples** (every word is in the course, and each meaning is the app's own text):
  - **ru:** *der Termin* ≠ «термин». In the app, *Termin* is «запись (к врачу) / встреча». Also *die Familie* ≠ «фамилия»: the app says «семья».
  - **pl:** *das Gymnasium* ≠ «gimnazjum». The app says «liceum ogólnokształcące (Gymnasium)».
  - **en / bn:** *das Gift* is poison. The app itself marks it as a false friend, "poison (false friend: not 'gift')", and «বিষ (ভুল বন্ধু)». Also *bekommen* means "to get / to receive", not "to become".

### 5. "Flight mode on"

- **Why:** offline is the real difference, and it's provable on screen. OffChess, an offline Android app with no account, reached 369 points on Show HN with that pitch.
- **Format:** 10–12 s. The status bar shows flight mode, then Sogda opens, three cards are reviewed, and the day's plan shows done. Captions only.
- **Example:** "Underground. Flight mode. Still learning German: no account, no signal, and your progress stays on this phone."

### Which format goes where

| Format | bn | ru | pl | en | Exam |
|---|---|---|---|---|---|
| 1. Your letters | Facebook, YouTube Shorts | YouTube Shorts, Telegram | TikTok | — | — |
| 2. der, die or das | Facebook | Telegram, VK | TikTok, Facebook | TikTok, Shorts, Discord | — |
| 3. Mock-exam task | YouTube | YouTube | YouTube | YouTube | YouTube (the main home) |
| 4. False friends | Facebook | Telegram, YouTube Shorts | TikTok | TikTok, Shorts | — |
| 5. Flight mode | Facebook | Telegram | TikTok | Shorts, Show HN | — |
