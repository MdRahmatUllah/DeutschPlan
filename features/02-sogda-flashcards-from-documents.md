# 02 — Sogda Feature: Flashcards From Your Own Documents

| Field | Value |
|---|---|
| Type | Feature inside Sogda (doc 01) |
| Status | Decided — first major update after launch |
| Priority in focus list | 2 |
| Data | 100% on device |

---

## 1. Summary

The learner brings their own German text: a letter, a PDF, a photo of a textbook page, a news article. Sogda finds the words they don't know yet and turns them into flashcards in their normal daily review.

**Why it matters:** learners study the German they actually meet in their lives, not only a textbook list. That makes learning more motivating, and each card is tied to a real sentence the learner has seen, which helps memory. It also gives users a reason to come back and a strong "what's new" story for the stores.

**Strategic link:** this is the bridge to the letter assistant (doc 03). A user who scans a Finanzamt letter there can send the hard words straight into Sogda.

---

## 2. User stories

1. *As a learner,* I photograph a letter from my landlord, see which words I don't know, and add them to my daily review.
2. *As a B1 student,* I import a PDF article and add all B1–B2 words in one tap.
3. *As a learner,* each card shows the sentence from my own document, so I remember where I saw the word.
4. *As a learner,* words I already know or already have in my backlog are not added again.
5. *As a privacy-conscious user,* my documents never leave my phone.

---

## 3. User flow

```
Home → "Learn from a document"
   ├─ Take photo(s)          (camera, multi-page)
   ├─ Import PDF / image     (file picker, share sheet)
   └─ Paste text             (clipboard)
        ↓
Processing (on device): OCR → tokenise → lemmatise → match → filter
        ↓
Review screen: text with unknown words highlighted, colour-coded by level
   - tap a word → mini card preview (article, plural, meaning, level)
   - bulk actions: "Add all A2", "Add all B1+", "Add all not-in-course"
        ↓
Confirm → cards created in a "From my documents" deck → enter FSRS queue
        ↓
Optional: save the document (text only or text + image) in "My documents"
```

---

## 4. Processing pipeline (all on device)

| Step | What happens | Implementation |
|---|---|---|
| 1. Text extraction | OCR on photos/scans; direct text for PDFs with a text layer | ML Kit Text Recognition (Android), Apple Vision (iOS); PDF text via a PDF parser package |
| 2. Clean-up | Fix hyphenation at line ends ("Ver-\nwaltung" → "Verwaltung"), remove headers, footers and page numbers | Rules |
| 3. Tokenisation | Split into sentences and words; keep each word's sentence | Rules / regex |
| 4. **Lemmatisation** | "ging" → gehen, "Häusern" → Haus, "angerufen" → anrufen | Lemma lookup table (precomputed form→lemma dictionary bundled with the app); separable verbs need sentence-level handling ("rufe … an" → anrufen) |
| 5. Level matching | Look up the lemma in the A1–C2 word lists → level, article, plural, meanings | Sogda SQLite |
| 6. Filtering | Remove stop words, known words, words already in backlog or review, names and numbers | User progress DB |
| 7. Card building | Front: word + article. Back: meaning(s) in chosen language(s), plural, level, **original sentence**, optional audio | Sogda card model |
| 8. Cloze cards (optional) | From the original sentence, blank the word: "Bitte überweisen Sie den Betrag ___ zum 15. Mai" → bis | Rules |
| 9. Scheduling | New cards enter the existing FSRS/SM-2 queue at the user's daily limit; overflow goes to backlog | Existing scheduler |

### Words not in the course lists
- Marked **"not in course"**.
- Meaning comes from the on-device translation model (Hy-MT or ML Kit) if installed. Otherwise the user enters it manually or skips the word.
- Compound nouns: try splitting ("Nebenkostenabrechnung" → Nebenkosten + Abrechnung) and show the parts as hints.

### Optional AI layer (only where available)
- Apple Foundation Models (iOS, Apple Intelligence devices) or Gemini Nano (supported Android phones).
- Uses: a simple extra example sentence, a 3–5 question comprehension quiz on the document, a short summary of the document.
- **Rule:** the core feature must work fully without an LLM. AI output is labelled as AI-generated.

---

## 5. Data model additions

```
documents(id, title, source_type[photo|pdf|text], created_at, text, image_path?, word_count)
document_words(document_id, lemma, surface_form, sentence, level, in_course, status[new|known|added|ignored])
cards(... existing fields ..., origin[course|document], document_id?, context_sentence?)
```

---

## 6. Settings

- Default bulk filter (e.g., "suggest only my level and one above").
- Save original image: yes / no (privacy and storage).
- Auto-delete documents after N days.
- Daily cap for document cards (so a long document doesn't flood the review).

---

## 7. Edge cases

| Case | Handling |
|---|---|
| Handwriting / poor photo | Show OCR confidence; ask to retake; allow manual correction of the text |
| Very long PDF | Process page by page with progress; limit the free tier to N pages if needed |
| Non-German text | Detect the language; warn the user |
| Ambiguous lemma ("Weg" noun vs "weg" adverb) | Use capitalisation and part-of-speech heuristics; let the user choose |
| Duplicates across documents | One card per lemma; add new context sentences to the existing card |

---

## 8. Monetization options

- **Free:** e.g., 3 documents per month or 50 cards per month.
- **Pro / lifetime unlock:** unlimited documents, cloze cards, AI quiz. Fits the later "lifetime" model being considered for Sogda.
- Or keep it free to drive retention and the cross-sell to the letter assistant.

---

## 9. Success metrics

| Metric | Target |
|---|---|
| % of active users who try the feature in the first 30 days | > 20% |
| Cards added per document | 8–20 |
| Retention of users who used the feature vs those who didn't | +25% D30 |
| Review accuracy on document cards vs course cards | Equal or higher |

---

## 10. Build estimate

| Part | Effort |
|---|---|
| OCR + PDF import + paste | 1 week |
| Lemma dictionary + matching + filtering | 1.5–2 weeks (the hardest part) |
| Review / highlight UI + bulk actions | 1 week |
| Card integration + cloze | 0.5–1 week |
| Optional LLM layer | 1 week (can ship later) |
| **Total** | **about 4–6 weeks** |

---

## 11. Integration with the letter assistant (doc 03)
- Share sheet or deep link: "Send unknown words to Sogda".
- Shared lemma dictionary and OCR module across both apps (one Flutter package).
