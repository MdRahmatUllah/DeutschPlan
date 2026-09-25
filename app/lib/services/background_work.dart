/// The background tasks of `notifications-widget.md` (#158).
enum BackgroundTask {
  /// 00:05 local: `openDay(today)`, and the week of reminders kept rolling.
  planPregenerate('plan_pregenerate'),

  /// Ten minutes before the reminder: its text, from the day's plan.
  reminderCompose('reminder_compose'),

  /// Hourly: the widget's snapshot (#159).
  widgetRefresh('widget_refresh');

  const BackgroundTask(this.id);

  /// The name the platform schedules it by: WorkManager's unique work, and
  /// iOS's `BGTaskSchedulerPermittedIdentifiers`.
  final String id;

  static BackgroundTask? byId(String id) =>
      values.where((task) => task.id == id).firstOrNull;
}

/// Queues [BackgroundTask]s with the platform. An interface so the schedule
/// can be tested without one, as `ReminderNotifications` is; the platform's
/// is `WorkmanagerWork` (`background_tasks.dart`).
abstract interface class BackgroundWork {
  /// Hands the platform the entry point its tasks start in.
  Future<void> init();

  /// Runs [task] once, no sooner than [delay] from now, in place of any run
  /// already queued.
  Future<void> after(BackgroundTask task, Duration delay);

  /// Runs [task] about every hour, keeping a schedule already there.
  Future<void> hourly(BackgroundTask task);

  Future<void> cancel(BackgroundTask task);
}
