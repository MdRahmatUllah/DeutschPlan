# The content calendar: weeks −3 to +6 around launch (#1204)

*agent-5, 2026-10-02. What goes out, where, in which language, when, and what it needs. The owner posts and sends everything. agent-5 drafts each week's posts (#1207) and sends the owner a due-list every Monday. The channels and their hours come from [`channels.md`](channels.md); the messages from [`messaging.md`](messaging.md); the formats from [`competitors.md`](competitors.md).*

## The days

- **Live:** the day Play shows the production listing. It comes when Google's review finishes, and the owner can't schedule it: managed publishing, which holds changes back until the owner publishes them, doesn't apply to an app's first release ("You can't use it when publishing an app for the first time", https://support.google.com/googleplay/android-developer/answer/9859654, read 2026-10-02).
- **L, launch day:** **the first Tuesday or Wednesday after Live**, once the owner has opened the listing on a phone and checked it in every language. Tuesday and Wednesday are the best days in Sprout Social's Facebook data, and they avoid Bangladesh's weekend, which is Friday and Saturday (sources in [`channels.md`](channels.md)). A listing that sits live and unannounced for a day or two loses nothing.
- **Week −3 happens only if Play's testing rule applies** (§2 of [`plan.md`](plan.md), #1239). Then Production opens at the earliest 14 days after the 12th tester opts in, plus up to about 7 days of review.

## The clock

| Audience | Zone | Window for posts (local) | In UTC | In Germany |
|---|---|---|---|---|
| Bangla, in Bangladesh | UTC+6, no DST | 20:00–23:00, not Friday | 14:00–17:00 | 16:00–19:00 CEST; 15:00–18:00 CET from 25 Oct |
| Bangla, in Germany | CEST, then CET | evening, after work or class | — | the same post as above reaches them at 16:00–19:00 |
| English (Reddit, Discord) | mixed | US morning | 13:00–15:00 | afternoon |
| YouTube (any language) | the viewers' | long-form 14:00–16:00 Wed–Fri; Shorts 12:00–14:00 or 18:00–19:00 Thu–Sat | — | — |
<!-- research:clock-ru-pl-de -->

Publish time matters less on YouTube, which says it "is not known to impact a video's long-term performance". Facebook and Telegram are where the hour counts. **Germany leaves summer time on 25 October 2026**, so every German time moves an hour against Bangladesh and Moscow from that day.

## The rows

The status of each row is one of:
- **idea:** in this plan;
- **drafted:** in `posts/<yyyy-ww>.md` (#1207);
- **ready:** reviewed, with the asset rendered;
- **posted:** the owner posted it, with the link on the week's issue.

Every asset row names its issue in lane M.

### Week −3 (L−21 … L−15), only if the testing rule applies

| Day | Time (local) | Channel | Lang | What | Asset | Status |
|---|---|---|---|---|---|---|
| T0 | — | Play Console | — | The owner opens the closed track and the Google Group, and sets the feedback address | #1239 | idea |
| T0 | — | Email | en, bn, pl, ru | The owner writes to everyone who asked sogda.de to be told (O4's mailto): "test it first?" | #1239 | idea |
| T0 | bn 20:30 | BDSAG / BSAAG, after the admins' OK | bn | The call for testers, if the admins allow it, as their rules require | #1239 | idea |
<!-- research:week-3 -->
| T0+1 … | — | Feedback log | — | agent-5 logs every report and files the findings as issues; agent-0 triages | #1239 | idea |

### Week −2 (L−14 … L−8): the accounts and the asks

| Day | Time | Channel | Lang | What | Asset | Status |
|---|---|---|---|---|---|---|
| L−14 | — | Facebook, YouTube, TikTok, Telegram, Discord | — | The owner claims the handles and sets up the profiles from the kit (only the channels chosen in §5 of [`plan.md`](plan.md)) | #1240 | idea |
| L−14 | — | AlternativeTo | en | The owner suggests Sogda with the website, as an alternative to Duolingo, Anki and Babbel. Its backlog runs "at least a few months", so it goes in before the Play link | — | idea |
| L−13 | — | BDSAG, BSAAG admins (Messenger) | bn | The owner asks the admins of each group for one approved launch post, as the maker | #1210 | idea |
| L−12 | — | germanprobashe.com | bn | The owner submits the Bangla guide through the contributor route | #1246 | idea |
| L−10 | — | Discord (German Learning and Discussion) | en | The owner reads the server's rules, logged in, and notes whether a launch post is allowed and where | — | idea |
<!-- research:week-2 -->

### Week −1 (L−7 … L−1): everything ready

| Day | Time | Channel | Lang | What | Asset | Status |
|---|---|---|---|---|---|---|
| L−7 | — | — | all | The launch kit is reviewed: every post, image and video, with `<play-link>` waiting | #1210 | idea |
| L−7 | — | — | en + subtitles | The promo video is ready for YouTube, unlisted, ads off | #1211 | idea |
| L−5 | — | — | all | The outreach list is re-checked: each roundup still live, with its contact route | #1212 | idea |
| L−3 | — | sogda.de | — | agent-4 has the Play badge with the site's referrer ready to switch on | sogda-website #45 | idea |
| L−2 | — | r/German modmail | en | The owner asks the moderators whether Sogda can go on the wiki's Apps page. A launch post isn't allowed: rule 3 bans proprietary apps | #1210 | idea |
<!-- research:week-1 -->

### Launch week (L … L+6)

| Day | Time (local) | Channel | Lang | What | Asset | Status |
|---|---|---|---|---|---|---|
| L | morning (DE) | Play Console, sogda.de | — | `<play-link>` goes into the kit; agent-4 switches the badge on (#45); the promo video's link goes into the listing | #1210, #1211 | idea |
| L | morning (DE) | Email | all | The owner thanks the testers and everyone on the O4 list, with the link. Asking for an honest review is fine; offering anything for one, or asking for five stars, isn't (Play policy) | #1210 | idea |
| L | 16:00 DE | Facebook Page, YouTube | bn, en | The launch post on Sogda's own channels, with the flight-mode clip | #1210, #1245 | idea |
| L | bn 20:30 | BDSAG, BSAAG (approved post) | bn | The launch post as the admins allowed it: "I make this app", the Bangla promise, the page and the link | #1210 | idea |
| L | 14:00 UTC | Discord, only if its rules allow | en | One post in the right channel | #1210 | idea |
<!-- research:launch-day -->
| L+1 | — | Email | en, de | Pitches to the roundups, one per site, from the owner's address | #1212 | idea |
| L+2 | — | Email | pl, ru, bn | Pitches to the roundups, one per site | #1212 | idea |
| L+1 | — | AlternativeTo | en | The owner adds the Play link to the listing | — | idea |
| L+2 | US weekday morning | Show HN | en | "Show HN: an offline German course for Android, A1 to C2, no account". The maker tells why they built it, and answers every comment. The owner decides; HN gives no best hour | #1210 | idea |
| L+3 | bn 20:30 | Facebook Page | bn | Format 1, the first featured word: *Anmeldung* in Bangla letters | #1241 | idea |
| L+4 | — | Every channel | — | The owner answers every comment from the week; agent-5 files each question or bug as an issue | — | idea |
| L+6 | — | `results.md` | — | Week 1's numbers, pasted by the owner and written up by agent-5: the baseline for weeks 2–6 | — | idea |

### Weeks 2 to 6: the rhythm

Each week has the same shape, so the owner's time stays at about one sitting a day. Every Monday the due-list arrives (#1207), and the owner pastes last week's numbers.

| Weekday | bn | ru | pl | en | Exam (YouTube) |
|---|---|---|---|---|---|
| Tue | Format 1 (a featured word), Facebook Page + Shorts, 20:30 | *channels research* | *channels research* | — | — |
| Wed | — | *channels research* | *channels research* | Format 2 (der, die or das?), TikTok and Shorts | Format 3, one task a week (A1 listening, A1 writing, A2 …), 14:00–16:00 |
| Thu | Format 2 or 4, Facebook Page, 20:30 | *channels research* | *channels research* | — | — |
| Sat | — | — | — | Format 4 or 5, TikTok and Shorts | — |
| Daily | The owner answers comments, as the maker | | | | |

**The series:**
- **Format 1** (#1241) goes through the twelve featured words, one a week.
- **Format 2** (#1242) posts the answer the day after the question.
- **Format 3** (#1243) builds a YouTube playlist that grows for months.
- **Formats 4 and 5** (#1244, #1245) fill the remaining slots.

**What can't be dated in advance:**
- **Week 4:** the Bangla guide, if germanprobashe.com publishes it (#1246); the owner shares it in BSAAG, as its rule 8 invites.
- **Week 6:** the review. `results.md` decides which channels keep their slots, and agent-5 proposes MK3.
- **Any week:** a real learner's question in the comments gets a video reply (Busuu's best post was one). It's never staged.
