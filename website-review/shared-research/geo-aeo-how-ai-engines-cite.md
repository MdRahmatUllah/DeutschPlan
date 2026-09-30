## GEO/AEO: how the AI engines pick and cite sources (researched 2026-09-30; primary sources where possible)

### Engine by engine
| Engine | robots.txt tokens | Index it draws on | What we control |
|---|---|---|---|
| Google AI Overviews / AI Mode | `Googlebot` only (no AI token) | Google's index + query fan-out | Search controls (`noindex`, `nosnippet`, `max-snippet`). "No special schema.org structured data" needed ([Google AI features](https://developers.google.com/search/docs/appearance/ai-features)). The AI optimization guide (May 2026) says AI text files are ignored ([guide](https://developers.google.com/search/docs/fundamentals/ai-optimization-guide)). GSC has a Generative AI performance report (June 2026). |
| Gemini app | Googlebot crawls; `Google-Extended` decides use | Google's index (grounding) | `Google-Extended` controls Gemini **training + grounding**, not Search/AIO ([Google crawlers](https://developers.google.com/search/docs/crawling-indexing/google-common-crawlers)) |
| ChatGPT search | `OAI-SearchBot` (search), `GPTBot` (training), `ChatGPT-User` (user fetches) | Its own crawl + third-party providers (Bing for Enterprise/Edu, [OpenAI help](https://help.openai.com/en/articles/10093903-chatgpt-search-for-enterprise-and-edu)); 87% of citations matched Bing's top results ([Seer, 2025, ~100 queries, directional](https://www.seerinteractive.com/insights/87-percent-of-searchgpt-citations-match-bings-top-results)) | Opting out of OAI-SearchBot = not shown in ChatGPT search; GPTBot = training only ([OpenAI bots](https://developers.openai.com/api/docs/bots)) |
| Claude | `ClaudeBot` (training), `Claude-SearchBot` (search), `Claude-User` (user fetches) | Not documented; Brave is likely ([TechCrunch 2025-03-21](https://techcrunch.com/2025/03/21/anthropic-appears-to-be-using-brave-to-power-web-searches-for-its-claude-chatbot/)). **Uncertain.** | Each bot separately ([Anthropic](https://support.claude.com/en/articles/8896518-does-anthropic-crawl-data-from-the-web-and-how-can-site-owners-block-the-crawler)). Brave follows Googlebot rules, has no webmaster console ([Brave](https://search.brave.com/help/brave-search-crawler)). |
| Perplexity | `PerplexityBot` (index), `Perplexity-User` (fetches) | Its own index | Blocking PerplexityBot = out of its results ([docs](https://docs.perplexity.ai/guides/bots)) |
| Copilot / Bing | `Bingbot` | Bing (which also feeds ChatGPT) | Bing Webmaster Tools **AI Performance** report (preview since Feb 2026, [Bing](https://blogs.bing.com/webmaster/February-2026/Introducing-AI-Performance-in-Bing-Webmaster-Tools-Public-Preview)); **IndexNow** reaches Bing, Yandex, Naver, Seznam, Yep and Amazon, not Google ([IndexNow](https://www.indexnow.org/faq)) |

### Citation factors, by likely impact for a small new site
1. **Being indexed in Google, Bing, Brave and Perplexity.** The overlap is low: only 12% of URLs cited by ChatGPT/Gemini/Copilot rank in Google's top 10 ([Ahrefs](https://ahrefs.com/blog/ai-search-overlap/)); only 38% of AIO citations rank in the top 10 (down from 76%, [Ahrefs Mar 2026](https://ahrefs.com/blog/ai-overview-citations-top-10/)).
2. **Third-party mentions.** YouTube mentions correlate about 0.737 with AI visibility; branded web mentions 0.66–0.71; Domain Rating only 0.27–0.33 (75k brands, [Ahrefs Dec 2025](https://ahrefs.com/blog/ai-brand-visibility-correlations/); correlations, not proof). **"Best X" lists = 43.8% of ChatGPT's cited pages for recommendation prompts**; third-party lists far outperform self-promotional ones ([Ahrefs](https://ahrefs.com/blog/best-lists-research/)).
3. **Uncontested long tails.** "German for Bangla speakers" returns small store apps and AI-written Talkpal pages, so a small site can win it long before "best German app".
4. **Extractable, sourced facts.** In the GEO paper ([arXiv 2311.09735](https://arxiv.org/abs/2311.09735), KDD 2024), Cite Sources / Quotations / Statistics gave +30–40% relative visibility; lower-ranked pages gained most; keyword stuffing gave no gain. It's a synthetic 2023-era benchmark.
5. **A live Play listing.** Store pages fill the results for app-intent queries.
6. **Hygiene:** hreflang, crawlability, CWV, E-E-A-T. Necessary, but they don't set you apart.
7. **Structured data:** entity clarity; JSON-LD on 1,885 pages gave "no major uplift" in citations ([Ahrefs June 2026](https://ahrefs.com/blog/schema-ai-citations/)).
8. **llms.txt:** about zero effect.

Who gets cited: ChatGPT cites Wikipedia most (7.8%); AIO and Perplexity lean on Reddit and YouTube ([Profound, 680M citations](https://www.tryprofound.com/blog/ai-platform-citation-patterns)); YouTube is now the most-cited domain in AIO (Ahrefs Mar 2026).

**Reality check** (WebSearch, US, a proxy):
- "best app to learn German offline" → listicles (mezzoguild, alllanguageresources, lingoni, deutschwunder, kylian.ai, learngermanonline.org, colanguage) + an App Store page.
- "German learning app for Bangla speakers" → store listings (DigBazar, Adian Sir) + 4 Talkpal pages.
- "Goethe exam preparation app A1 to C2" → store listings, goethe.de trainings, small test-prep sites.
- "Duolingo alternative German" → competitors' blogs (Clozemaster, Praktika, LingoLegend) + AlternativeTo + MetaFilter.

### Checklist for sogda.de
- **robots.txt:**
  - Keep `*` Allow + Sitemap; drop the legacy `Host:`.
  - Don't add named bot groups unless blocking: a named group ignores the `*` rules.
  - Owner call: keep the training bots allowed (helps models "know" the brand; uncertain).
- **Structured data:**
  - Keep MobileApplication. **No app rich result is possible** without price + ratings (forbidden here), so aim for entity clarity: Organization (logo, `sameAs`: Play, YouTube, later Wikidata), WebSite, `publisher`/`@id` links, `installUrl` to Play once live, BreadcrumbList on hubs.
  - Course *info* was retired in June 2025; Course *list* needs ≥3 courses + a provider (uncertain fit).
  - **FAQPage no longer displays anywhere** (FAQ rich results dropped 2026-05-07, [SEJ](https://www.searchenginejournal.com/google-drops-faq-rich-results-from-search/574429/)); keep the visible Q&A.
  - HowTo is deprecated.
- **llms.txt:** optional, low priority. A proposal, not a standard ([llmstxt.org](https://llmstxt.org/)). Its only confirmed consumer is Lighthouse's "Agentic Browsing" audit. A 10-minute file, not a lever.
- **Content hubs** (the main lever), in 5 languages with hreflang:
  1. "German for Bangla speakers";
  2. one page per CEFR level (can-dos + topics, citing the Goethe descriptors);
  3. a grammar reference with bn/ru/pl meanings;
  4. themed vocabulary per level (each page must add value: Google's scaled-content-abuse policy);
  5. exam-format guides (Goethe, telc, ÖSD, cited);
  6. offline and FSRS explainers with statistics and sources;
  7. About/methodology with named authors.
- **Off-site:**
  - Publish and localize the Play listing in 5 languages, with Android App Links (`assetlinks.json`).
  - A YouTube channel with demos in bn/en/de.
  - Pitch the listicle authors above; AlternativeTo.
  - Genuine, disclosed participation in r/German and r/languagelearning.
  - Wikidata only after independent sources exist; Wikipedia isn't realistic yet.
- **Tools** (no analytics on the site):
  - Verify the site in GSC and BWT (import from GSC) and submit sitemaps.
  - IndexNow: a key file at the root, pinged on each Vercel deploy.
  - Watch GSC's Generative AI report and BWT's AI Performance report.

### Myths
- **llms.txt gets you cited:** Google ignores it; 97% of ~38k llms.txt files got zero fetches ([Ahrefs](https://ahrefs.com/blog/llmstxt-study/)); no correlation across ~300k domains ([SE Ranking](https://seranking.com/blog/llms-txt/)).
- **Special AI schema, or chunking content for AI:** both are myths per Google, and there was no uplift in Ahrefs' test.
- **Blocking GPTBot hides you from ChatGPT search:** search inclusion is OAI-SearchBot; GPTBot is training only.
- **Google-Extended controls AI Overviews:** it doesn't; AIO runs on Googlebot.
- **Ranking #1 on Google means ChatGPT and Claude cite you:** they use different indexes.
- **Planting mentions or self-listicles works:** Google warns against "inauthentic mentions".
- **Keyword stuffing works for GEO:** it gave no gain in the GEO paper.
- **AI-visibility scores are objective:** they depend on the chosen prompts.
