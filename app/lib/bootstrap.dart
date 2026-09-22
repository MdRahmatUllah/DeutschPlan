import 'dart:async';
import 'dart:io';

import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/theme/glass_capability.dart';
import 'package:deutschplan/core/theme/theme_mode.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/db/content_update.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:material_ui/material_ui.dart' show Brightness;
import 'package:path_provider/path_provider.dart';

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
    required this.content,
    required this.settings,
    required this.glass,
    required this.contentVersion,
    required this.contentChange,
    required this.themeMode,
    required this.isFirstRun,
    required this.elapsed,
  });

  final AppDatabase db;
  final ContentDao content;
  final SettingsRepository settings;
  final GlassCapability glass;

  /// `meta.content_version` of the course now attached.
  final String contentVersion;

  /// What this launch installed, or null when the course was already current.
  /// Today's update card reads it (BR-CONTENT-03).
  final ContentChange? contentChange;

  /// The mode `AppTheme` should build. Resolved here so the first frame is
  /// already the right one — a frame of the wrong theme is the thing
  /// FR-S1-01 exists to prevent.
  final DpMode themeMode;

  /// How long the whole thing took. FR-S1-02 budgets 500 ms warm, 2 s on a
  /// first run; this is what a test and a bug report measure against.
  final Duration elapsed;

  /// True when this launch installed the course for the first time.
  ///
  /// Read from whether the file was there before, not from the change: a
  /// first install reports an empty change (there is nothing to diff against)
  /// and so does an update that moved no words, so the change cannot tell
  /// them apart. Splash's caption — "Preparing your course · first start
  /// only" — is the thing that would be wrong.
  final bool isFirstRun;

  Future<void> dispose() async {
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

/// FR-S1-01, in the order the doc gives it.
///
/// Open user.db (creating the schema if absent) · copy content.db when the
/// version differs · attach it · load settings · resolve the theme. All of it
/// before `runApp`, so nothing here is ever waiting behind a frame.
///
/// It does not throw. A failure comes back as [BootstrapFailed] carrying the
/// step and whatever opened, because the error screen has to offer *Retry* and
/// *Export progress* rather than an exception the learner cannot read.
///
/// [openDatabase], [platformBrightness] and [glass] exist for tests;
/// everything else here is real I/O, and a test that faked the database would
/// be testing its own fake.
Future<BootstrapResult> bootstrap({
  AppDatabase Function()? openDatabase,
  Brightness platformBrightness = Brightness.light,
  GlassCapability? glass,
}) async {
  final watch = Stopwatch()..start();

  // Only set once the file is genuinely open. Constructing an `AppDatabase`
  // touches nothing, so handing that object to the failure would have the
  // error screen offer *Export progress* for a database that never opened —
  // a button that cannot do what it says.
  AppDatabase? opened;
  var step = BootstrapStep.database;

  try {
    final db = (openDatabase ?? AppDatabase.open)();
    // The first statement is what actually opens the file and runs the
    // migration; constructing the object does not. Failing here rather than
    // on the first screen's query is the whole point.
    await db.fileSchemaVersion();
    opened = db;

    step = BootstrapStep.content;
    final content = ContentDao(db);
    final updater = ContentUpdater(db, content);

    // Whether the course is already installed, asked before `attach` — which
    // is what writes it on a first run, so afterwards the answer is always
    // yes.
    final firstRun = !(await content.installedFile()).existsSync();

    // Attach first: on a first run this is what writes the asset to disk, and
    // the updater's replace path detaches before it renames.
    await content.attach();
    final change = await updater.runIfNeeded();
    final version = await content.version();

    step = BootstrapStep.settings;
    final settings = SettingsRepository(db);
    await settings.load();

    // Glass asks the platform whether it will blur. It is awaited here rather
    // than left running into the first frame: main.dart started it unawaited
    // to protect the launch budget, and the right place for the round trip is
    // a function that is already off the frame.
    final capability = glass ?? (GlassCapability()..startFrameWatchdog());
    await capability.queryPlatform();

    final mode = settings
        .read(SettingKeys.themeMode)
        .resolve(platformBrightness);

    watch.stop();
    return BootstrapReady(
      Bootstrap(
        db: db,
        content: content,
        settings: settings,
        glass: capability,
        contentVersion: version,
        contentChange: change,
        themeMode: mode,
        isFirstRun: firstRun,
        elapsed: watch.elapsed,
      ),
    );
  } on Object catch (error, stackTrace) {
    watch.stop();
    return BootstrapFailed(
      BootstrapFailure(
        step: step,
        error: error,
        stackTrace: stackTrace,
        db: opened,
      ),
    );
  }
}

/// Deletes the installed course so the next [bootstrap] copies it again.
///
/// What *Retry* on the error screen does when the failure was [
/// BootstrapStep.content]: a half-written or corrupt copy is the likeliest
/// cause, and retrying against the same bad file would fail the same way for
/// ever. The learner's data is in user.db and is not touched.
Future<void> resetInstalledContent({Directory? support}) async {
  final root = support ?? await getApplicationSupportDirectory();
  for (final name in <String>[
    ContentDao.fileName,
    ContentUpdater.manifestFile,
  ]) {
    final file = File('${root.path}/$name');
    if (file.existsSync()) file.deleteSync();
  }
}
