import 'dart:io' show File, Platform;

import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/reminder_scheduler.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/today/today_providers.dart';
import 'package:deutschplan/features/today/today_view.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/l10n/ui_language_locale.dart';
import 'package:deutschplan/services/background_work.dart';
import 'package:deutschplan/services/reminder_notifications.dart';
import 'package:deutschplan/services/widget_snapshot.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqlite3/sqlite3.dart' show OpenMode, sqlite3;
import 'package:workmanager/workmanager.dart';

part 'background_tasks.g.dart';

/// The reminder's plain words, in [language]: what it says until
/// `reminder_compose` writes the day's plan into it.
ReminderCopy reminderCopy(UiLanguage language) {
  final l10n = lookupAppLocalizations(language.locale);
  return (
    title: l10n.reminderTitle,
    body: l10n.reminderBody,
    channel: l10n.reminderChannel,
  );
}

/// The reminder's schedule over [container]'s settings: the app's, and a
/// background task's.
ReminderScheduler remindersFor(
  ProviderContainer container,
  ReminderNotifications notifications,
  BackgroundWork work,
) => ReminderScheduler(
  container.read(settingsProvider),
  notifications,
  container.read(clockProvider),
  reminderCopy,
  work,
);

/// How long from [now] until the next 00:05, when `plan_pregenerate` runs.
Duration untilPregenerate(DateTime now) {
  final tonight = DateTime(now.year, now.month, now.day, 0, 5);
  final next = tonight.isAfter(now)
      ? tonight
      : DateTime(now.year, now.month, now.day + 1, 0, 5);
  return next.difference(now);
}

/// Queues the tasks no setting moves: tonight's `plan_pregenerate` and the
/// hourly `widget_refresh`. `reminder_compose` follows the reminder's
/// settings, through [ReminderScheduler].
Future<void> startBackgroundWork(BackgroundWork work, DateTime now) async {
  await work.init();
  await work.after(BackgroundTask.planPregenerate, untilPregenerate(now));
  await work.hourly(BackgroundTask.widgetRefresh);
}

/// Runs [task] against [container]'s database (`notifications-widget.md`).
///
/// Each one-off queues its next run last: on Android that replaces the run
/// in progress, which has nothing left to do by then.
///
/// ponytail: "nothing" but the database's close, which the stopped engine
/// may skip; WAL recovers a connection left open, so nothing is lost.
/// Queue the next run after `withBackgroundDatabase` if the close ever
/// matters.
Future<void> runBackgroundTask(
  BackgroundTask task,
  ProviderContainer container, {
  required ReminderNotifications notifications,
  required BackgroundWork work,
  required WidgetStore widgets,
}) async {
  final reminders = remindersFor(container, notifications, work);
  switch (task) {
    case BackgroundTask.planPregenerate:
      await container
          .read(planEngineProvider)
          .openDay(container.read(todayProvider));
      // FR-X1-01: the widget rewritten at midnight, from the new day.
      await refreshWidget(container, widgets);
      // The week of reminders rolls on for a learner who doesn't open the
      // app, and today's compose is queued with it.
      await reminders.sync();
      await work.after(task, untilPregenerate(container.read(clockProvider)()));
    case BackgroundTask.reminderCompose:
      await reminders.composeAfter(
        await composeReminder(container, notifications),
      );
    case BackgroundTask.widgetRefresh:
      // Hourly, for the word of the day; the app writes it after every
      // session (`followWidget`).
      await refreshWidget(container, widgets);
  }
}

/// Writes today's reminder from the plan, or cancels it when the day is done
/// or nothing is due and the learner asked for `reminder_only_when_due`.
/// Returns today's reminder time, which the next compose is queued after.
Future<DateTime> composeReminder(
  ProviderContainer container,
  ReminderNotifications notifications,
) async {
  final settings = container.read(settingsProvider);
  final now = container.read(clockProvider)();
  final time = settings.read(SettingKeys.reminderTime);
  final at = DateTime(now.year, now.month, now.day, time.hour, time.minute);
  // Off, or it has rung already: nothing of today's is left to write.
  if (!settings.read(SettingKeys.reminderEnabled) || !at.isAfter(now)) {
    return at;
  }
  final view = container.listen(todayViewProvider.future, (_, _) {});
  final text = container.listen(reminderBodyProvider.future, (_, _) {});
  try {
    final today = await view.read();
    if (!today.isStudyDay) {
      // No reminder on a rest day; one scheduled before the study days
      // changed goes.
      await notifications.cancelDay(at);
      return at;
    }
    final l10n = lookupAppLocalizations(
      settings.read(SettingKeys.uiLanguage).locale,
    );
    final body = await text.read();
    if (body != null) {
      await notifications.replace(at, (
        title: l10n.reminderTitle,
        body: body,
        channel: l10n.reminderChannel,
      ));
    } else if (settings.read(SettingKeys.reminderOnlyWhenDue)) {
      await notifications.cancelDay(at);
    }
    return at;
  } finally {
    view.close();
    text.close();
  }
}

