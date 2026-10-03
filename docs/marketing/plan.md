# The launch plan: getting the most out of Sogda's first Play release

*agent-5 (Marketing & Media), 2026-10-02, for the owner and the team. This page is the plan. The research and the detail it rests on are in the files it links. Every fact is a token from [`site-facts.json`](../05-dev-guide/site-facts.json) (see [`messaging.md`](messaging.md)). Nothing here is posted or sent by an agent: the owner posts and sends everything.*

## The plan in one screen

- **The first thing is a check, not a post.** If the owner's Play developer account is a personal one created after 13 Nov 2023, Google opens Production only after **a closed test with 12 testers opted in for 14 days in a row**, plus a review of up to about a week. Then launch is about three weeks after the 12th tester joins, and **recruiting real learners as testers is the first campaign** (D1, #1239).
- **Who, in order:**
  1. Bangla speakers;
  2. Russian speakers;
  3. Polish speakers;
  4. exam candidates;
  5. English speakers;
  6. the teachers who recommend.

  The order follows where Sogda's edge is sharpest, and where an honest post is allowed.
- **What we say:** the combination nobody else has, and, new in the first release (v1.2.0, #1383), learning from the German you meet: share or photograph a letter, and Sogda marks its new words by level. Offline, no account, A1 to C2, mock exams for every step, and meanings and pronunciation in the learner's own script. We show it with real screens, never claim it with superlatives. **No price, "free", rating, user count, testimonial or pass promise**, ever.
- **Where:**
  - **One approved post in each of about eight communities,** with the admins asked first. The biggest are the Bangla student groups in Germany (62.1K and 124.8K members), the largest Ukrainian diaspora chat that allows it, and the most active Polish group in Germany.
  - **Pitches** to the roundups, DW Russian and four creators.
  - **Show HN.**
  - **AlternativeTo.**
  - **Sogda's own Facebook Page and YouTube channel** for everything weekly.
  - **No Reddit launch post:** r/German, r/germany and r/Polska ban app promotion. r/languagelearning allows one comment in its monthly resources thread.
- **When:**
  - **L is the first Tuesday or Wednesday after the listing goes live.** On L, each audience gets its post in its own evening.
  - **The pitches go out in the next two days.**
  - **Weeks 2–6 run on five formats:** your letters, der/die/das, the mock-exam task, false friends, flight mode. Each is about one sitting a day for the owner.
- **How we know:**
  - **Every link carries a referrer,** and Play Console counts installs per channel.
  - **The owner pastes the numbers every Monday.**
  - **Week 1 is the baseline** for the targets, and a channel that brings nothing in two weeks is dropped.
- **What the owner decides now:** D1 to D8 in §10. **D1 decides the date.**

## 1. What "the most out of it" means

A first release has one chance to be new. We have no ads budget, no analytics (the owner's rule), and no ratings yet. So the plan aims at what a launch can win once, and keeps what it learns:

| # | Goal | How we know (no analytics needed) |
|---|---|---|
| G1 | **Installs we can trace to a channel**, so week 2 puts its time where week 1 worked | Play Console's acquisition report, by the referrer on every link we hand out ([`messaging.md`](messaging.md), *The Play link*) |
| G2 | **The first honest ratings and reviews,** in each listing's language: the proof we lack today | The Play Console's ratings and reviews. We never offer anything for a review (Play's policy, and the owner's rules) |
| G3 | **Listed where people choose apps:** the roundup articles, AlternativeTo, and the communities' own recommendation threads | The outreach table (`outreach.md`, #1212): sent, answered, listed |
| G4 | **sogda.de found, and cited by AI answers,** for the niche Sogda owns: offline, A1 to C2, mock exams, and learning from Bangla, Russian or Polish | Search Console, Bing and Yandex (O1 on sogda-website #56), and the monthly AI panel (sogda-website #65) |
| G5 | **What learners tell us becomes the next release:** every bug, question and wish from a comment becomes an issue | The issues labelled `marketing`, and what MK3 plans |

**Targets.** The first week's numbers are the baseline; we don't guess them before launch. At the end of week 1, agent-5 writes them into [`results.md`](results.md), and the owner sets the week 2–6 targets from them. What we control gets targets now, in §7: every launch-kit post out within a day of L, every pitch sent in week 1, and every comment answered within a day.

## 2. Before launch: the gates

The listing can't go live, or can't be worth announcing, until these are done. The *Who* column says whose each one is.

| # | Gate | Why it matters | Who | Where |
|---|---|---|---|---|
| **1** | **Check the Play account's type and creation date.** A personal account created after 13 Nov 2023 must run a closed test with **at least 12 testers opted in for 14 days in a row** before it may apply for Production. Google's review then "usually takes seven days or less". | If it applies, **launch is about three weeks after the 12th tester opts in** (14 days, plus the review), and recruiting testers becomes the first campaign. Production, pre-registration and open testing all stay locked until then (https://support.google.com/googleplay/android-developer/answer/14151465, read 2026-10-02) | The owner | #1239 |
| 2 | Sign and upload v1.2.0 (1.2.0+10, #1312), the first release (#1383), with the listing in en, bn, pl and ru: titles, texts, screenshots per locale and the feature graphics, all on `main` | The listing itself | The owner | #1123 |
| 3 | The promo video on YouTube (unlisted, ads off), linked in the listing | Play autoplays its first 30 s on the listing | agent-5 makes it, the owner uploads it | #1211 |
| 4 | Search Console, Bing and Yandex for sogda.de | Without them, G4 can't be measured | The owner | O1 on sogda-website #56 |
| 5 | The accounts the plan uses (§5) | The Bangla groups need a real profile; the Page and the channel are where links point | The owner, from agent-5's kit | #1240 |
| 6 | The Play badge on sogda.de, with the site's referrer | The site is where pitches and AI answers send people | agent-4 | sogda-website #45 |
| 7 | The launch kit, reviewed: every post, image and video, with `<play-link>` waiting | Launch day takes an hour, not a week | agent-5, reviewed by agents 0, 1 and 2 | #1210 |

**Not available at launch,** whatever we do (Google's own pages, read 2026-10-02):
- **Promotional content and the store's YouTube integration** need Premium growth tools (millions of monthly users, or ad spend).
- **Custom store listings and store listing experiments** need an app that is already published.
- **Managed publishing,** which would let the owner pick the hour the listing goes live, "can't" be used for a first release.

After launch, the cheap win is **a custom listing per audience URL**, for example `&listing=bn` with the Bangla screenshots first, for links posted in Bangla communities (week 3 or later). Details: [`research/2026-10-02-competitors-and-play.md`](research/2026-10-02-competitors-and-play.md), part B.

## 3. Who it's for, in launch order

The order follows where Sogda's edge is sharpest and where the audience can be reached honestly. Each audience's message, proof points and objection are in [`messaging.md`](messaging.md).

1. **Bangla speakers, in Bangladesh and in Germany.**
   - **Why first:** the least-served audience. No rival has A1 to C2 with Bangla meanings and the guide in Bangla letters.
   - **Where:** it gathers in a few very large Facebook groups and around YouTube's lesson-1 videos (436K–971K views each).
2. **Russian speakers.**
   - **Why:** everything is in Russian (meanings, examples, grammar rules), to C2, while the most-watched Russian courses are for beginners.
   - **Where:** YouTube and Telegram (lesson 1 has 9.9M views).
3. **Polish speakers.**
   - **Why:** everything is in Polish, to C2, where the Polish-language apps in sogda.de's review stop at A1 to B1.
   - **Where:** TikTok works for this audience, unlike for Bangla and Russian; and Facebook groups in Germany.
4. **Exam candidates, any language.**
   - **Where:** YouTube search, where exam-part videos keep drawing views for years.
   - **Pace:** slow to start, then the longest tail.
5. **English-speaking learners.**
   - **Why last:** the largest audience, but the most crowded, and its biggest communities ban app promotion (r/German, r/germany) or confine it to one monthly thread (r/languagelearning).
   - **Where:** Discord, short video, Show HN and AlternativeTo.
6. **People in Germany who recommend.** Teachers, volunteers and integration-course staff don't learn from Sogda; they pass it on. One teachers' group (DaF – Lehrer) hears at launch; then the German site and pitches carry it.

## 4. The message

[`messaging.md`](messaging.md) has it per audience, in each language. In short:
- **One sentence everything comes from:** the store listing's positioning sentence, in each listing's own approved words.
- **The proof is the product:** a real word card, a real guide in Bangla, Cyrillic or Polish letters, a real mock-exam task, flight mode on.
- **The owner speaks as the maker,** in every community: "I make this app".

## 5. The channels

[`channels.md`](channels.md) has the full map, with sizes, rules and sources. **The ranked top 10:**

1. BDSAG and BSAAG (bn, Facebook), through the admins, plus BSAAG's article route (#1246);
2. УКРАЇНЦІ В НІМЕЧЧИНІ (ru/uk, Telegram), through @Mod_ukr;
3. Polacy w Niemczech / Krefeld … (pl, Facebook), through the admins;
4. DW Russian (ru), an editorial pitch;
5. r/languagelearning's monthly "Share Your Resources" thread (en);
6. DaF – Lehrer (de, Facebook), through the moderators;
7. German Learning and Discussion (en, Discord), if its rules allow;
8. Show HN (en);
9. four creators, one honest message each: KKS (bn), DeutschMosaik (exam), Deutsch mit Yehor (ru), Natalia Kamysz (pl);
10. the roundups and AlternativeTo (sogda-website #76, #1212).

**Sogda's own channels** carry the weekly rhythm, and every community post links back to them:
- **a Facebook Page** (bn first);
- **a YouTube channel:** the promo video, the exam series, and Shorts in every language;
- **TikTok,** for Polish and English, if the owner opens it (D2).

## 6. The phases

The dated version is [`calendar.md`](calendar.md), weeks −3 to +6.

| Phase | When | What happens | The owner's part |
|---|---|---|---|
| **0. Gates** | Now | D1; v1.2.0 uploaded to the closed track (#1312); Search Console (O1) | Check the account; upload; verify the site |
| **1. Test and ask** | Week −3 (only with the testing rule) and week −2 | The closed test with real learners (#1239); the accounts from the kit (#1240); every admin asked once; AlternativeTo suggested; the Bangla guide submitted (#1246) | Open the test track and the Group; claim the handles; message the admins |
| **2. Ready** | Week −1 | The launch kit, reviewed in five languages (#1210); the promo video (#1211); the outreach list re-checked (#1212); the site's badge ready (sogda-website #45); r/German's moderators asked about the wiki | Approve the kit; upload the video, unlisted |
| **3. Launch week** | L to L+6 | L: the testers and the O4 list first, then Sogda's own channels, then each community in its evening. L+1, L+2: the pitches. L+2: Show HN. L+3 to L+7: the creators | About an hour on L, then one sitting a day. Answer every comment as the maker |
| **4. Rhythm** | Weeks 2–6 | The five formats as series (#1241–#1245), on Sogda's own channels; the due-list every Monday (#1207) | Post from the due-list; paste the numbers on Mondays |
| **5. Review** | End of week 6 | [`results.md`](results.md) decides what stays. agent-5 proposes MK3: a custom store listing per audience (`&listing=bn`), a localised listing experiment once there's traffic, and the questions on sponsorships (D3) and a German listing (D7) | Decide MK3 |

## 7. Measuring, every week

- **Every link has a referrer.** The source, medium and campaign scheme is in [`messaging.md`](messaging.md). A link without one is a channel we can't judge.
- **Every Monday, the owner pastes** last week's numbers into the week's issue:
  - Play Console's installs by referrer;
  - new ratings and reviews per language;
  - each post's views and clicks, as each platform shows them to the account holder.
- **agent-5 then:**
  - writes them into `results.md`;
  - compares the channels;
  - moves next week's posts toward what worked. A channel that brings nothing in two weeks loses its slot.
- **Each month,** Search Console, Bing and Yandex (once O1 is done) and the AI-answer panel (sogda-website #65, first in November 2026) show whether search and AI answers have started to name Sogda.
- **What we control, as a checklist:**
  - every launch-kit post is out within a day of L;
  - every pitch on the outreach list goes in week 1;
  - every comment and question is answered within a day;
  - every finding becomes an issue the same day.

## 8. Who does what

| Who | Does |
|---|---|
| **The owner** | Holds every account, posts every post, sends every pitch and email, and answers comments as the maker. Approves each week's posts. Decides everything in §10 |
| **agent-5** | Research, this plan and the calendar, every draft in five languages, every image and video, the weekly due-list, `results.md`, and turning feedback into issues. Never posts, sends or logs in |
| **agent-0** | Checks every fact and the brand, and en and de copy |
| **agent-1, agent-2** | Native reviews: pl and bn (agent-1), ru (agent-2) |
| **agent-4** | The site at launch: the Play badge with its referrer (sogda-website #45), and the pages posts link to |
| **agent-3** | The monthly AI-answer panel (sogda-website #65) |

## 9. Risks, and how the plan avoids them

| Risk | How we avoid it |
|---|---|
| **A community bans us for self-promotion** | Read every rule while logged in before posting. Ask admins first. One post per community, never a follow-up. The owner always says "I make this app" |
| **A new Reddit account is shadow-banned** | No Reddit launch post. Only one disclosed comment in r/languagelearning's resources thread, the place that thread exists for, from an account with some honest history first (§5) |
| **A content error spotted in public** (it happened to a German app on Show HN) | Only real screens from the release build, and every word quoted from the app or `site-facts.json`. A fact check by agent-0 before anything goes out |
| **Russian copy in Ukrainian spaces** | Never assume. Russian copy goes to Russian-language communities. In a Ukrainian or mixed one, the owner asks the admins which language they want (D8) |
| **Guilt by association** with exam leaks, pirated PDFs or discount spam | Those channels are listed as *avoid* in [`channels.md`](channels.md). We never post there or buy ads there |
| **Gaming the testing rule** with tester-swap groups | Real learners only. Google's application asks whether engagement matched real use |
| **A harsh first review** | The owner answers kindly and factually, fixes the cause, and never asks for a better rating |
| **Small numbers hide in "Other"** in Play Console's acquisition report | Judge channels over weeks, not days. Post counts and clicks from the platforms help |
| **The owner's time runs out** | One sitting a day, with posts ready to paste. A channel that brings nothing in two weeks is dropped |
| **A trademark complaint** | Goethe and telc are named only to describe. "Not official Goethe or telc papers", every time |
| **Breaking Play's policy** | No incentive for a review, no "5 stars?", no ranking or price words, no testimonials (Play's Ratings and Metadata policies) |

## 10. What the owner decides

Answer here or on the issue named. Each one has a recommendation.

| # | Question | Recommendation |
|---|---|---|
| **D1** | **Is the Play developer account personal, and was it created after 13 Nov 2023?** (#1239) | **Answered on 2026-10-02: yes.** The closed test comes first, and 1.1.0's first upload goes to the Closed testing track. The steps and the call for testers: [`launch/closed-test.md`](launch/closed-test.md) |
| D2 | Which accounts to open | **A Facebook Page and a YouTube channel first.** Telegram and Discord as a person (for the admins and the rules), with **no Sogda Telegram channel at launch:** a new channel has no readers, and the reach is in the existing chats. **TikTok** for Polish and English once Shorts show the clips work |
| D3 | Pay for anything? Easy German and others take app sponsors | **Not at launch.** Look again after week 2's numbers. Never pay for reviews, ratings or installs |
| D4 | Show HN on L+2, and Product Hunt (only as an app, never a "course") | **Show HN yes**, written as the maker's story. **Product Hunt only if the owner wants a launch day there:** it's a badge, not an install channel |
| D5 | How to answer "is it free?" or "what does it cost?" in comments | The owner's answer. Our copy never says "free" or a price, and r/German's rule turns on "non-free and/or proprietary" |
| D6 | Ask for a Play rating inside the app (#1237) | **Yes, once, after a real milestone**, in the first update after launch |
| D7 | A German (de-DE) Play listing, though the app has no German interface | **Not for the first release.** Play falls back to the English listing. Revisit with the site's German audience |
| D8 | The language for Ukrainian and mixed communities (the app has no Ukrainian) | **Ask the admins.** Russian only where the chat itself writes Russian, otherwise English. A Ukrainian note would need a native reviewer the team doesn't have |

## 11. The work, as issues

Every piece of the plan is an issue in lane M on the board, label `marketing`.

| When | Issue | What |
|---|---|---|
| Done | #1200 | The feature graphics (merged, #1215) |
| This PR | #1201, #1202, #1203, #1204 | Channels, competitors, messaging and the calendar, under this plan |
| **Now (D1: yes)** | **#1239** | **The closed test: the call for testers in five languages, the Group, the feedback log, the production form** |
| Before launch | #1209 → #1205 → #1206 | Templates, then the stills and video tools every series needs |
| Before launch | #1240 | The profile kit for the owner's accounts |
| Done | #1208 | The feature review (of v1.1.0), as a marketer. Every finding becomes an issue (the first: #1237) |
| Before launch | #1207 | Post drafts and the weekly due-list, from the calendar and the facts |
| Week −1 | #1210, #1211, #1212 | The launch kit, the promo video, and the outreach list with sogda-website #76's pitches |
| From launch | #1241, #1242, #1243, #1244, #1245 | The five formats as series: your letters, der/die/das, the mock-exam task, false friends, flight mode |
| Week −2 → 4 | #1246 | The Bangla guide for germanprobashe.com |
| After launch | #1237 | Ask for a rating once, and the "Rate Sogda" row (a product issue, decided by the owner) |
