# Format 3: a mock-exam task, one a week (#1243)

The series `competitors.md` calls format 3: one task from Sogda's mock exam, the timer running, then the result. It goes on Sogda's YouTube channel, as Shorts (vertical) and in a playlist (landscape), on Wednesdays 14:00–16:00 (`calendar.md`).

**The clips** are on the `media` branch, `2026-10-03-1243-exam-tasks/`. Each is `exam-<level>-<task>-<lang>-<format>.mp4`, with `exam-<level>-<task>-<lang>.srt` beside it:
- the levels: `a1`, `a2`, `b1`;
- the tasks: `listening`, `writing`;
- the languages: `en`, `bn`, `ru`;
- the formats: `vertical`, `landscape`.

The app on screen is English. The captions are in the clip's language. Post them in this order, one a week: A1 listening, A1 writing, A2 listening, A2 writing, B1 listening, B1 writing.

## What the clips show, and how they were made

- **The real app** (release build, emulator-5558), one task each:
  - **Listening:** the question's word is played by the phone's German voice, and the answer is typed.
  - **Writing:** the message is finished, and its words light up and the count passes the level's minimum.
- **Then the submit, and the result screen** with the score by section.
- **The device state behind them:**
  - The learner is an English one at A1.1 whose A1.1, A2.1 and B1.1 words were marked as learned in the app's database, so those steps' mocks are open (BR-EXAM-01).
  - Each paper was started in the app. Every question but the filmed task was then given its correct answer in the database, and the writing text was written a few words short of the minimum.
  - So the score shown (83 % for listening, 87 % for writing, with Speaking at 0) is the app's own grading of that paper.
  - It isn't a learner's result, and no caption or description says it is.
- **Re-recording:** one command per clip (`python tools/media/video.py exam-a1-listening --record`), on a device in that state.
- **Captions** are the course's facts as `{tokens}` where they state a number: the writing minimum is `{mock_exam.writing_min_words.A1}` and so on.

## The rules for every post

- The level and the task in the title; never "reading" (Sogda's mock exams have none).
- The description says it's a practice task from Sogda's mock exam, **not an official Goethe or telc paper**. It never promises a pass.
- No price, no "free", no rating, no user count. Goethe and telc only described, never in a title next to "Sogda".

## Titles and descriptions

The Play link is `<play-link youtube/exam>`, filled when the listing is live (`kit.md`).

### en

| Clip | Title |
|---|---|
| A1 listening | A1 German listening: hear the word, write it (one mock-exam task) |
| A1 writing | A1 German writing: a short message with the given words (one mock-exam task) |
| A2 listening | A2 German listening: hear the word, write it (one mock-exam task) |
| A2 writing | A2 German writing: a short email with the given words (one mock-exam task) |
| B1 listening | B1 German listening: hear the word, write it (one mock-exam task) |
| B1 writing | B1 German writing: a personal letter with the given words (one mock-exam task) |

Description (the writing line only on the writing clips):

> One task from Sogda's mock exam for this level: listening or writing, with the timer running, then the result by section. The writing task asks for at least {mock_exam.writing_min_words.A1} words at A1, {mock_exam.writing_min_words.A2} at A2 and {mock_exam.writing_min_words.B1} at B1.
>
> It's a practice task, not an official Goethe or telc paper. Sogda's mock exams test listening, writing and speaking, plus vocabulary and grammar.
>
> Google Play: <play-link youtube/exam>

### bn

| Clip | Title |
|---|---|
| A1 listening | A1 জার্মান লিসেনিং: শব্দটি শুনুন, লিখুন (একটি মক পরীক্ষার টাস্ক) |
| A1 writing | A1 জার্মান রাইটিং: দেওয়া শব্দ দিয়ে ছোট বার্তা (একটি মক পরীক্ষার টাস্ক) |
| A2 listening | A2 জার্মান লিসেনিং: শব্দটি শুনুন, লিখুন (একটি মক পরীক্ষার টাস্ক) |
| A2 writing | A2 জার্মান রাইটিং: দেওয়া শব্দ দিয়ে ছোট ইমেইল (একটি মক পরীক্ষার টাস্ক) |
| B1 listening | B1 জার্মান লিসেনিং: শব্দটি শুনুন, লিখুন (একটি মক পরীক্ষার টাস্ক) |
| B1 writing | B1 জার্মান রাইটিং: দেওয়া শব্দ দিয়ে ব্যক্তিগত চিঠি (একটি মক পরীক্ষার টাস্ক) |

> এই লেভেলের জন্য Sogda-র মক পরীক্ষা থেকে একটি টাস্ক: লিসেনিং বা রাইটিং, টাইমার চলছে, তারপর প্রতিটি অংশের ফলাফল। রাইটিং টাস্কে A1-এ অন্তত {mock_exam.writing_min_words.A1}টি, A2-তে {mock_exam.writing_min_words.A2}টি আর B1-এ {mock_exam.writing_min_words.B1}টি শব্দ লিখতে হয়।
>
> এটি অনুশীলনের টাস্ক, Goethe বা telc-এর অফিসিয়াল পরীক্ষা নয়। Sogda-র মক পরীক্ষায় থাকে লিসেনিং, রাইটিং ও স্পিকিং, সঙ্গে শব্দভান্ডার ও ব্যাকরণ।
>
> Google Play: <play-link youtube/exam>

### ru

| Clip | Title |
|---|---|
| A1 listening | Немецкий A1, аудирование: послушай слово и напиши его (задание пробного экзамена) |
| A1 writing | Немецкий A1, письмо: короткое сообщение с заданными словами (задание пробного экзамена) |
| A2 listening | Немецкий A2, аудирование: послушай слово и напиши его (задание пробного экзамена) |
| A2 writing | Немецкий A2, письмо: короткое письмо по электронной почте с заданными словами (задание пробного экзамена) |
| B1 listening | Немецкий B1, аудирование: послушай слово и напиши его (задание пробного экзамена) |
| B1 writing | Немецкий B1, письмо: личное письмо с заданными словами (задание пробного экзамена) |

> Одно задание из пробного экзамена Sogda для этого уровня: аудирование или письмо, с таймером, а потом результат по разделам. В письме нужно написать минимум: A1 — {mock_exam.writing_min_words.A1}, A2 — {mock_exam.writing_min_words.A2}, B1 — {mock_exam.writing_min_words.B1} слов.
>
> Это тренировочное задание, а не официальный экзамен Goethe или telc. Пробные экзамены Sogda проверяют аудирование, письмо и говорение, а также лексику и грамматику.
>
> Google Play: <play-link youtube/exam>
