# The profile kit: Sogda's own channels, ready to set up (#1240)

*agent-5, 2026-10-03. Everything the owner pastes when opening Sogda's own channels: the handle, the name, the bio, the link, and the images. **The owner creates and holds every account; agents never do.** The plan recommends a **Facebook Page** and a **YouTube channel** first (D2 in [`plan.md`](../plan.md)), and the launch kit already posts to both, so this kit covers those two. TikTok follows if the owner opens it.*

*Facts are `{tokens}` from [`site-facts.json`](../../05-dev-guide/site-facts.json). The images are on the `media` branch, `2026-10-03-1240-profiles/`, rendered by `python tools/media/stills.py banner --formats youtube_banner,facebook_cover` from `brand.json`; the avatar is the brand kit's own icon.*

## Before claiming

- **Claim the handles early:** empty and impostor handles exist for bigger apps ([`competitors.md`](../competitors.md)).
- **Read the name rules on each platform's own form:** the forms are the source, and they change.
- **`@sogda` on Telegram is taken** (a channel with one subscriber, seen 2026-10-02), which doesn't matter: the plan uses Telegram only as a person. The other handles below could only be checked logged in; take the first one free.

## Facebook Page (bn first, then en)

| Field | Value |
|---|---|
| **Page name** | Sogda |
| **Username** | `sogda`, else `sogda.app`, else `sogdaapp` |
| **Category** | Education (or the closest app category the form offers) |
| **Intro (bio)** | Sogda: German A1–C2, offline, no account. জার্মান শিখুন বাংলায়: অর্থ বাংলায়, উচ্চারণ বাংলা অক্ষরে। |
| **Website** | https://www.sogda.de/bn |
| **Action button** | the Play link, `<play-link facebook-page/bio>` (`messaging.md`, *The Play link*) |
| **Profile picture** | `docs/sogda-brand-kit/png/play-store-icon-512.png` (512 × 512, the kit's icon; Facebook crops it round) |
| **Cover** | `2026-10-03-1240-profiles/bn-facebook_cover.png` (1640 × 624; the en cut is beside it). Everything sits in the middle, which both the desktop and the phone crop keep. Check the crop on upload |

The Intro's Bangla line is *draft* until agent-1's review.

## YouTube channel (en)

| Field | Value |
|---|---|
| **Channel name** | Sogda |
| **Handle** | `@sogda`, else `@sogdaapp`, else `@sogda.de`. YouTube allows 3–30 letters, numbers, `_`, `-` and `.` ([YouTube](https://support.google.com/youtube/answer/11585688), read 2026-10-02) |
| **Picture** | `docs/sogda-brand-kit/png/play-store-icon-512.png` (YouTube shows it at 98 × 98) |
| **Banner** | `2026-10-03-1240-profiles/en-youtube_banner.png` (2560 × 1440; the lockup and the words sit in YouTube's safe area: 1235 × 338 at the minimum size, [YouTube](https://support.google.com/youtube/answer/10456525), read 2026-10-03) |
| **Links** | sogda.de: https://www.sogda.de/en · Google Play: `<play-link youtube/bio>` |

**Description:**

> Sogda is an offline German course app for Android: A1 to C2 in {totals.steps} steps, with {totals.words} words, {totals.grammar_topics} grammar topics and {totals.mock_exams} mock exams, and meanings and a pronunciation guide in English, Bangla, Russian or Polish, no account needed.
>
> It also reads the German you meet: share or photograph a letter, and Sogda marks its new words by level.
>
> Here: short clips of the real app, a mock-exam task at a time, and how to read German in your own letters. The mock exams are practice, not official Goethe or telc papers.

The videos it starts with:
- the promo video (#1211);
- the documents video (#1236);
- then the series (#1241, #1243).

## TikTok (only if the owner opens it, D2)

| Field | Value |
|---|---|
| **Name** | Sogda |
| **Username** | `sogda`, else `sogda.app` |
| **Bio** | German A1–C2, offline. Meanings in English, Bangla, Russian, Polish. |
| **Link** | `<play-link tiktok/bio>` |
| **Picture** | the kit's icon, as above |

## The person accounts

Telegram, Discord and Reddit are the owner's own: the plan uses them to ask admins and answer questions, as the maker, never as a brand. They need no kit, only the rule every post keeps: "I make Sogda".
