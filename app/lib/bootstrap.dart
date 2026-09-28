import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;
// `Override` is not in the main barrel in Riverpod 3.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/glass_capability.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/db/content_update.dart';
import 'package:sogda/data/repositories/exam_repository.dart';
import 'package:sogda/data/repositories/plan_repository.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/router/app_router.dart';
import 'package:sogda/router/route_guards.dart';
import 'package:sogda/router/routes.dart';

/// Which step of FR-S1-01 was running, so a failure can say what went wrong
/// in words the learner can act on.
enum BootstrapStep {
  /// Opening user.db, including any migration.
  database,

  /// Installing or updating the course.
  content,

  /// Reading the settings table into memory.
  settings,
}

/// Everything that has to exist before the first frame.
///
/// Handed to `runApp` whole rather than rebuilt from providers, because the
/// point of FR-S1-01 is that none of it is still happening when Today draws.
@immutable
class Bootstrap {
  const Bootstrap({
    required this.db,
    required this.settings,
    required this.glass,
    required this.router,
    required this.elapsed,
  });

  final AppDatabase db;
  final SettingsRepository settings;
  final GlassCapability glass;

  /// Built here and held for the life of the app.
  ///
  /// A `GoRouter` owns the navigation stack, so one rebuilt on every frame
  /// loses it — and one held in a static is shared by every instance, which
  /// makes two widget tests in a file share a history. Bootstrap is where the
  /// app's singletons are made, and it is also what will know the deep link
  /// to open with (#70).
  final GoRouter router;

  /// How long the whole thing took. FR-S1-02 budgets 500 ms warm, 2 s on a
  /// first run; this is what a test and a bug report measure against.
  final Duration elapsed;

  /// The overrides `ProviderScope` needs so nothing re-opens what this
  /// already opened.
  ///
  /// `appDatabaseProvider` and `settingsProvider` throw when they are read
  /// without one — a second `AppDatabase` over the same file is how a learner
  /// loses a rating to a race, and an unloaded `SettingsRepository` answers
  /// every read with a default.
  List<Override> get overrides => <Override>[
    appDatabaseProvider.overrideWithValue(db),
    settingsProvider.overrideWithValue(settings),
  ];

  /// Also the glass capability's frame watchdog: a retry's result that the
  /// app never took over kept listening to every frame (#686 ST-9).
  Future<void> dispose() async {
    glass.dispose();
    await settings.dispose();
    await db.close();
  }
}

/// A bootstrap that did not finish. FR-S1-03: a recoverable screen, never a
/// blank one.
@immutable
class BootstrapFailure {
  const BootstrapFailure({
    required this.step,
    required this.error,
    required this.stackTrace,
    required this.db,
    this.file,
    this.newer = false,
  });

  final BootstrapStep step;
  final Object error;
  final StackTrace stackTrace;

  /// The database, when it opened before the failure.
  ///
  /// Kept rather than closed, because FR-S1-03's error screen offers *Export
  /// progress* — and a learner whose course will not install still has every
  /// review they have ever done sitting in user.db. Throwing that away to
  /// tidy up is the one thing the error screen exists to avoid.
  final AppDatabase? db;

  /// Whether the learner's data can still be exported from here.
  bool get canExport => db != null;

  /// user.db itself, when it would not open (#619): a corrupt file, or one a
  /// newer build wrote. Nothing can export from it, but the file can still
  /// leave the phone, which is the learner's way out short of clearing the
  /// app's data.
  final File? file;

  /// Whether [file] was written by a newer build: its `user_version` is past
  /// this build's schema, and drift refuses to downgrade. Updating the app,
  /// not retrying, is what opens it.
  final bool newer;

  /// #803: the phone's storage is full: ENOSPC (errno 28, Android and iOS),
  /// or its message where the code is lost. Freeing space, then Retry, is
  /// the way out.
  bool get noSpace {
    final error = this.error;
    return error is FileSystemException &&
        (error.osError?.errorCode == 28 ||
            '${error.osError?.message}'.contains('No space left'));
  }

  Future<void> dispose() async => db?.close();
}

/// The result of [bootstrap]: one or the other, never both.
sealed class BootstrapResult {
  const BootstrapResult();
}

class BootstrapReady extends BootstrapResult {
  const BootstrapReady(this.bootstrap);
  final Bootstrap bootstrap;
}

class BootstrapFailed extends BootstrapResult {
  const BootstrapFailed(this.failure);
  final BootstrapFailure failure;
}

/// #803: about what a course install needs, in MB, as the error screen says
/// it: the bundled course (7.6 MB, 2026-09) and a margin. A test holds the
/// asset under it.
const int courseInstallMegabytes = 10;

/// How long the glass capability query may take before bootstrap gives up on
/// it. A slice of FR-S1-02's 500 ms, not the whole of it.
const Duration glassTimeout = Duration(milliseconds: 150);

