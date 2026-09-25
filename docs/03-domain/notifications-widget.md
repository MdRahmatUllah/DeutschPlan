# Reminders, background work and the home-screen widget

## Reminder

`services/notifications.dart` with `flutter_local_notifications`. One daily notification at `reminder_time` on study days. With `reminder_only_when_due = 1` (default) the text is built from the real plan at send time by a `workmanager` task scheduled 10 minutes earlier: "12 revisions · 7 new · about 9 min" (+ "Grammar due: …"); if the day is already complete or nothing is due, the notification is cancelled. Tap → `deutschplan://today`. Permission is requested only when the learner switches the reminder on.

Details the reminder settles (#157):
- `ReminderScheduler` (`data/repositories/reminder_scheduler.dart`) keeps the schedule to `reminder_enabled`, `reminder_time`, `study_days_mask` and `ui_language`: synced when the app starts and again on each change, nothing scheduled while the reminder is off. Syncs run one after another: restart setup writes three of those settings at once, and an "on" still scheduling while the "off" cancels would leave reminders the learner turned off.
- It schedules the next week's study days as one notification each, at the local `reminder_time` of each date (`domain/reminder_times.dart`), so a daylight-saving change can't shift one by an hour. Today's is included only while it is still ahead. A week is what's scheduled; `plan_pregenerate` (#158) keeps it rolling for a learner who doesn't open the app.
- `ReminderNotifications` (`services/reminder_notifications.dart`) is `flutter_local_notifications`: an inexact alarm on Android (`inexactAllowWhileIdle`, so no exact-alarm permission), a UNUserNotificationCenter request on iOS. The scheduled reminders come back after a reboot (`ScheduledNotificationBootReceiver`, `RECEIVE_BOOT_COMPLETED`).
- It never asks for the permission. `NotificationPermission` asks when the reminder is switched on (S2 page 5, and M5 in #147), and a phone that said no simply doesn't show the notification.
- Scheduled, the reminder reads "Time for German — Today's plan is ready. A few minutes is enough.", in the app language; `reminder_compose` writes the day's plan into it (below). `reminder_only_when_due` leaves the schedule as it is; cancelling a day with nothing due is that task's job.
- Each reminder's notification id is its date (`20260921`), so the task can replace or cancel today's alone.
- A tap opens `deutschplan://today`, through `resolveDeepLink`: a tap while the app runs, and the one that starts it (the plugin's launch details).
- Each reminder is an instant, the local `reminder_time` when it was scheduled. A learner who changes time zone hears the old zone's 19:30 until the app next starts and reschedules.

## Background tasks (`workmanager`)

| Task | When | Does |
| --- | --- | --- |
| `plan_pregenerate` | 00:05 local, daily | `openDay(today)` so the widget and reminder are accurate |
| `reminder_compose` | reminder_time − 10 min | builds/cancels the notification |
| `widget_refresh` | after every session, hourly for the word of the day | writes the snapshot |

Details the background tasks settle (#158):
- `services/background_tasks.dart` runs them; `BackgroundWork` (`services/background_work.dart`) queues them. On Android each is WorkManager unique work named after the task. On iOS `plan_pregenerate` and `reminder_compose` are BGProcessingTasks and `widget_refresh` a BGAppRefreshTask, with the three ids in `BGTaskSchedulerPermittedIdentifiers` and registered in `AppDelegate`, and the `fetch` and `processing` background modes.
- `plan_pregenerate` and `reminder_compose` are one-offs that queue their own next run: the app queues tonight's 00:05 at every start, and `ReminderScheduler` queues the compose on every sync, ten minutes before the next reminder, or at once when the sync falls inside those ten minutes (it has just put the plain text back). A compose queues the one for the next study day's reminder after it. `widget_refresh` is periodic, hourly.
- `plan_pregenerate` runs `openDay(today)` and a reminder sync, so the week of reminders rolls on for a learner who doesn't open the app.
- `reminder_compose` reads T1's view of today. Its text is the open blocks and BR-PLAN-09's estimate, "12 revisions · 7 new · about 9 min", a block with nothing open left out, and "Grammar due: <first topic due>" on a second line (expanded on Android). Practice sentences don't count as due. When nothing of revise, new or grammar is open, which includes a finished day, it cancels today's reminder under `reminder_only_when_due` and leaves the plain one otherwise. On a rest day it cancels. When it runs after the reminder time, or with the reminder off, it writes nothing.
- A task runs in an engine of its own. It opens user.db on its own connection (not drift's shared isolate, which would end with the task's engine under an app that joined it meanwhile), with `busy_timeout` so its writes wait for the app's; the app's streams don't hear them, and only `openDay`'s rows are written. A task finds no course before the app's first start and does nothing.
- iOS runs its tasks when it chooses, never before the time asked. A compose that runs late leaves the plain reminder.
- `widget_refresh` writes the widget's snapshot (below), and so does `plan_pregenerate` after `openDay`.

## Widget (`home_widget`)

The app writes `widget_snapshot.json` ({step, remaining, total, minutes, wordOfDay{uid, article, german, meaning}, done}) to the shared container; Glance (Android) and WidgetKit (iOS) render it. Sizes: small 2×2 (ring, "8 left", step), medium 4×2 (adds Wort des Tages with a pronounce action that deep-links to `deutschplan://word/<uid>?speak=1`). Word of the day = a learned word due soon, never a To-do word. When the day is done the widget shows the Lime check and tomorrow's preview.

Details the snapshot settles (#159):
- `services/widget_snapshot.dart` builds it from T1's view of today: `{date, step, remaining, total, minutes, done, wordOfDay{uid, article, german, meaning}, tomorrow{revise, newWords, minutes}}`. `remaining` and `total` are the ring's (FR-T1-02) and `minutes` its estimate. `tomorrow` is set once the day is done, for the Lime-check state, and is null before. `date` lets a widget tell yesterday's snapshot from today's.
- It is stored as the JSON string under `widget_snapshot` in `home_widget`'s shared store: SharedPreferences on Android, and the App Group `group.app.deutschplan`'s UserDefaults on iOS (release.md). #160 and #161 read it there and add the `updateWidget` call that redraws them.
- Word of the day (FR-X1-03, `domain/word_of_day.dart`): the learned words (learning or done, never To-do or suspended) due within three days. One is picked by a generator seeded with the date, over the uids in order, so it holds all day while the candidates do. A word revised today can leave them and move the pick. None, and `wordOfDay` is null. The meaning follows `meaning_language`: English, Bangla (English where the course has none), or both as "flat, apartment · ফ্ল্যাট".
- Written at midnight (`plan_pregenerate`), hourly (`widget_refresh`), and in the app whenever the snapshot changes (`followWidget`, from launch). A finished session always changes it, which is FR-X1-01's "after every session". An unchanged snapshot isn't written again, and a store that can't be written costs one refresh, never the task. The meaning follows `meaning_language` as M3 changes it. An app left open across midnight reads the date again before it writes, so it never puts yesterday's snapshot over the new day's.
