# Answer checking

`domain/answer_check.dart` + `domain/text_norm.dart`. Implements BR-ANS-01…04.

| Function | Input | Verdicts |
| --- | --- | --- |
| `checkMeaning(given, expectedList)` | German → a meaning language | correct · almost · wrong |
| `checkGerman(given, german, article)` | a meaning language → German, cloze, forms | correct · almost · wrongArticle · wrong |
| `checkArticle(given, article)` | Articles | correct · wrong |
| `checkForm(given, expectedForm)` | Forms quiz | as `checkGerman` without article logic |

Normalisation (`searchKey`, `searchKeyAlt`) is byte-identical to the Python pipeline, which applies NFC: Bangla's precomposed nukta letters (ড় ঢ় য়, as some keyboards type them) key as letter + nukta, as the course stores them (#655); `test/domain/text_norm_test.dart` loads `tools/test_vectors.json`.

Notes and alternatives (#645): `splitMeanings` splits a meaning cell at `/`, `,` and `;` only outside brackets, and `checkMeaning` tries the whole cell as shown and each synonym, each as written and without its bracketed note (`meaningAnswers`, which Search's exact tier uses too, so the two agree). A typed list of several synonyms ("hi / hello", any order) is split the same way: right when each part is one of the cell's, *almost* when each is at least almost, wrong when one isn't (#678). `germanForms` does the same for a German headword or forms cell: its ` / ` alternatives, each side of an in-word slash, with and without the note; only the text outside the note is split, so a word from inside a note is never an answer on its own. The article check (BR-ANS-02) runs per alternative.

Phrases (#687): a phrase with no article of its own (`pos = phrase`, `article` NULL: "Das stimmt nicht", "den Tisch decken") is typed whole. Its leading der, die, das, den, dem or des is one of its words, so it is neither optional nor a *wrong article*: "stimmt nicht" and "die Tisch decken" are wrong. EN→DE and listening items carry it as `phrase` (the quiz's `QuizItem`, the exam's `WordQuestion`, kept in the row's prompt JSON); a paper stored before it has none and grades as it did.

Umlauts (#675): German is compared on two keys. The expanded one (ä → ae) decides *correct*, so "Tür", "Tuer" and "Straße"/"Strasse" are right. A match only on the folded key (ä → a) is *almost*: a bare vowel can be another word or form, the very thing a gap fill, a forms item or a listening item tests. Meanings (English, Bangla) keep the folded match as *correct*.

Meanings in the course's other languages (#1120): a typed meaning is right without its marks, compared folded on both sides: Polish ą ć ę ł ń ó ś ź ż as a c e l n o s z z (`zolty` for *żółty*, `lawka` for *ławka*), Russian ё as е (`елка` for *ёлка*), and a combining acute (U+0301) is ignored. Case and spacing are ignored, as everywhere. Bangla keeps its raw match (#716), and German is untouched by this: its umlauts follow #675. A meaning list (`a / b`) takes any of its items, as English does.

Letters and hyphens (#699): BR-ANS-01's typo gate counts the letters of the expected word with ß as one, so the five-letter "Größe" gets no typo allowance ("Grüße" is wrong), while "Straße" does. A meaning's hyphen may be left out: "email" is right for "e-mail", in a check and on Search's exact tier. A German one may not: "Email" is enamel, not "E-Mail".

Shared meanings (#832): EN → DE (L8) and the exam's Reverse ask for the German of a meaning cell, and some cells belong to several words: "you" is *du*, *dich* and *Sie*, "doctor" *der Arzt* and *die Ärztin*. An answer is right if it is any word of the course whose cell, English or Bangla as the prompt shows it, is the prompt, compared as written (`ContentDao.sharedMeanings`; the item carries them as `also`, a re-ask keeps them, and a stored Reverse item keeps them in its prompt JSON). Under an English prompt with its Bangla shown ("both"), the other word's Bangla must be that too: "you" over *তুমি* is *du*, not *Sie*. Another word counts only when it is right: a near miss or a wrong article is judged against the word asked, which the feedback names. The FSRS rating goes to the word asked.

Scoring: correct 1 · almost 0.5 · wrongArticle 0 (feedback names the article) · wrong 0.

Umlaut helper row (ä ö ü ß, long-press ß → ẞ) is a shared widget `SgUmlautBar` attached to every German text field. Where it sits under its field (R2's German, T2's cloze and grammar practice's answers), the field's `scrollPadding` (`SgUmlautBar.scrollPadding`) makes a focused field scroll up with the whole row, and what follows it (R2's next field, *Check*), above the keyboard, except past 130 %, where *Check* may scroll under the keyboard and the keyboard's Done checks (#564). Flutter's default 20 dp left the keys cut at the keyboard's edge (#396, #515). It reserves the keys' own height (`SgUmlautBar.rowHeight`: 44 dp, or their text's line once taller): scaling 44 by the text's growth had reserved 79 dp for a 49 dp row at 200 % (#572). Typing past 130 %, the margin under the keys is 12 dp, not 20, on T2's cloze and L15's gap, which share the answer field (#572). L8 and L12 pin the row above the keyboard instead.
