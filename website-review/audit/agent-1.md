# sogda.de audit: agent-1 (2026-09-30)

Measured on the live site (www.sogda.de, `dev` = `main` at ef281e7 + 1). Tools:
- `curl` on the raw HTML and headers;
- Playwright (Chromium) at 390 × 844 and 1440 × 900, scrolling a screen at a time as a visitor does;
- web search for the index and the brand results.

Severity: **P0** blocks the goal, **P1** a big lever, **P2** worth doing, **P3** polish.

## The verdict in five lines
1. The page itself is good: clear, fast, accessible, beautifully illustrated, genuinely localized in 5 languages, with exemplary security headers.
2. But **no search engine or AI can find it yet**: `site:sogda.de` returns nothing.
3. The brand's results show our **public GitHub repo** and the ancient **Sogdia** instead.
4. There are only **5 content URLs**, one landing page per language, so there's almost nothing for long-tail queries or AI answers to cite.
5. Every call to action is **"Coming soon"**, so a convinced visitor has nothing to do.

## A. Discoverability (the goal: first in Google and in AI answers)
| # | Finding | Evidence | Sev |
|---|---|---|---|
| A1 | **Not indexed.** | Web search `site:sogda.de` → 0 results (2026-09-30). "Sogda learn German app offline A1 to C2" → 10 other "Learn German A1–C2 offline" apps; Sogda absent. | P0 |
| A2 | **The brand results belong to others.** "sogda German" → github.com/MdRahmatUllah/sogda-website and its issues/PRs (#9, #34, #36, #40, #43) rank; the site doesn't. Plain "Sogda" → Sogdia, Sogdian language, Sogdiana (singer). The name is ambiguous, so the entity must be built on purpose. | web search, 2026-09-30 | P0 |
| A3 | **5 content URLs in all.** The sitemap has 15 URLs: `/en /de /pl /ru /bn` + impressum ×5 + datenschutz ×5. There's nothing for "Goethe B1 vocabulary", "der die das rules", "German for Bangla speakers" etc. to land on. | `sitemap.xml` | P0 |
| A4 | **No `llms.txt`** (404). robots.txt allows all crawlers, AI ones included (good). It carries an obsolete `Host:` line (Yandex-only). | `/robots.txt`, `/llms.txt` | P2 |
| A5 | **The sitemap's hreflang has no `x-default`.** The pages have it. | `sitemap.xml` vs `<head>` | P3 |
| A6 | **Root `/`:** a 200 page with `<title>Sogda</title>`, no description or canonical, **relative** hreflang (`href="/en"`; Google wants absolute URLs), and a meta-refresh plus JS redirect to the visitor's language. It works for people; for crawlers it's a thin duplicate. | `curl /` | P2 |

## B. On-page SEO
| # | Finding | Evidence | Sev |
|---|---|---|---|
| B1 | **The H1 is a slogan with no search terms:** "Learn German, one clear day at a time." (and its translations). "App", "offline", "A1–C2", "Goethe" and "course" live only in the subtitle and `<title>`. | h1 per locale | P1 |
| B2 | **The titles miss "app" and "exam/Goethe"**, the words people type. For example, en "Sogda — Learn German offline, A1 to C2" (38 chars) has room: "Sogda: offline German course app, A1 to C2 · Goethe & telc practice". The same holds for de/pl/ru/bn in their own phrasing. | `<title>` ×5 | P1 |
| B3 | **The structured data is one thin `MobileApplication`** (name, OS, category, description, inLanguage, url, image). **Missing:** `Organization` (logo, email, `sameAs`), `WebSite`, `FAQPage` for the 5 visible Q&As, and, on the app, `screenshot`, `featureList`, `softwareVersion`, `availableOnDevice`/"Android 8.0+", `publisher`, `audience`/`educationalLevel` (CEFR A1–C2), and `installUrl`/`downloadUrl` once on Play. | JSON-LD on /en | P1 |
| B4 | **About 860 visible words**, and a **5-question FAQ**. That's fine for a landing page, but thin for answer engines, which quote Q&A-shaped, fact-dense text. | parsed body | P1 |
| B5 | **Headings, alt text and landmarks are exemplary:** one H1, H2 per section, 53/53 images with meaningful, localized alt text, skip link, `lang` per page. Keep them. | parsed body | ✓ |
| B6 | **The localization is real, not machine-flat.** Titles and descriptions are rewritten per market (pl/ru lead with their own meanings, bn with Bangla), each page carries canonical + absolute hreflang + `x-default`, and `og:locale` is set. | head ×5 | ✓ |

## C. Conversion and UX (would a visitor want it at a glance?)
| # | Finding | Evidence | Sev |
|---|---|---|---|
| C1 | **Every CTA is dead:** hero "Coming soon to Google Play" / "Coming soon on iPhone", the nav's "Get the app", and the final CTA. They are **styled as buttons**, so people tap and nothing happens. Fix: once the Play listing exists, a Play **pre-registration** (or open-testing) link gives a real store URL now, a Play entity for search, and a launch-day install base (the owner's call, #45). | 390 and 1440 screenshots | P0 |
| C2 | **The screenshots are English on every locale.** The Bangla page's phone says "Revise · 10 / Day 34 of your course"; ru and pl likewise. The app has bn/pl/ru goldens (`study_back_ru`, `today_pl`, …) and the Play store now has pl/ru phone sets (`docs/05-dev-guide/store/`). Showing a Bangla learner the app in Bangla with Bangla meanings is the strongest "made for me" signal we have. | `content/screenshots.json` has themes, no locales | P1 |
| C3 | **The hero phone greets "Guten Morgen, Maruf"**, a real first name, on every locale. Use a neutral sample persona, or none. | hero, all locales | P2 |
| C4 | **The hero image** (the LCP element, `today-light-360.avif`) shows a **blur-up placeholder** until about 1.6 s on a fast line; on 3G/4G in Dhaka it's much longer. Preload it with `fetchpriority="high"`. The second phone is `loading="lazy"` inside the first viewport. | Playwright LCP 1628 ms at 390 px | P2 |
| C5 | **The contact address is a personal Gmail** (`mdrahmatullahde@gmail.com`). Use hello@sogda.de (or similar) for trust and E-E-A-T. | footer `mailto:` | P2 |
| C6 | **No "who makes this / how the course was built" page:** no About, methodology (FSRS, CEFR alignment, how the 5,069 words and 182 topics were chosen and checked), changelog or press kit. Answer engines and journalists both look for these. | sitemap | P1 |
| C7 | **The page is long:** about 15 screens on a phone, with the value repeated well, but no persistent CTA while scrolling. It matters once C1 has a real link. | scroll run, 390 px | P3 |
| C8 | **The feel is strong:** the Lagoon/Sun palette, the A1→C2 dotted road, the numbered "How it works" story with real screens, the theme switch demo and the counter animation (the raw HTML still says "5,069", so crawlers read the real number). | scroll run | ✓ |

## D. Technical
| # | Finding | Evidence | Sev |
|---|---|---|---|
| D1 | **The security headers are exemplary:** CSP, HSTS preload (2 y), `X-Frame-Options: DENY`, nosniff, a strict Referrer-Policy and Permissions-Policy. | `curl -D -` | ✓ |
| D2 | **Static assets aren't cached long-term.** `/screens/*.avif|webp` and `/og/*.png` use `Cache-Control: public, max-age=0, must-revalidate`, so every repeat visit revalidates about 50 images. Give them `max-age=31536000, immutable` (rename on change). | headers | P2 |
| D3 | **The HTML is 150 KB** (inline SVG art, e.g. the umlaut glyph paths). That's fine at 98–100 Lighthouse, but trim it if art grows. | `curl` size | P3 |
| D4 | **Unknowns to confirm with agent-4:** is the site verified in **Google Search Console** and **Bing Webmaster Tools** (Bing's index feeds ChatGPT/Copilot)? Are sitemaps submitted? Is **IndexNow** wired on deploy? | – | P0 |

## E. Off-site (what AI engines actually cite)
| # | Finding | Sev |
|---|---|---|
| E1 | **Zero third-party mentions:** no Play listing yet, and no directory, review listicle, Reddit or YouTube mention. The only mentions are our own GitHub. AI answers quote third parties ("best apps to learn German" lists, Reddit threads, store pages) far more than a brand's own homepage. | P0 |
| E2 | **The public website repo is indexed.** It ranks for the brand, and exposes internal issues and discussion. The owner may want it private (the site doesn't need a public repo), or at least its README should point to sogda.de. | P1 |

## What only Sogda can say (the angle for everything above)
- **The only complete A1–C2 German course with Bangla meanings and Bangla-letter pronunciation.** Few rivals serve Bangla speakers at all; full Russian/Polish A1–C2 courses are rare too. This is our "blue ocean" for search and for AI answers ("German course for Bangla speakers").
- **Fully offline, no account.** That's rare, and it's concrete for commuters and for markets with costly data.
- **Built around the exams:** three mock exams per step, from A1 to C2.

All three are BRIEF §4 facts, so no new claims are needed.

## My quick-win list (for the discussion)
1. Search Console + Bing Webmaster + sitemap submission + IndexNow (D4, A1).
2. A Play pre-registration link replacing the "Coming soon" buttons (C1; the owner decides).
3. Keyword-bearing H1 subtitle and titles per locale (B1, B2).
4. Rich JSON-LD: Organization + WebSite + MobileApplication + FAQPage (B3).
5. Localized screenshots per locale (C2), and no real name in the hero (C3).
6. A domain email (C5); absolute hreflang on `/` and `x-default` in the sitemap (A5, A6); immutable caching (D2).
