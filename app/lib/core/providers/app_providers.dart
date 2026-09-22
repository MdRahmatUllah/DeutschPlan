/// The app's core providers. `state-management.md`'s provider map.
///
/// Four things are `keepAlive`, and the list is not a matter of taste:
///
/// - **`appDatabase`** holds an open file and an attached course. Disposing it
///   between screens would close and reopen user.db on every navigation.
/// - **`settings`** is read *synchronously during `build`* — a theme, a
///   language, whether to autoplay — which is only possible because the table
///   is in memory. Rebuilding it would put an async gap back.
/// - **`clock`** is a function; disposing it would hand out a different one
///   and break the tests that override it.
/// - **`theme`** is what every frame reads.
///
/// Everything else auto-disposes, which is the default `@riverpod` gives.
/// `architecture_test.dart` holds the set to exactly this list, read out of
/// the doc rather than restated here.
library;

import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/theme/theme_mode.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/backup_repository.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/grammar_repository.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/data/repositories/search_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:material_ui/material_ui.dart' show Brightness;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_providers.g.dart';

/// The open database. Supplied by `bootstrap()` through an override, because
/// opening it is I/O and FR-S1-01 says all of that happens before `runApp`.
///
/// Reading it without that override throws rather than quietly opening a
/// second database — two `AppDatabase`s over one file is how a learner loses
/// a rating to a race.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) => throw UnimplementedError(
  'appDatabaseProvider must be overridden with the database bootstrap() '
  'opened. Reading it here would open a second connection to user.db.',
);

/// The settings, already loaded. Overridden by `bootstrap()` for the same
/// reason as the database: [SettingsRepository.read] throws until `load()` has
/// run, and that is a disk read.
@Riverpod(keepAlive: true)
SettingsRepository settings(Ref ref) => throw UnimplementedError(
  'settingsProvider must be overridden with the repository bootstrap() '
  'loaded. An unloaded one answers every read with a default, which looks to '
  'the learner like their settings reset.',
);

/// The one source of "now".
///
/// `state-management.md`: "`DateTime Function()`; overridden in tests for date
/// logic." A study day is a local day and the plan engine, the streak and the
/// FSRS scheduler all turn on which day it is — so a second clock somewhere
/// means two answers to "is this due", and only one of them is testable.
@Riverpod(keepAlive: true)
DateTime Function() clock(Ref ref) => DateTime.now;

/// Today, as a local date string. What `plan_items.plan_date` and
/// `word_state.due` are compared against.
///
/// Derived from [clock] rather than from `DateTime.now()` so a test that moves
/// the clock moves this too.
@riverpod
String today(Ref ref) {
  final now = ref.watch(clockProvider)();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

/// The mode `AppTheme` builds, kept in step with the setting.
///
/// A notifier rather than a derived value because Settings writes to it
/// (FR-M3-02) and the write has to reach every frame at once.
@Riverpod(keepAlive: true)
class Theme extends _$Theme {
  @override
  DpMode build() {
    final setting = ref.watch(settingsProvider).read(SettingKeys.themeMode);
    return setting.resolve(_platformBrightness);
  }

  /// The platform's current brightness. Read through the notifier so a test
  /// can drive it without a widget tree.
  Brightness _platformBrightness = Brightness.light;

  /// Called by Settings (FR-M3-02). An action on the notifier, not a write
  /// from a widget: `state-management.md` says widgets never write to
  /// repositories.
  Future<void> choose(ThemeModeSetting setting) async {
    await ref.read(settingsProvider).write(SettingKeys.themeMode, setting);
    ref.invalidateSelf();
  }

  /// Called when the platform's light/dark setting changes.
  ///
  /// Invalidated unconditionally, with no `if (followsPlatform)` in front of
  /// it: `build` re-reads the setting and resolves to the same mode for a
  /// learner who chose one, and Riverpod does not notify listeners when the
  /// value is unchanged. The guard was there first and planting showed it
  /// bought nothing — the tests that count rebuilds pass either way, because
  /// the suppression is Riverpod's, not ours.
  void platformBrightnessChanged(Brightness brightness) {
    _platformBrightness = brightness;
    ref.invalidateSelf();
  }
}

// --- Repositories ----------------------------------------------------------
//
// All auto-disposing. They hold no state of their own — each is a thin thing
// over the database, which is the one that is kept alive — so a screen that
// stops watching one costs nothing to rebuild.

@riverpod
ContentDao contentDao(Ref ref) => ContentDao(ref.watch(appDatabaseProvider));

@riverpod
WordRepository wordRepository(Ref ref) =>
    WordRepository(ref.watch(appDatabaseProvider), ref.watch(settingsProvider));

@riverpod
GrammarRepository grammarRepository(Ref ref) => GrammarRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(settingsProvider),
);

@riverpod
PlanRepository planRepository(Ref ref) =>
    PlanRepository(ref.watch(appDatabaseProvider));

@riverpod
ExamRepository examRepository(Ref ref) =>
    ExamRepository(ref.watch(appDatabaseProvider));

@riverpod
SearchRepository searchRepository(Ref ref) =>
    SearchRepository(ref.watch(contentDaoProvider));

@riverpod
BackupRepository backupRepository(Ref ref) =>
    BackupRepository(ref.watch(appDatabaseProvider));