/// FR-S1-01, in the order the doc gives it.
///
/// Open user.db (creating the schema if absent) · copy content.db when the
/// version differs · attach it · load settings. All of it before the app's
/// first frame, so nothing here is ever waiting behind one: `main` runs the
/// app first, and S1 shows while this runs. The theme is resolved from the
/// loaded settings by `themeProvider`, which `BootstrapHost` tells the
/// phone's brightness before the app's first frame (#644).
///
/// It does not throw. A failure comes back as [BootstrapFailed] carrying the
/// step and whatever opened, because the error screen has to offer *Retry* and
/// *Export progress* rather than an exception the learner cannot read.
///
/// [onUiLanguage] hears the learner's app language as soon as user.db is
/// open — before the content install, which on a first run is most of the
/// wait — so the splash already on screen can switch to it.
///
/// [onCourseUpdate] hears that an app update is about to copy its new course
/// in, so the splash can say so rather than "first start only" (#686 ST-9).
/// Never on a first start, whose copy the splash's own caption names.
///
/// [openDatabase] and [glass] exist for tests;
/// everything else here is real I/O, and a test that faked the database would
/// be testing its own fake.
Future<BootstrapResult> bootstrap({
  AppDatabase Function()? openDatabase,
  GlassCapability? glass,
  void Function(UiLanguage)? onUiLanguage,
  void Function()? onCourseUpdate,
}) async {
  final watch = Stopwatch()..start();

  // Only set once the file is genuinely open. Constructing an `AppDatabase`
  // touches nothing, so handing that object to the failure would have the
  // error screen offer *Export progress* for a database that never opened —
  // a button that cannot do what it says.
  AppDatabase? opened;
  AppDatabase? created;
  var step = BootstrapStep.database;

  try {
    final db = created = (openDatabase ?? AppDatabase.open)();
    // The first statement is what actually opens the file and runs the
    // migration; constructing the object does not. Failing here rather than
    // on the first screen's query is the whole point.
    await db.fileSchemaVersion();
    opened = db;

    // One row, not the settings step: FR-S1-01 keeps its order, and only the
    // splash needs this early.
    onUiLanguage?.call(
      await SettingsRepository.peek(db, SettingKeys.uiLanguage),
    );

    step = BootstrapStep.content;
    final content = ContentDao(db);
    final updater = ContentUpdater(db, content);

    // Whether the course is already installed, asked before `attach` — which
    // is what writes it on a first run, so afterwards the answer is always
    // yes. A first start's copy is the splash's own caption; only a course
    // that was there is being updated.
    final firstRun = !(await content.installedFile()).existsSync();

    // Attach first: on a first run this is what writes the asset to disk, and
    // the updater's replace path detaches before it renames.
    await content.attach();
    await updater.runIfNeeded(onCopy: firstRun ? null : onCourseUpdate);
    // Asked for what it checks: a course with no version fails the start.
    await content.version();
    await content.assertSearchable();

    step = BootstrapStep.settings;
    final settings = SettingsRepository(db);
    await settings.load();

    // Glass asks the platform whether it will blur. Awaited here rather than
    // left running into the first frame — but bounded, because a native side
    // that never answers would otherwise hold the app on the launch screen
    // for ever, which is the blank screen FR-S1-03 exists to prevent. The
    // defaults already say blur is fine, so giving up costs nothing.
    final capability = glass ?? (GlassCapability()..startFrameWatchdog());
    await capability.queryPlatform().timeout(glassTimeout, onTimeout: () {});

    final plan = PlanRepository(db);

    // `splash.md`: S1 "leads to S2 (no enrollment) · T1". The guards only
    // send an *enrolled* learner away from onboarding; nothing sent a new
    // one to it, so a fresh install opened on an empty Today and the learner
    // never saw setup at all.
    final router = buildRouter(
      initialLocation: await plan.hasEnrollment()
          ? '/today'
          : const OnboardingRoute(page: '1').location,
      guards: RouteGuards.of(exams: ExamRepository(db), plan: plan),
    );

    // After the enrolment read and the router: they are the start's too
    // (#686 ST-9).
    watch.stop();
    return BootstrapReady(
      Bootstrap(
        db: db,
        settings: settings,
        glass: capability,
        router: router,
        elapsed: watch.elapsed,
      ),
    );
  } on Object catch (error, stackTrace) {
    watch.stop();
    // #619: one that never opened is closed before its file is offered, so
    // no connection of ours is left to checkpoint the file mid-share.
    if (opened == null) await _closeQuietly(created);
    final file = opened == null ? await _userDbFile() : null;
    return BootstrapFailed(
      BootstrapFailure(
        step: step,
        error: error,
        stackTrace: stackTrace,
        db: opened,
        file: file,
        newer:
            file != null &&
            (AppDatabase.versionOf(file) ?? 0) >
                AppDatabase.latestSchemaVersion,
      ),
    );
  }
}

/// Closes a database that failed to open. Bounded, and never throws, as
/// [bootstrap] never does: the error screen must still come up.
Future<void> _closeQuietly(AppDatabase? db) async {
  try {
    await db?.close().timeout(const Duration(seconds: 2));
  } on Object {
    // Left open: the file is still offered, as it was before #619.
  }
}

/// user.db on disk, or null when there is none: a first start that failed
/// has nothing to save (#619). Never throws, as [bootstrap] never does.
Future<File?> _userDbFile() async {
  try {
    final file = await AppDatabase.file();
    return file.existsSync() ? file : null;
  } on Object {
    return null;
  }
}

/// Deletes the installed course so the next [bootstrap] copies it again.
///
/// What *Retry* on the error screen does when the failure was
/// [BootstrapStep.content]: a half-written or corrupt copy is the likeliest
/// cause, and retrying against the same bad file would fail the same way for
/// ever. The learner's data is in user.db and is not touched.
///
/// Never a course that still reads (#617): then something else failed, and
/// deleting it would only have the next start copy it again, or fail for
/// the space the copy needs.
Future<void> resetInstalledContent({Directory? support}) async {
  final root = support ?? await getApplicationSupportDirectory();
  if (ContentDao.readable(File('${root.path}/${ContentDao.fileName}'))) return;
  for (final name in <String>[
    ContentDao.fileName,
    ContentUpdater.manifestFile,
  ]) {
    final file = File('${root.path}/$name');
    if (file.existsSync()) file.deleteSync();
  }
}
