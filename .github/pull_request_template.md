<!--
The checklist below is the one in docs/05-dev-guide/getting-started.md.
Tick what applies and strike through what does not, with a reason.
-->

## What and why

<!-- One or two sentences. What changes, and which issue it closes. -->

Closes #

## Checklist

- [ ] **Docs updated** — behaviour changes land in `docs/` in this PR. When code and the documents disagree, the documents win until they are deliberately changed (`docs/README.md`).
- [ ] **Tests** — unit for logic, widget for behaviour, with the FR/BR IDs in the test names (`test('FR-T1-03 primary button label shows remaining count', …)`).
- [ ] **Goldens** — light, dark and glass, on the phone and tablet frames, each diffed against its own artboard set. Updated only via `make goldens` and reviewed as images below.
- [ ] **Migration** — if a `user.db` table changed: a migration step in `migrations.dart`, a schema fixture, and a test opening every previous version. Columns with data are never dropped.
- [ ] **Licence check** — if a package was added: its licence is recorded and appears on the Licences screen.
- [ ] **Privacy** — no new network call without a user action (BR-PRIV-01); no analytics of any kind.
- [ ] **Accessibility** — labels and semantics on every control, targets ≥ 48 dp / 44 pt, nothing conveyed by colour alone.

## Verification

<!--
Paste the actual output. Lint runs `dart analyze --fatal-infos`, NOT
`flutter analyze` — the latter does not load the riverpod_lint analyzer plugin
and passes clean while every riverpod rule is inactive (ADR 18).
-->

```
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
flutter test
```

## Screenshots / goldens

<!-- For a screen: the artboard beside the build, per theme. -->
