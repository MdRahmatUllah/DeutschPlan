---
name: sogda-rename
description: "Owner 2026-09-26 — the app is Sogda (sogda.de), app id de.sogda.app, internals renamed too (package sogda, Dp→Sg prefix, sogda:// scheme); repo name kept; brand kit in docs/sogda-brand-kit"
metadata:
  node_type: memory
  type: project
  originSessionId: 235e22a9-6d7c-4bb0-8033-62309951e502
  modified: 2026-09-26T21:02:25.657Z
---

The owner decided on 2026-09-26 (after v1.0.1, before any Play upload):
- **The name is Sogda.** The domain is sogda.de, the tagline "The road to a new language", the Play title "Sogda: German A1–C2". Always one word with a capital S.
- **The application id is `de.sogda.app`**, replacing `io.github.rahmatullah.deutschplan`. It is permanent after the first upload.
- **Internals are renamed too:**
  - the Dart package `deutschplan` becomes `sogda`;
  - the deep-link scheme `deutschplan://` becomes `sogda://`;
  - the method channels `deutschplan/*` become `sogda/*`;
  - class names containing DeutschPlan are renamed;
  - **the design-system prefix Dp becomes Sg** (DpText → SgText, DpTokens → SgTokens, dp_*.dart → sg_*.dart).
- **sogda.de** appears in the store listing and docs only, not in the app.
- **The GitHub repo stays MdRahmatUllah/DeutschPlan** for now. Report-a-problem links keep pointing at it.
- **The brand kit** is `docs/sogda-brand-kit/`: the tiles mark, "a" behind and "Ä" in front, in Lagoon, Sun, Ink and Paper, Inter ExtraBold. It replaces `docs/branding/`, which is deleted. Variant A (tiles) is the icon; variant B (with the Silk Road dots) is for marketing only.
- **What doesn't change:** the local folders (F:/appDevs/deutschplan, dp-wt, dp-team) and the artboard folders (deutsch-plan-design-html…) keep their names.

**Why:** the app will teach more languages than German; the owner bought sogda.de.

**How to apply:** new code uses `package:sogda/` and the Sg* names. An old memory or doc naming DpText, DpTokens and the like means SgText, SgTokens. Never re-ask these. Related: [[v1-release]], [[v1-scope]].
