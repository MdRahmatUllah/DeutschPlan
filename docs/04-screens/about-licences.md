# M9 · About & privacy · M8 · Licences

**Prototype.** `About`, `Licences`.

**Reached from.** M1 → About; M9 → Licences.

**About layout.** App mark; "Version 1.0.0 (build 41) · content 2026.09 · 21 Sep 2026"; **Privacy**: "Your progress stays on this phone. DeutschPlan has no account, no server and no analytics. The internet is used only when you open a web search link or download a model."; **Open-source and model licences** → M8; **Contact** address; **Content**: "5,594 words · 182 grammar topics · 11,188 sentences" (from `meta`).

**Licences layout.** Sections Models (Supertonic 3 — OpenRAIL-M; Hy-MT 1.5 (1.8B) — Hy-MT licence), Fonts (Inter, Noto Sans Bengali — OFL 1.1), Packages (from `LicenseRegistry`).

**Functional requirements**
- FR-M9-01 Version/build from `package_info_plus`; content version and counts from `c.meta`.
- FR-M8-01 Model and font licence texts are bundled as assets and shown in full.

**Tests.** counts equal the content manifest.
