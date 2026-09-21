# Reminders, background work and the home-screen widget

## Reminder

`services/notifications.dart` with `flutter_local_notifications`. One daily notification at `reminder_time` on study days. With `reminder_only_when_due = 1` (default) the text is built from the real plan at send time by a `workmanager` task scheduled 10 minutes earlier: "12 revisions · 7 new · about 9 min" (+ "Grammar due: …"); if the day is already complete or nothing is due, the notification is cancelled. Tap → `deutschplan://today`. Permission is requested only when the learner switches the reminder on.

## Background tasks (`workmanager`)

| Task | When | Does |
| --- | --- | --- |
| `plan_pregenerate` | 00:05 local, daily | `openDay(today)` so the widget and reminder are accurate |
| `reminder_compose` | reminder_time − 10 min | builds/cancels the notification |
| `widget_refresh` | after every session, hourly for the word of the day | writes the snapshot |

## Widget (`home_widget`)

The app writes `widget_snapshot.json` ({step, remaining, total, minutes, wordOfDay{uid, article, german, meaning}, done}) to the shared container; Glance (Android) and WidgetKit (iOS) render it. Sizes: small 2×2 (ring, "8 left", step), medium 4×2 (adds Wort des Tages with a pronounce action that deep-links to `deutschplan://word/<uid>?speak=1`). Word of the day = a learned word due soon, never a To-do word. When the day is done the widget shows the Lime check and tomorrow's preview.
