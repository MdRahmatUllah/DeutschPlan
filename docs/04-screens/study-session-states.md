# T2 · Study session (2/2 — card states)

| State | Artboard | What differs |
| --- | --- | --- |
| Front | `StudyFront` | Headword, caption, speaker, hint, *Show meaning*. Rating bar hidden. |
| Revealed | `StudyBack` | Meanings "bill, invoice / বিল, চালান"; two examples with play and translation; "⟶ die Rechnung bezahlen · eine Rechnung stellen"; "≈ Im Restaurant auch: „Zahlen, bitte!“"; prompt "How well did you remember it? The interval shows when it comes back."; rating bar. |
| New word | `StudyNew` | Block label "New today · 2 / 7", banner "Neue Wörter · Wohnen & Haushalt", *New* chip on the card, buttons *I know it* / *Skip → backlog* above *Show meaning*, undo snackbar "Moved die Kaution to the backlog · Undo". |
| Cloze | `StudyCloze` | *Cloze* chip; prompt "Fill the gap"; sentence with the word blanked "Ich habe die ___ noch nicht bezahlt." and its translation; text field with the umlaut row; on correct: "Correct · the sentence plays" then the rating bar with prompt "How well did you know it?"; footnote explaining the switch and how to revert: two Good or Easy ratings, or, for a card the learner chose in W1 (`card_mode_manual`, BR-FSRS-06), that they chose it (#515). |
| Grammar set (inline L15) | `GrammarPractice` | See `grammar-practice.md`; rendered inside the session with the same top bar. |
| Block banner | — | 1 s slide-in label between blocks. |
| Audio unavailable | — | The speaker and the mini play buttons slashed (#452); each tap says how to install a voice. |

**Cloze rules.** Entered after two consecutive ≥ Good ratings (BR-FSRS-06). The blanked token is the headword (or its inflected form found in the sentence via `searchKey` prefix match); a verb also by its participle or its split stem, a reflexive without its `sich`, a phrase by its words in a row or else its noun (`domain/cloze.dart`, #325); if no example contains it, the plain card is used. Answer via `checkGerman` (article not required). *Almost* shows the correct spelling and still allows rating. After a wrong answer the rating bar offers **Again and Hard only**, with Good and Easy faded: those are for a right or *almost* answer (the lead's call, #345). The learner can choose either card from Word detail, and the rule then keeps their choice.

**Interference tip.** When `interference_tips` has a row for the word, a Tangerine-bar callout appears under the meanings on the back: "⚠ bekommen = to get, not 'to become'".

**Goldens.** One per state per theme (`study_front_light.png` …).
