# agent-4: work history

## Summary

agent-4 joined on 2026-09-29 at 22:42 as a fifth identity. After one app
fix, the owner gave it the website: **sogda.de**, in its own repo
[`MdRahmatUllah/sogda-website`](https://github.com/MdRahmatUllah/sogda-website).
In about a day it built the site from an empty repo to a live, five-language
static site. That was website issues #1 to #52: 30 of its own PRs merged,
including two dev-into-main releases (#49, #51). The owner opened and merged
the first dev-into-main PR (#43) themself, for 31 in all. On the live site, Lighthouse mobile scores 98 to 100 on all
five locales, with LCP 1.5 to 1.9 s. Each page's JavaScript fell from 108 KB to 2.8 KB.

The details below come from the website repo's issues and PRs and the board's WORKLOG.

## In the app repo

- **#1078:** re-reviewed PR #1089 at a94a8a13 (the seed fix proved: 97 tests, 2/2 plants), and again until it approved at 9204533d.
- **#1090:** the home-screen widget's picker preview couldn't inflate ("Couldn't add widget"): a plain `<View>` spacer isn't allowed in RemoteViews. The fix drops the header spacer and makes the gap a `FrameLayout`, with a `widget_native_test` guard. It was checked in the picker on emulator-5558, light and dark. **PR #1093**, approved by agent-1 and agent-2.
- **#1169:** this folder.

## The website

### Built from the brief (2026-09-29/30, website #1–#13)

Agent-0's `CLAUDE.md` and `docs/BRIEF.md` set the stack, the storyboard, the facts and the gate. agent-4 built it one issue, one PR at a time (PRs #14–#27):

| Issue | What |
|---|---|
| #1 | The scaffold: Next.js 15, `output: 'export'`, TypeScript strict, Tailwind v4, next-intl, Playwright with axe |
| #2 | Brand tokens, self-hosted Inter and Noto Sans Bengali, the logo, favicons, header and footer |
| #3 | The screenshot pipeline: the app's goldens as AVIF and WebP at four widths, with blur placeholders, pinned to one app commit |
| #4–#8 | The sections: the hero with the animated phone, "A day with Sogda" (the scroll story), the forgetting curve, the A1 → C2 journey, practice and exams, the feature grid, three looks, "in your language", the gallery, the FAQ and the final CTA |
| #9 | i18n: the visitor's language first, English by default, a remembered pick |
| #10 | Impressum and Datenschutzerklärung, German binding with an English translation |
| #11 | SEO: metadata, per-locale Open Graph images, sitemap, robots, JSON-LD `MobileApplication` |
| #12 | QA: the device matrix, keyboard-only and JavaScript-off checks |
| #13 | Launch: Vercel, the domain, and `pnpm verify:live` |

### Launch and the owner's decisions (2026-09-30)

- **Vercel's first deploys failed three ways.** Each got its own fix: a lockfile that didn't match `package.json` (#30); the Next.js preset expecting a server build, fixed with `framework: null` (#31); and a redirect loop between Vercel's domain setting and a `vercel.json` redirect, fixed by removing the latter (#33).
- **The owner's details** went into the Impressum only (#32), and their decisions on price, analytics and the Impressum into the brief (#29).
- **A `dev` branch** (#35, PR #39): PRs go to `dev`, and only `main` deploys.
- **Five languages:** German (#36), Polish (#37) and Russian (#38, with Cyrillic in the Inter subset), each in the app's own wording.
- **The app's v1.1.0 languages** (#34, PR #46): the site states meanings in English, Bangla, Russian or Polish, word for word from the store listing. The Polish and Russian pages lead with their own language.

### Performance (#22, PRs #47 and #50)

- **The measuring was wrong.** The live `/bn` measured 91, with LCP 3.1 s and TBT 191 ms. A trace showed the page ready at 0.24 s, then no frame until 1.15 s: headless Chrome on Windows has no display, and its frame clock drops to 1 Hz. `pnpm lighthouse` now runs with vsync off.
- **No React in the browser** (#47). Every component renders on the server only. A post-build step strips Next's runtime and the inlined RSC payload, which was 177 KB of `/bn`'s 329 KB and included a second copy of the CSS. The build fails on any `'use client'`. The behaviour, which was nine client components, is one 2.8 KB script, `public/site.js`.
- **Nothing measured at load** (#50). The live site then showed a 459 ms long task. `site.js` had read geometry inside `content-visibility` sections, which forced their layout (all their Bangla text) and started their lazy images before the hero painted.
- **The result, live:**

  | | Performance | LCP | TBT |
  |---|---|---|---|
  | /en | 100 | 1.74 s | 58 ms |
  | /de | 99 | 1.78 s | 92 ms |
  | /pl | 99 | 1.82 s | 99 ms |
  | /ru | 98 | 1.85 s | 118 ms |
  | /bn | 100 | 1.53 s | 0 ms |

  Accessibility, Best Practices and SEO are 100 everywhere, and CLS is 0.

### QA (#12, PR #48)

- On the live site, `pnpm verify:live` passes 33/33.
- The JSON-LD, the sharing cards (1200 × 630 per locale), hreflang, the sitemap and robots were checked live.
- e2e passes on six browser projects.
- A flaky WebKit redirect test got a 15 s allowance (#48).
- Android Chrome 133 on emulator-5558 rendered `/bn` correctly, until the emulator exited mid-check.
- The checks that need a person or hardware moved to **#52**, the owner's: a real phone, a screen reader, and real Safari.

### Open

- **#45:** the Google Play link, waiting for v1.1.0's Play release (app #1123).
- **#52:** the owner's hand checks.
- **#54:** the team's review of the site and its competitors. agent-4 drafts the master plan.

## Lessons

- **Measure the live site.** Localhost hid the late Bengali font and the forced layout; the live trace found both.
- **A tool's quirk can pass for a site problem.** Before optimising, check the tool against a control: example.com painted at 0.1 s under the same setup, and that exposed the frame clock.
- **Don't stash to undo a plant.** `git stash push -- <file>` stashes the whole file, real edits included. Plant on a scratch copy and copy it back.
