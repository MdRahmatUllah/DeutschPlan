# agent-5's memory

What agent-5 knows on day one (2026-10-02), from agent-0. The board's
`agents/agent-5.md` (Now, Next, Memory) is the live copy once it has joined;
this file is the snapshot and the durable background.

## Board memory
*Empty until agent-5's first session. Refresh this section from
`<root>/dp-team/agent-5/agents/agent-5.md` when `developer-agents/` is refreshed.*

## The product, in one breath
**Sogda** (`de.sogda.app`, Android only for now; "iPhone coming soon") is an
offline German course from A1 to C2 in 12 steps.
- Its words, grammar topics and mock exams come from data: read
  `docs/05-dev-guide/site-facts.json` and never type a number.
- Meanings and a pronunciation guide come in English, Bangla, Russian or Polish, with an optional second language shown under the first. In Russian and Polish, the example sentences and the grammar rules come in the reader's language too.
- It needs no account, and progress stays on the phone.
- The positioning sentence is in sogda-website `docs/MASTER-PLAN.md` §4. The store texts, with the owner's approved titles (#1186), are in `docs/05-dev-guide/store-listing.md`.

## Where things stand (2026-10-02)
- **The app:** 1.1.0+4 is ready for the owner to sign and upload (#1123). **It isn't on Play yet**, and Play needs the feature graphic first (#1200, agent-5's P1).
- **The website** www.sogda.de is live with the W1–W3 work: 83 pages in five languages, including about, the levels, mock exams, spaced repetition, the audience pages and the Anki and Duolingo comparisons. Every one of them can be linked from a post.
- **W4 waits on the Play link:** sogda-website #45 (the link on the site), #77 (ratings) and #76 (outreach). #76's pitches are drafted in en, de, pl, bn and ru, and MK2 #1212 takes them over.
- **The owner's open steps:**
  - O1 on sogda-website #56: verifying the site in Search Console, Bing and Yandex by DNS;
  - O7: outreach after Play;
  - O9 is closed: the contact address stays the one in the Impressum.
- **Measuring:** the monthly AI-answer panel is on sogda-website #65, starting in the first week of November 2026. The owner pastes four assistants' answers, and agent-3 scores them.

## The team
- **agent-0 (lead):** assigns, reviews facts and brand, and relays the owner's decisions.
- **agent-1 and agent-2 (developers):** agent-1 is the native reviewer for pl and bn, agent-2 for ru.
- **agent-3 (SQA).**
- **agent-4 (the website):** link to its pages, and ask it for page changes by issue.

All six agents share the owner's GitHub account, so every PR body starts with `**Agent-N**`.

## Lessons the team learned the hard way (apply them from day one)
- **Edit message or JSON files as text.** A `json.load` / `json.dumps` round trip turns `\u00a0` escapes into invisible characters.
- **Heredocs in Git Bash halve backslashes.** Scripts with a backslash go through the Write tool.
- **In Git Bash, an argument like `/bn` becomes a Windows path.** Use `MSYS_NO_PATHCONV=1` or full URLs.
- **`team.py ack` marks every handoff read.** Run `status` right before it.
- **A shell variable for shas and numbers.** In a comment, take them from git or gh through a variable; never type one from memory.
- **Fetch before merge:** `git fetch -q origin && git merge origin/main` in one command.
- **Play wants RGB images.** `test_store_listing.py` caught an alpha channel on the re-shot screenshots (#1184).
- **Under load, measurements lie.** Lighthouse on this host swings with other agents' Chromium, so re-run before you believe a number.
