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
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/data/repositories/rating_service.dart';
import 'package:deutschplan/data/repositories/search_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/services/model_downloads.dart';
import 'package:deutschplan/services/notification_permission.dart';
import 'package:deutschplan/services/tts/system_tts.dart';
import 'package:deutschplan/services/tts/tts_engine.dart';
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
///
/// **It does not tick.** [clock] is a *function*, so watching it never fires
/// again — this is computed once and cached until something invalidates it,
/// and a session left open across midnight would read yesterday. That is
/// deliberate: a provider that rebuilt every second would rebuild every screen
/// watching it. `state-management.md` puts the midnight refresh on
/// `todayPlan`, which listens for app resume and re-runs `openDay`; anything
/// else that must survive midnight watches that, not this.
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

  /// The platform's current brightness.
  ///
  /// Seeded by `main` from `PlatformDispatcher` at startup — the default here
  /// is only what a test gets before it says otherwise, and leaving it as the
  /// app's real starting value would show a dark phone a light first frame.
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

/// The two languages: the meaning printed beside each German word, and the
/// app's own. Kept together because S2 sets both from one choice.
///
/// A notifier for the same reason as [Theme]: the root reads [UiLanguage] for
/// the locale, and a write has to reach it on the next frame, not the next
/// launch.
@Riverpod(keepAlive: true)
class Languages extends _$Languages {
  @override
  ({MeaningLanguage meaning, UiLanguage ui}) build() {
    final settings = ref.watch(settingsProvider);
    return (
      meaning: settings.read(SettingKeys.meaningLanguage),
      ui: settings.read(SettingKeys.uiLanguage),
    );
  }

  /// S2 page 2. Written as it is tapped rather than held for the finish with
  /// the plan: the page promises it sets the app language, and the next page
  /// is the proof. A language is not a plan setting, so #92's one transaction
  /// is not where it belongs.
  ///
  /// Invalidated before the disk write finishes, not after: `write` puts the
  /// value in memory first, so the tick and the new locale land on the next
  /// frame instead of waiting on SQLite.
  Future<void> chooseMeaning(MeaningLanguage meaning) {
    final settings = ref.read(settingsProvider);
    final written = Future.wait(<Future<void>>[
      settings.write(SettingKeys.meaningLanguage, meaning),
      settings.write(SettingKeys.uiLanguage, meaning.uiLanguage),
    ]);
    ref.invalidateSelf();
    return written;
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

/// Rating a word: FSRS joined to the writes (#78).
///
/// Takes [clock] rather than reading `DateTime.now()`, so a test that moves the
/// clock moves which study day a rating lands on.
@riverpod
RatingService ratingService(Ref ref) => RatingService(
  ref.watch(appDatabaseProvider),
  ref.watch(settingsProvider),
  ref.watch(planRepositoryProvider),
  ref.watch(wordRepositoryProvider),
  ref.watch(clockProvider),
);

/// Kept alive: it caches the parsed manifest, and the onboarding draft —
/// itself kept alive — reaches it through [modelDownloads].
@Riverpod(keepAlive: true)
ModelRepository modelRepository(Ref ref) =>
    ModelRepository(ref.watch(settingsProvider));

// --- Services --------------------------------------------------------------
//
// `project-structure.md`: platform plugins behind small interfaces, so a test
// can put a fake in the scope instead of a method channel that is not there.

/// The phone's German voice. `tts` — engine selection and fallback — is
/// #153's, and will sit in front of this.
@riverpod
TtsEngine systemTts(Ref ref) => SystemTts();

/// Kept alive with the onboarding draft that asks it (FR-S2-05). Stateless,
/// so there is nothing to hold on to but the object.
@Riverpod(keepAlive: true)
NotificationPermission notificationPermission(Ref ref) =>
    const PlatformNotificationPermission();

/// Kept alive for the same reason: page 5's draft queues the voice (FR-S2-06).
@Riverpod(keepAlive: true)
ModelDownloads modelDownloads(Ref ref) =>
    BackgroundModelDownloads(ref.watch(modelRepositoryProvider));
