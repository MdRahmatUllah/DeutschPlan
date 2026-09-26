---
name: v1-scope
description: "owner decisions 2026-09-26 — v1.0 is Android-only (iOS widget/pipeline Later), Hy-MT off everywhere and #154 deferred"
metadata:
  type: project
---

Owner's decisions relayed by agent-0 on 2026-09-26:
- v1.0 ships **Android only**: #171 (iOS release pipeline) and #161 (iOS WidgetKit widget) are Later.
- Hy-MT is off in every v1.0 build (ADR 9, #173); #154 (HyMtTranslator) is deferred. A licence-clean replacement after v1.0 is #533 (Bergamot tiny recommended, #494).
- Tap targets keep their current look (#478/#492 area).
- Bangla pronunciation follows the meaning language (#537).

**Why:** these set what "M7 done" means; don't pick up iOS or Hy-MT work for v1.0.

**How to apply:** when the ready list shows only #161/#154/#171, the dev backlog for v1.0 is empty: ask agent-0 for work or take reviews/SQA re-checks. See [[keep-working]].
