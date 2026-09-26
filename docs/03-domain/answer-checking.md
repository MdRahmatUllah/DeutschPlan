# Answer checking

`domain/answer_check.dart` + `domain/text_norm.dart`. Implements BR-ANS-01…04.

| Function | Input | Verdicts |
| --- | --- | --- |
| `checkMeaning(given, expectedList)` | DE→EN / DE→BN | correct · almost · wrong |
| `checkGerman(given, german, article)` | EN→DE, cloze, forms | correct · almost · wrongArticle · wrong |
| `checkArticle(given, article)` | Articles | correct · wrong |
| `checkForm(given, expectedForm)` | Forms quiz | as `checkGerman` without article logic |

Normalisation (`searchKey`, `searchKeyAlt`) is byte-identical to the Python pipeline; `test/domain/text_norm_test.dart` loads `tools/test_vectors.json`.

Scoring: correct 1 · almost 0.5 · wrongArticle 0 (feedback names the article) · wrong 0.

Umlaut helper row (ä ö ü ß, long-press ß → ẞ) is a shared widget `UmlautBar` attached to every German text field. Where it sits under its field (R2's German, T2's cloze and grammar practice's answers), the field's `scrollPadding` (`DpUmlautBar.scrollPadding`) makes a focused field scroll up with the whole row, and what follows it (R2's next field, *Check*), above the keyboard, except past 130 %, where *Check* may scroll under the keyboard and the keyboard's Done checks (#564). Flutter's default 20 dp left the keys cut at the keyboard's edge (#396, #515). L8 and L12 pin the row above the keyboard instead.
