# Screen guide template

Every screen document follows this structure. Keep the headings; leave "None" where a section does not apply.

1. **Purpose** — one sentence.
2. **Prototype** — artboard names as they appear in the screen index of `docs/README.md`. Each name resolves to four files per design set; see the design-set table there.
3. **Reached from / Leads to** — every entry and exit, with the navigation kind.
4. **Layout** — top to bottom; components by name from `01-architecture/theming.md` and the component set.
5. **Functional requirements** — `FR-<ID>-nn`, MUST/SHOULD/MAY.
6. **Business rules applied** — IDs from `00-product/business-rules.md`.
7. **States** — empty, loading, error, completed, edge cases.
8. **Interactions & motion** — gestures, haptics, animations.
9. **Data** — providers read, repository calls, tables touched.
10. **Developer notes** — widget names, files, pitfalls.
11. **Tests** — required unit/widget/golden tests naming the FR IDs.
