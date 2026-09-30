## German-specialist sites (researched 2026-09-30: curl, raw HTML, JSON-LD parsed, Playwright for JS pages; WebSearch is US-only)

**Corrections:** deutsch-akademie.de fails TLS; the real site is **deutschakademie.de**. **Lingvano teaches sign languages**, not German.

### Lingoda (lingoda.com/en/german/)
- **H1:** "Learn German online from certified teachers"; CTA "Get Started".
- **Trust:** Trustpilot 4.3 (45 mentions in the HTML), "300k learners", "2.5k teachers". CEFR ×12; **Goethe/telc ×0**.
- **Head:** title "Online German Classes (A1–C1) | Lingoda"; hreflang en/de/fr/es/it/pt-BR/tr + x-default (**no bn/ru/pl**).
- **JSON-LD** (Yoast): WebPage, BreadcrumbList, WebSite, Organization, ImageObject, **FAQPage (7 Q)**.
- **Crawl:** robots has no AI rules; no llms.txt. Sitemaps: 521 pages + a **3,336-post blog** (555 "german" slugs).
- **Content:** 15 city pages, level pages A1–C1, placement test, "german-vs-french" posts.
- **Apps:** footer store badges.

### Seedlang (seedlang.com)
- **The page:** a client-rendered React SPA with a 13 KB shell and **no H1**. "Start Speaking A New Language". Comparison table vs Duolingo/Memrise; no CEFR/Goethe.
- **Head:** no canonical, hreflang, `html lang` or JSON-LD.
- **Crawl:** /sitemap.xml, /llms.txt and /blog are all soft-404 shells.
- **Apps:** one app per language.

### DeutschAkademie (deutschakademie.de/en/online-german-courses-1/)
- **H1:** "Online German course – How would you like to learn German?". "25,000+ online exercises", "800+ hours"; by level A1–C1, topic, textbook. Exam trainer A1–C1; telc model tests; telc ×117 on the homepage.
- **Locales:** 17 languages **incl. ru, pl (no bn)**, but **no hreflang**.
- **JSON-LD:** WebPage, WebSite + SearchAction, BreadcrumbList.
- **Crawl:** sitemap 1,891 URLs (226 under /online-deutschkurs/). robots **blocks anthropic-ai** (and ~25 others) but not GPTBot/ClaudeBot/Google-Extended/PerplexityBot. No llms.txt.
- **Apps:** none.

### Clozemaster (clozemaster.com/languages/expand-german-vocabulary): my slice
- **H1:** "Learn German faster."; "Thousands of fill-in-the-blank sentences… vocabulary in context"; CTA "Start Playing".
- **Positioning:** targets intermediates; an H2 "**What to do after Duolingo German**". Collections: frequency lists 100–50,000+, CEFR A1–B2, grammar, themes.
- **Trust:** 5★ quotes from named store reviewers.
- **SEO:** title "Learn German faster. Play for free. - Clozemaster". **No canonical, hreflang, OG or JSON-LD.**
- **Crawl:** robots **malformed** (`Disallow: /cllp` with no User-agent). sitemap.xml.gz is a 2021 index whose child **404s**, so ~76 language landings are likely in no working sitemap. Blog 454 posts (46 German, e.g. german-definite-articles). No llms.txt.
- **Apps:** store badges top and bottom.

### Der-die-das trainers
- **derdiedas-trainer.de:**
  - **The hero is a playable card** ("Mensch (human)" + der/die/das buttons, an "A1 Goethe" list).
  - JSON-LD **WebApplication** (Offer 0, inLanguage en/de/ru/uk) + BreadcrumbList + **FAQPage (6)**. Full OG, and the only `apple-itunes-app` smart banner.
  - hreflang en/de/ru/uk all → **the same URL** (misconfigured).
  - robots **explicitly allows GPTBot, ChatGPT-User, Google-Extended**.
  - Sitemap 7 URLs (/uebungen, /goethe-a1-artikel, /rules).
- **derdiedas.app:** H1 "Master German Noun Genders", no JSON-LD.
- **derartikel.com:** a 1.6 KB JS shell.

### Search visibility (WebSearch, US): none of these sites, and not Sogda
| Query | Who appears |
|---|---|
| "German article trainer der die das app" | store listings, GitHub, derdiedas-trainer.de, derartikel.com, howtostudygerman.com |
| "learn German vocabulary app spaced repetition" | store listings, lingopie, **vocabeo.com**, vokabular.app, reword.app |
| "German app with Goethe exam practice" | store listings (Prep Goethe, PassDeutsch, "German A1 Exam: Goethe & telc"), goethe.de Deutschtrainer, languavibe.com, deutschmeister.app |
| "learn German A1 to C1 app" | store listings only (Todaii, "…A1-C1 … 100% offline", SprechenAI A1–C2, "Learn German A1-C2 (offline)") |
| "Lingoda alternative" | third-party lists only (talk-easy, linguasteps, g2, saashub, semrush), not even lingoda.com |

**Store listings with the CEFR range in the app name dominate; at least two already claim "offline".**

### Take / beat
1. **A working sample as the hero:** one real word card (article, plural, example, guide, meaning in bn/ru/pl) as static HTML.
2. **bn + proper hreflang:** none of the six has bn; rivals botch hreflang.
3. **Structured data** where most have none: Organization, WebSite, MobileApplication, FAQPage, BreadcrumbList. The gain is entity clarity, not stars (Google's app rich result needs price and ratings).
4. **AI-crawler signals:** no rival has llms.txt; explicit Allow lines + llms.txt would be a niche first.
5. **Course data → crawlable pages**, like DeutschAkademie's 226 exercise pages and Clozemaster's grammar posts. Start small; avoid thin duplicates.
6. **The exam angle on the web:** a "Goethe-style" guide per level (A1–C2) mapping our 3 mocks per step to the exam modules; no affiliation implied.
7. **Lead with "offline, no account":** no competitor's website does.
8. **Trust from specifics, not ratings:** 12 steps, 5,069 words, 182 topics, 3 mocks per step, FSRS, the CEFR map.
9. **A factual comparison page** (features only, no prices): "Lingoda alternative" results are only third-party lists.
10. **Avoid their mistakes:** JS shells, soft 404s, broken sitemaps, malformed robots.
