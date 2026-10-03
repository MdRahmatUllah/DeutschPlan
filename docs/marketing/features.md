# Sogda as a learner meets it: the selling points, the gaps, and what we filed (#1208)

*agent-5, 2026-10-03. A walk through v1.1.0 (1.1.0+4, the tagged release) on emulator-5558, from a fresh install with setup's defaults:*
- *English: setup, day 1's session, sentence practice, the course, a step's four tabs, a word, search, Me and Settings;*
- *Bangla, Russian and Polish: setup and the first card.*

*Facts are `{tokens}` from [`site-facts.json`](../05-dev-guide/site-facts.json). The screenshots taken on the walk stay local, because the repo is public. The ones to post are the Play sets in [`store/`](../05-dev-guide/store/), named below, or re-shoots by the video and stills tools.*

## The ten strongest selling points, and the screen that shows each

| # | What a learner gets | Where it shows | The asset |
|---|---|---|---|
| 1 | **A whole course on the phone:** A1.1 to C2.2 in {totals.steps} steps, {totals.words} words and {totals.grammar_topics} grammar topics, with every step's counts in sight | L1, *Your course*: "0 of … words · 0 of … grammar topics", then each step's words and topics | `store/*/04-course.png` |
| 2 | **Meanings in your language, and a second under it** | T2's back: the first meaning, the second's line under it, and both in L2's word list | `store/*/03-card-back.png` |
| 3 | **The pronunciation in your own letters,** with a one-line key to read it | T2: `/Ауф вИдазээн/` (ru), `/auf WI-da-ze-en/` (pl), the Bangla guide (bn), each with *How to read the pronunciation* (ru, pl, en) | `store/ru-phone-light/03-card-back.png`, `store/pl-phone-light/03-card-back.png`; format 1 (#1241) |
| 4 | **In Russian and Polish, everything in your language:** examples translated, grammar rules too | T2's examples: "Auf Wiedersehen, Frau Schmidt. → До свидания, госпожа Шмидт." / "Do widzenia, pani Schmidt." | `store/ru-phone-light/`, `store/pl-phone-light/` |
| 5 | **A plan for today, with its time:** "0 / 7, ≈ 6 min", revision from tomorrow, and the week's grammar topic on the same screen | T1. After the session: "Tomorrow · 7 revisions · 7 new · ≈ 9 min" | `store/*/01-today.png` |
| 6 | **Spaced revision you can see:** every rating says when the word comes back | T2's rating bar: "Again, 1 d · Hard, 1 d · Good, {fsrs.good_days.0} d · Easy, …" ({fsrs.version}) | `store/*/03-card-back.png` |
| 7 | **An honest pace:** the app says how long a step takes, never "fluent in 3 weeks" | Setup page 4: "A1.1 takes about … days at 7 words a day"; L2: "about … days left at 7 words/day" | A still for the messaging contrast (`competitors.md`, "What we never copy") |
| 8 | **Mock exams for every step,** listening, writing and speaking included, with a result per section; the unlock threshold is the learner's to change | L2 › Exams, *What's in these exams*: "Vocabulary · Reverse · Articles · Word forms · Gap fill · Grammar · Listening · Writing · Speaking … not official Goethe or telc papers" | #1243's task videos, **once a day-1 learner can reach one (#1364)** |
| 9 | **Search both ways, offline,** with the course's sentences | R1: "appointment" finds *der Termin*, *der Kinderarzttermin* and *einen Termin vereinbaren*, plus 10 sentences | A new still or clip (R1 isn't in the Play sets) |
| 10 | **Offline, no account, nothing to sign in to;** the progress stays on the phone, and a backup is a file that "never leaves the phone unless you share it" | S2 page 1; M3 › Data › *Export / import* | Format 5, flight mode (#1245) |

**Close behind** (good for posts, weaker as headlines):
- **Sentence practice:** tap any word for its meaning, and long-press the speaker for slow audio (T5, after the session).
- **Grammar as short rules:** each step's topics read like a teacher's board, for example "Every noun has der/die/das – learn the article with the word…" (L2 › Grammar).
- **Supertonic, the offline neural voice:** offered on setup's last page and on Today's card.
- **Two meaning languages at once,** for people who learn German from their second language.

## The gaps a learner would notice

| Gap | What the learner sees | Filed |
|---|---|---|
| **The mock exams are out of reach for months at the defaults** | L2 › Exams: "Unlocks when 90% of A1.1 is introduced … about 81 days at 7 a day"; M1 lists every step as "Exams locked". The headline feature can't be tried on day 1 | **#1364** (owner's decision: a day-1 sample task, or a pointer to the setting) |
| **An English speaker who keeps the defaults gets Bangla** | An English app pre-selects বাংলা as the second meaning (#1156), and then shows the Bangla-script guide on every card (#1150). The English launch audience can't read either | **#1363** (owner's decision) |
| **"Works fully offline" is a little broader than the audio** | S2 page 1 promises it, but the sound needs the phone's German voice, or Supertonic once downloaded | **#1365** (owner's decision: say "the course") |
| **The B1 steps look thin next to their neighbours** | Placement and L1 show B1.1 and B1.2 at under 200 words each, against about 500 for an A2 or B2 step. The course front-loads A1 and A2, so the total by the end of B1 is the larger number | Not a bug. **For messaging:** state the total by the end of a level, summed from `site-facts.json`'s `steps`, never one step's count |
| **Day 1 has no quiz** | L2 › Quiz: "Quizzes open once 10 words of this step are learned · 7 so far" | Not a bug: day 2 opens it. Don't promise quizzes in day-1 posts |

**Checked and fine:**
- the Bangla and Russian defaults on setup's page 2 (Bangla + English; Russian alone);
- Russian's and Polish's first cards (guide, key, meaning, translated examples);
- the intervals on the rating bar match `site-facts.json`'s `fsrs`;
- search's hint names the chosen meaning languages (#1189).

The screen reader's «Scrim» on W1's sheet was already #1354, and it's fixed on `main` (#1362).

## What it means for the plan

- **Lead with points 1–4 and 10.** They're true on every phone on day 1, and the Play sets already show them.
- **Show the exams only through #1243's task videos,** and say how they unlock until #1364 is decided.
- **English posts should point at Settings › meaning languages,** or wait for #1363, so English speakers don't meet Bangla on their first card.
- **Use the honest pace as a contrast:** a step's days, never "fluent in N weeks". It's the opposite of what competitors promise (`competitors.md`).
