# Planned screens

Screens specified and decided, but not built yet. They're kept apart because
`golden_coverage_test.dart` requires every screen in `docs/04-screens/` to
have goldens. **The PR that builds a screen moves its doc up a level,** with
its goldens and its routes and providers in `navigation.md` and
`state-management.md`.

None right now. D1, D2 and D3 (v1.2.0, epic #1219) were built and moved up a level, to
[`doc-import.md`](../doc-import.md), [`doc-words.md`](../doc-words.md) and
[`my-documents.md`](../my-documents.md) (#1329).

**Their artboards** (#1222) are in all eight canvases, with the base canvases' PNGs in `docs/design/<canvas>/` and their row in README's screen tables:
- `deutsch-plan-design-html/<canvas>/screens/` and `deutsch-plan-v2-aurora-glass-html/<canvas>/screens/`;
- the screens `DocImport`, `DocImportProcessing`, `DocImportCorrect`, `DocWords`, `DocWordsCard`, `DocWordsEmpty`, `MyDocuments` and `MyDocumentsEmpty`;
- the section *Documents · v1.2.0* in each canvas's index.

The engine is [`../../03-domain/document-matcher.md`](../../03-domain/document-matcher.md), and the rules are BR-DOC and BR-PLAN-11 in [`../../00-product/business-rules.md`](../../00-product/business-rules.md).
