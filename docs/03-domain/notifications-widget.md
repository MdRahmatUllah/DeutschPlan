# Reminders, background work and the home-screen widget

## Reminder

`services/notifications.dart` with `flutter_local_notifications`. One daily notification at `reminder_time` on study days. With `reminder_only_when_due = 1` (default) the text is built from the real plan at send time by a `workmanager` task scheduled 10 minutes earlier: "12 revisions · 7 new · about 9 min" (+ "Grammar due: …"); if the day is already complete or nothing is due, the notification is cancelled. Tap → `deutschplan://today`. Permission is requested only when the learner switches the reminder on.

Details the reminder settles (#157):
- `ReminderScheduler` (`data/repositories/reminder_scheduler.dart`) keeps the schedule to `reminder_enabled`, `reminder_time`, `study_days_mask` and `ui_language`: synced when the app starts and again on each change, nothing scheduled while the reminder is off. Syncs run one after another: restart setup writes three of those settings at once, and an "on" still scheduling while the "off" cancels would leave reminders the learner turned off.
- It schedules the next week's study days as one notification each, at the local `reminder_time` of each date (`domain/reminder_times.dart`), so a daylight-saving change can't shift one by an hour. Today's is included only while it is still ahead. A week is what's scheduled; `plan_pregenerate` (#158) keeps it rolling for a learner who doesn't open the app.
- `ReminderNotifications` (`services/reminder_notifications.dart`) is `flutter_local_notifications`: an inexact alarm on Android (`inexactAllowWhileIdle`, so no exact-alarm permission), a UNUserNotificationCenter request on iOS. The scheduled reminders come back after a reboot (`ScheduledNotificationBootReceiver`, `RECEIVE_BOOT_COMPLETED`).
- It never asks for the permission. `NotificationPermission` asks when the reminder is switched on (S2 page 5, and M5 in #147), and a phone that said no simply doesn't show the notification.
- Until #158's `reminder_compose` builds the text from the plan, the reminder reads "Time for German — Today's plan is ready. A few minutes is enough.", in the app language. `reminder_only_when_due` leaves the schedule as it is; cancelling a day with nothing due is that task's job.
- A tap opens `deutschplan://today`, through `resolveDeepLink`: a tap while the app runs, and the one that starts it (the plugin's launch details).
- Each reminder is an instant, the local `reminder_time` when it was scheduled. A learner who changes time zone hears the old zone's 19:30 until the app next starts and reschedules.

## Background tasks (`workmanager`)

| Task | When | Does |
| --- | --- | --- |
| `plan_pregenerate` | 00:05 local, daily | `openDay(today)` so the widget and reminder are accurate |
| `reminder_compose` | reminder_time − 10 min | builds/cancels the notification |
| `widget_refresh` | after every session, hourly for the word of the day | writes the snapshot |

## Widget (`home_widget`)

The app writes `widget_snapshot.json` ({step, remaining, total, minutes, wordOfDay{uid, article, german, meaning}, done}) to the shared container; Glance (Android) and WidgetKit (iOS) render it. Sizes: small 2×2 (ring, "8 left", step), medium 4×2 (adds Wort des Tages with a pronounce action that deep-links to `deutschplan://word/<uid>?speak=1`). Word of the day = a learned word due soon, never a To-do word. When the day is done the widget shows the Lime check and tomorrow's preview.
