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

Umlaut helper row (ä ö ü ß, long-press ß → ẞ) is a shared widget `UmlautBar` attached to every German text field.
