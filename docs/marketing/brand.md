# Brand templates: frames, type, colours and safe areas

Every still and video should look like Sogda without being designed again
each time (#1209). This page explains the values. **The values themselves live
in one place, [`brand.json`](brand.json).** The media tools read them through
`tools/media/brand.py` (`colour`, `size`, `safe_box`, `contrast`), so a tool
never types a colour, a size or a margin. `tools/tests/test_brand.py` checks
that `brand.json`:
- matches the brand kit and the app;
- computes every pair's contrast rather than trusting a number typed here;
- says what this page says.

The rulebook stays [`docs/sogda-brand-kit/README.md`](../sogda-brand-kit/README.md):
- the mark, never recoloured, stretched or given a gradient;
- clear space of the Ä's dots' height on every side;
- **Sogda**, one word with a capital S.

## Colours

| Name | Hex | From |
|---|---|---|
| Lagoon | #00C2B2 | the kit: ground |
| Sun | #FFC61A | the kit: front tile |
| Ink | #15121F | the kit: outline, text |
| Paper | #FFF8EE | the kit: light background |
| Night | #13111D | the kit: dark background |
| Cobalt | #3D5AFE | the app: *der* |
| Raspberry | #FF3D7F | the app: *die* |
| Emerald | #00B86B | the app: *das* |

The gender colours are there because the app's screens show them: a still
built around a screenshot can pick them up.

### Text on a colour
`pairs` in `brand.json` lists every pair a template may use. Each passes WCAG 2's
contrast for its use:
- **Body text** (4.5:1 or more):
  - Ink on Lagoon, Sun, Paper, Raspberry or Emerald;
  - Paper on Ink, Night or Cobalt;
  - Lagoon, Sun or Emerald on Night.
- **Large text only** (3:1 or more; 24 px and up, or 19 px bold): Ink or Sun on Cobalt.
- **Never** (`never`, under 3:1): Paper or Sun on Lagoon, Sun or Lagoon on Paper.
  - The brand's two loudest colours don't carry text on each other. Lagoon behind Ink does.

## Type
- **Inter** for Latin and Cyrillic (en, de, pl, ru), and **Noto Sans Bengali** for bn. These are the app's own fonts, from `app/assets/fonts/`, under SIL OFL 1.1.
- **Weights:** headline 800 (the wordmark's ExtraBold), title 600, body and caption 500.
- **Tracking:** −2 % on headlines, as the wordmark, and −1 % on titles.
- **Line height:** 1.2 for Latin and Cyrillic, and 1.5 for Bangla, whose vowel signs need the room.
- **Sizes:** in pixels, by format, in `brand.json`'s `type.sizes`: a headline, a body and a caption size for each format, and the feature graphic's title. The vertical format runs largest, since it's read on a phone at arm's length.

A caption is never under 32 px on a 1080 px-wide image, so it can be read on a phone held at arm's length.

## The frame: the app's Paper & Ink look
- **Fills and lines:** solid colour fills with Ink outlines (3 px), and a hard Ink shadow offset 6 px down and right. No blur, no gradients.
- **Corners:** cards and screenshots get a 24 px radius.
- **The logo** is the kit's horizontal tiles lockup:
  - the light one on Paper or Lagoon, where it sits as a Paper card (as on the feature graphic), and the dark one on Night;
  - 40 % of the safe area's width, at the safe area's top left;
  - on the feature graphic, centred.
- **On a photo,** the mark sits on its Lagoon square, as the kit says.
- **Screenshots** come only from the app on `emulator-5558` or the Play sets in `docs/05-dev-guide/store/`, framed in the 24 px radius with the hard shadow. Never an AI-made person and never a real name (`developer-agents/agent-5/README.md`).

## Formats and their safe areas
Text and the logo stay inside the safe area. The background, and a screenshot's edge, may run to the image's edge. The fractions are in `brand.json`, and `safe_box(format)` turns them into pixels.

| Format | Size | For | Kept clear (top, right, bottom, left) | Source |
|---|---|---|---|---|
| Feature graphic | 1024 × 500 | Play's listing (RGB, no alpha) | 10 %, 15 %, 10 %, 15 % | Ours: Play shows its cutoff zones only as a picture, with no numbers ([Play Console Help](https://support.google.com/googleplay/android-developer/answer/9866151), read 2026-10-03) |
| Square | 1080 × 1080 | feed posts | 6 % all round | Ours: a feed shows the whole image |
| Portrait | 1080 × 1350 | feed posts, the tallest a feed shows whole | 6 % all round | Ours |
| Vertical | 1080 × 1920 | Reels, Stories, TikTok, Shorts | 14 %, 6 %, 35 %, 6 % | [Meta's Reels guide](https://www.facebook.com/business/ads-guide/update/image/instagram-reels): "leave roughly 14 % of the top, 35 % of the bottom and 6 % of each side free" of text and logos, read 2026-10-03. TikTok's own safe-zone article no longer exists, so the same zone serves TikTok and Shorts |
| Landscape | 1920 × 1080 | YouTube, the website, slides | 6 % all round | Ours |
| YouTube banner | 2560 × 1440 | the channel's banner (#1240) | 35.3 % top and bottom, 19.8 % sides | [YouTube](https://support.google.com/youtube/answer/10456525): minimum 2048 × 1152, recommended 2560 × 1440, text and logos inside 1235 × 338 at the minimum (so 1544 × 423 at 2560), read 2026-10-03 |
| Facebook cover | 1640 × 624 | the Page's cover (#1240) | 20 % top and bottom, 25 % sides | Ours: [Meta's page](https://www.facebook.com/help/125379114252045) needs scripts to read, so everything sits in the middle, which both crops keep. The owner checks the crop on upload |

### Play's feature graphic, from Play's page (read 2026-10-03)
- **Size and format:** 1024 × 500, JPEG or 24-bit PNG (no alpha).
- **Placement:** keep the focal point toward the centre. The logo, the app's name, the slogan and the main UI stay out of the cutoff zones.
- **Background:** not pure white or dark grey, which blend into Play's background. Lagoon doesn't.
- **Branding:** avoid "prominent branding that is similar to your app icon". The first graphic (#1200) centred the tiles lockup, the icon's own mark. Since #1375 (#1323), it shows the wordmark, the title and the listing's own card, and no tiles.

## What a template never says
These are the owner's rules (`developer-agents/agent-5/README.md`):
- **Numbers:** only from `docs/05-dev-guide/site-facts.json`, and the listing's words only from `store-listing.md`, both read by the tool.
- **Never claimed:** a price, "free", "no ads", a rating or a user count.
- **Goethe and telc** are named only to describe: the mock exams are not official papers.