/// Tonight's reminder text from today's plan, in the app's language
/// ([reminderText]); null when nothing is due. The one composer
/// `reminder_compose` and M5's preview share (FR-M5-03).
@riverpod
Future<String?> reminderBody(Ref ref) async {
  final settings = ref.watch(settingsProvider);
  final grammar = ref.watch(grammarRepositoryProvider);
  final today = await ref.watch(todayViewProvider.future);
  final topic = today.grammarDue.isEmpty
      ? null
      : await grammar.find(today.grammarDue.first);
  return reminderText(
    lookupAppLocalizations(settings.read(SettingKeys.uiLanguage).locale),
    today,
    grammar: topic?.topic.topic,
  );
}

/// "12 revisions · 7 new · about 9 min", and "Grammar due: [grammar]" on the
/// line below; null when nothing of the day's study is open. Sentences are
/// practice, not due.
String? reminderText(AppLocalizations l10n, TodayView view, {String? grammar}) {
  final revise = view.revise.open;
  final fresh = view.newToday.open;
  if (revise + fresh + view.grammarDue.length == 0) return null;
  final line = <String>[
    if (revise > 0) l10n.reminderRevisions(revise),
    if (fresh > 0) l10n.reminderNew(fresh),
    l10n.reminderMinutes(view.estimateMinutes),
  ].join(' · ');
  return grammar == null ? line : '$line\n${l10n.reminderGrammar(grammar)}';
}

/// [BackgroundWork] on `workmanager`: WorkManager on Android, BGTaskScheduler
/// on iOS.
///
/// iOS decides when its tasks run; "no sooner than" is all it promises. A
/// compose that runs late leaves the plain reminder, which is still right.
class WorkmanagerWork implements BackgroundWork {
  const WorkmanagerWork();

  @override
  Future<void> init() => Workmanager().initialize(backgroundDispatcher);

  @override
  Future<void> after(BackgroundTask task, Duration delay) => Platform.isIOS
      // A one-off on iOS is `beginBackgroundTask`, which lives only as long
      // as the app does; a processing task outlives it.
      ? Workmanager().registerProcessingTask(
          task.id,
          task.id,
          initialDelay: delay,
        )
      : Workmanager().registerOneOffTask(
          task.id,
          task.id,
          initialDelay: delay,
          existingWorkPolicy: ExistingWorkPolicy.replace,
        );

  @override
  Future<void> hourly(BackgroundTask task) =>
      Workmanager().registerPeriodicTask(
        task.id,
        task.id,
        frequency: const Duration(hours: 1),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );

  @override
  Future<void> cancel(BackgroundTask task) =>
      Workmanager().cancelByUniqueName(task.id);
}

/// Where the platform starts a background task: an engine of its own, with
/// no app around it.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((name, _) async {
    final task = BackgroundTask.byId(name);
    if (task == null) return true;
    debugPrint('background: ${task.id}');
    try {
      await withBackgroundDatabase((container) async {
        final notifications = PlatformReminderNotifications();
        // A tap is the app's to handle, in its own engine.
        await notifications.init((_) {});
        await runBackgroundTask(
          task,
          container,
          notifications: notifications,
          work: const WorkmanagerWork(),
          widgets: const HomeWidgetStore(),
        );
      });
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('background ${task.id}: $error\n$stackTrace');
      // WorkManager retries it, later.
      return false;
    }
  });
}

/// Whether user.db at [file] is at this build's schema, read without drift.
///
/// A task never migrates: after an update the app does it at its next
/// start, and a task that opened the file first would run the migration on
/// a connection of its own, beside an app that may start and run it too.
/// Tonight's task skips, and tomorrow's finds the file migrated.
bool atCurrentSchema(File file) {
  if (!file.existsSync()) return false;
  final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
  try {
    return db.userVersion == AppDatabase.latestSchemaVersion;
  } finally {
    db.close();
  }
}

/// user.db with the course attached and the settings loaded: what a task
/// needs of `bootstrap`, without the router, the theme or a course install.
///
/// A connection of its own ([AppDatabase.open]'s `shared` off): the app's
/// streams don't hear what a task writes, which is only `openDay`'s rows,
/// and the app's own `openDay` finds them.
Future<void> withBackgroundDatabase(
  Future<void> Function(ProviderContainer container) run,
) async {
  // drift_flutter's file for `AppDatabase.open`'s name, `user`.
  final support = await getApplicationSupportDirectory();
  if (!atCurrentSchema(File('${support.path}/user.sqlite'))) {
    debugPrint('background: user.db is not at this schema; left for the app');
    return;
  }
  final db = AppDatabase.open(shared: false);
  try {
    final content = ContentDao(db);
    // Never started: installing the course is the app's first start's job.
    if (!(await content.installedFile()).existsSync()) return;
    await content.attach();
    final settings = SettingsRepository(db);
    await settings.load();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
      ],
    );
    try {
      await run(container);
    } finally {
      container.dispose();
      await settings.dispose();
    }
  } finally {
    await db.close();
  }
}
