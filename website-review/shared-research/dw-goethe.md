## DW Learn German and the Goethe-Institut (researched 2026-09-30)
Method: curl for DW. goethe.de returns **403** to curl/WebFetch (HEAD gives 200: a firewall), so it was read in headless Chromium (the rendered DOM). WebSearch is a US engine, not Google.

### DW Learn German (learngerman.dw.com): agent-0's slice
- **Home** (/en/learn-german/s-9528):
  - **No H1**; the first H2 is "Learn German free online"; "…mobile courses… A1 to C1".
  - CTA: level tiles (A1/A2, B1/B2, C1/C2, teachers). Nav: Placement Test, Beginners, Fortgeschrittene, Profis, Vocab/Grammar overviews, Vocabulary Trainer, Login.
  - A news-portal feel ("New every day" cards with CEFR badges). Trust = the DW brand; no numbers or testimonials.
  - **19 locales incl. pl, ru; no bn**.
  - Head: `<title>LEARN GERMAN</title>`; og:title "Learn German online for free | A1-C1", but **no og:image**; self-canonical, hreflang + x-default (zh listed twice).
  - **JSON-LD: WebSite only.**
- **Nicos Weg:**
  - Title "Nicos Weg"; **no H1, no JSON-LD** (no Course/VideoObject).
  - **Client-rendered** (the raw HTML says "enable JavaScript").
  - hreflang points each language to its **home page**, not to its Nicos Weg page (wrong).
- **Grammar:** /en/grammar has 184 accordion topics that **load on click and have no URL of their own**, so they can't rank. No meta description or canonical on /grammar and /vocabulary.
- **Placement test:** A1–B1 only; the title is "Placement Test | Placement Test".
- **robots.txt blocks ~50 bots incl. GPTBot, OAI-SearchBot, ChatGPT-User, ClaudeBot, anthropic-ai, Google-Extended, PerplexityBot, CCBot, Applebot-Extended** (Claude-SearchBot not named). The search tool itself was refused.
- **Sitemap:** 76 child sitemaps (19 locales × 4 types); en has 512 lessons. No llms.txt.
- **App:** DW Learn German (Play `com.dw.learngerman`, 1M+, 4.2★; "online and on the go", **no offline claim**). The **site links to neither store.**

### Goethe-Institut (goethe.de): agent-2's slice
- **Pages:**
  - Home H1 "SPRACHE. KULTUR. DEUTSCHLAND." (institutional).
  - /en/spr/ueb.html H1 "PRACTISE GERMAN FOR FREE".
  - /en/spr/prf.html H1 "GERMAN EXAMINATIONS A1–C2" (visa, recognition, university).
- **Trust stats:** 15.5M learners, 1.1M exams in 2025, **461,000 B1 exams in 2025**, 154 branches.
- **Languages:** the central /spr/ and /prf/ are de/en only. /spr/ueb/ has es/fr/ru, but /pl/spr/ueb.html is a 404. The Bangladesh site is de/en; **no Bengali anywhere**.
- **SEO:**
  - Strong titles/descriptions ("Practise German for free - Goethe-Institut"; "Exam training - Goethe-Zertifikat B1 / Free test examples, exercises and word list").
  - gzb1.html has **no meta description**. Self-canonical everywhere; **no hreflang on any page checked**, so country copies (/ins/ke/…) compete with each other.
  - JSON-LD: home = Organization, ContactPoint, WebPage, WebSite; ueb/prf = WebPage, WebSite, BreadcrumbList, VideoObject. **No FAQPage** despite a 7-Q FAQ on prf; no Course/SoftwareApplication. No OG on central pages.
- **Crawl:**
  - robots.txt has no AI rules (it blocks SEO tools + Bytespider), but the **firewall 403s non-browser fetchers**.
  - Sitemap index: 454 children, no /ru/ sitemap. No llms.txt.
- **Content:** free exam trainings A1–C2 (model tests, audio, word lists: the likeliest traffic and link earner), "Test your German", Deutsch für dich (its community is discontinued), 24hdeutsch YouTube.
- **Apps:**
  - The Vocabulary Trainer is **A1–B1 only**, a 7-day trial then a subscription (Play `de.goethe.vokabeltrainer`, 10K+, 4.3★). **Its landing links only to the App Store**, and it has defects: the same placeholder text under 3 features, and alt text with a literal `<span>German</span>`.
  - The Deutschtrainer A1 app is gone (the URL 404s).

### Search visibility (US engine)
| Query | Results | DW / Goethe |
|---|---|---|
| learn German online free course A1 | alison, yourgermanteacher, cursa… | neither linked |
| Goethe B1 exam preparation app | apps with "Goethe" in the name (Goethe Prep, Prep Goethe…), then goethe.de's **paid** B1 prep in 5th | Goethe's free trainings are absent |
| German grammar explanation dative | study.com, preply, Rosetta, fluentu, Wikipedia, lingoda | neither |
| learn German app offline | App Store: "Learn German Language Offline", "**Learn German A1-C2 (offline)**"… | neither |
| best app to learn German A1 to C2 | "Learn German A1-C2 (offline)", Lingzy, SprechenAI, deutschland.de "Eight free apps", listicles | neither |

### Take / beat
1. **"Offline", "A1 to C2" and the meaning languages in the H1, title and description.** Neither giant says offline; small store apps win these queries.
2. **Bengali is open:** DW has 19 locales and Goethe ≤7, and neither has bn.
3. **hreflang done right:** DW maps alternates to home pages; Goethe has none.
4. **Basics they skip:** a real H1 (DW has none), specific titles, og:image per locale.
5. **Structured data** (MobileApplication without offers/ratings, Organization, BreadcrumbList, FAQPage as machine context).
6. **Be readable by AI:** DW blocks every AI crawler and Goethe 403s fetchers. Static HTML + allowed bots is an advantage by default.
7. **Static, indexable content:** DW's 184 grammar topics have no URLs, so a few server-rendered grammar pages could win where only blogs rank.
8. **The exam angle without borrowing the brand:** B1 is huge (461k Goethe B1 exams in 2025). Describe our mocks in exam-module terms (Lesen, Hören, Schreiben, Sprechen) and link to Goethe's official free trainings; no affiliation implied.
9. **A store link in every locale's first screen:** DW never links its app; Goethe's app page links only the App Store.
10. **Trust without numbers:** 5,069 words, 182 topics, 12 steps, 3 mocks per step, screenshots or a short video, no account.
