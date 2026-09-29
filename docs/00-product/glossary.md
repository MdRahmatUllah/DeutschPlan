# Glossary

| Term | Meaning |
| --- | --- |
| Step | One of 12 course units, e.g. A2.1. Half a CEFR level. |
| Active step | The step from which new words are drawn. |
| Plan item | One card scheduled for a date: kind `new` or `revise`. |
| Backlog | New-word plan items from earlier dates that are not completed. |
| FSRS | Free Spaced Repetition Scheduler; predicts memory stability and difficulty. |
| Stability | Days until recall probability drops to 90 %. |
| Retrievability | Current probability of recall. |
| Due | Date the scheduler wants a card reviewed. |
| Cloze card | Revision card with the word blanked in an example sentence. |
| Interference tip | A note about a trap for Bangla/English speakers (false friend, seit + present …). |
| Mock | A generated practice exam for one step; three per step, seeds 1–3. |
| Rubric | The self-assessment checks: two for Writing, four for Speaking, a point each. |
| content.db | Read-only course database bundled with the app. |
| user.db | Learner database created on the device. |
| SgSurface | The only surface widget: in the glass theme it renders the frosted panel. |
| Aurora | The drifting colour backdrop of the glass theme. |

## Bangla UI terms

One Bangla word per term, wherever the copy names it (#696). A message that
names a tab or a button uses the label the Bangla UI shows, never the English
one (#684). `test/l10n_test.dart` fails on the rejected spellings.

| English | Bangla | Not |
| --- | --- | --- |
| Step | ধাপ | |
| Backlog | ব্যাকলগ | জমে থাকা |
| Revision, revise | রিভিশন | পুনরাবৃত্তি (which means "a repeat") |
| Review (one rating of a card) | রিভিউ | |
| Due; left ("3 left") | বাকি | |
| To do (a word's status) | শেখা বাকি | বাকি, which means "due" |
| Learning (a word's status) | শিখছি | |
| Done (a word's status) | শেখা হয়েছে | সম্পন্ন, শেষ |
| Suspended | স্থগিত | |
| Voice | ভয়েস | কণ্ঠ |
| Mock | মক | |
| Today, Learn, Search, Me (tabs) | আজ, শিখুন, খুঁজুন, আমি | the English names |
| Again, Hard, Good, Easy (ratings) | আবার, কঠিন, ভালো, সহজ | the English names |

## Polish UI terms

One Polish word per term, as for Bangla (#1078). Messages speak to the learner
as *ty*, and avoid a past tense that needs a gender ("Ukończono…", a noun, or
"label: {count}"). A message that names a tab or a button uses the Polish
label. `test/l10n_test.dart` fails on the rejected spellings and on an English
tab or rating label inside a Polish message. Drafted by an agent: a native
speaker reviews them before release.

| English | Polski | Not |
| --- | --- | --- |
| Step (a course unit) | etap | krok (a setup page's "Krok 1 z 5" only) |
| Backlog | zaległości | Backlog |
| Revision, revise; a review | powtórka, powtarzać | |
| Due; left ("3 left") | do powtórki; zostało 3 | |
| To do (a word's status) | Do nauki | |
| Learning (a word's status) | W nauce | |
| Done (a word's status) | Znane | Opanowane (too long for M1's counts at 150 %) |
| Suspended | Wstrzymane | |
| Voice | głos | |
| Mock | egzamin próbny | egzamin testowy |
| Streak | seria | |
| Meaning language; app language | język znaczeń; język aplikacji | |
| Today, Learn, Search, Me (tabs) | Dziś, Nauka, Szukaj, Profil | the English names |
| Again, Hard, Good, Easy (ratings) | Znowu, Trudne, Dobre, Łatwe | the English names |
