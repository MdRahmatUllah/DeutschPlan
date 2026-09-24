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

import 'package:deutschplan/data/repositories/sentence_store.dart';
import 'package:deutschplan/domain/sentence_picker.dart';
import 'package:deutschplan/data/db/content_update.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/theme/theme_mode.dart';
import 'package:deutschplan/domain/fsrs.dart';
import 'package:deutschplan/domain/plan_engine.dart';
import 'package:deutschplan/domain/quiz_builder.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/backup_repository.dart';
import 'package:deutschplan/data/repositories/exam_repository.dart';
import 'package:deutschplan/data/repositories/exam_run_service.dart';
import 'package:deutschplan/data/repositories/grammar_repository.dart';
import 'package:deutschplan/data/repositories/model_repository.dart';
import 'package:deutschplan/data/repositories/plan_repository.dart';
import 'package:deutschplan/data/repositories/plan_store.dart';
import 'package:deutschplan/data/repositories/quiz_run_service.dart';
import 'package:deutschplan/data/repositories/quiz_store.dart';
import 'package:deutschplan/data/repositories/rating_service.dart';
import 'package:deutschplan/data/repositories/search_repository.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/setup_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/services/model_downloads.dart';
import 'package:deutschplan/services/notification_permission.dart';
import 'package:deutschplan/services/tts/system_tts.dart';
import 'package:deutschplan/services/tts/tts_engine.dart';
import 'package:deutschplan/data/repositories/translation_repository.dart';
import 'package:deutschplan/data/repositories/word_actions.dart';
import 'package:deutschplan/services/translation/translator.dart';
import 'package:material_ui/material_ui.dart' show Brightness;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// BR-CONTENT-03's record of course updates, for Today's update card.
@riverpod
ContentUpdater contentUpdater(Ref ref) => ContentUpdater(
  ref.watch(appDatabaseProvider),
  ref.watch(contentDaoProvider),
);

@riverpod
WordRepository wordRepository(Ref ref) =>
    WordRepository(ref.watch(appDatabaseProvider), ref.watch(settingsProvider));

/// Every step and the learner's place in it: L1's tiles, the Me card
/// (`state-management.md`: Stream, Learn/Me).
@riverpod
Stream<List<StepProgress>> stepProgress(Ref ref) =>
    ref.watch(wordRepositoryProvider).watchStepProgress();

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

/// W1's actions (FR-W1-01…03), each with its undo.
@riverpod
WordActions wordActions(Ref ref) => WordActions(
  ref.watch(appDatabaseProvider),
  ref.watch(ratingServiceProvider),
  DriftPlanStore(ref.watch(appDatabaseProvider), ref.watch(settingsProvider)),
);

/// Rating a grammar topic: FSRS joined to `grammar_state` (FR-L4-01,
/// FR-L15-03).
@riverpod
GrammarRatingService grammarRatingService(Ref ref) => GrammarRatingService(
  ref.watch(grammarRepositoryProvider),
  ref.watch(settingsProvider),
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

/// On-device translation: nothing yet. #154 puts the Hy-MT model here, and
/// until it does `mt_enabled` cannot be on.
@riverpod
Translator translator(Ref ref) => const UnavailableTranslator();

/// W1's *Translate* (FR-W1-05): the translator through `translation_cache`.
@riverpod
TranslationRepository translationRepository(Ref ref) => TranslationRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(translatorProvider),
  ref.watch(clockProvider),
);

/// Opens a web page in an in-app browser tab: R1's Duden · DWDS · Wiktionary
/// · Linguee · Google chips (FR-R1-06). The app makes no request of its own
/// (BR-PRIV-01); the browser does, because the learner tapped.
typedef OpenWeb = Future<bool> Function(Uri page);

@riverpod
OpenWeb openWeb(Ref ref) =>
    (page) => launchUrl(page, mode: LaunchMode.inAppBrowserView);

/// The phone's German voice: S2's preview (FR-S2-06) and `tts.md`'s fallback.
/// Kept alive because the plugin reports playback to one instance only.
@Riverpod(keepAlive: true)
TtsEngine systemTts(Ref ref) {
  final tts = SystemTts();
  ref.onDispose(tts.dispose);
  return tts;
}

/// The voice every speaker uses (`tts.md`). #153 puts `TtsService` — engine
/// choice and the fallback — here, so no speaker changes when it lands.
@Riverpod(keepAlive: true)
TtsEngine tts(Ref ref) => ref.watch(systemTtsProvider);

/// Whether [tts] can speak German now: a speaker is slashed when it cannot
/// (accessibility-performance.md). Asked afresh whenever a screen starts
/// watching it, and after a failed [TtsEngine.speak].
@riverpod
Future<bool> ttsAvailable(Ref ref) => ref.watch(ttsProvider).isAvailable();

/// Kept alive with the onboarding draft that asks it (FR-S2-05). Stateless,
/// so there is nothing to hold on to but the object.
@Riverpod(keepAlive: true)
NotificationPermission notificationPermission(Ref ref) =>
    const PlatformNotificationPermission();

/// Kept alive for the same reason: page 5's draft queues the voice (FR-S2-06).
@Riverpod(keepAlive: true)
ModelDownloads modelDownloads(Ref ref) =>
    BackgroundModelDownloads(ref.watch(modelRepositoryProvider));

@riverpod
SetupRepository setupRepository(Ref ref) => SetupRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(settingsProvider),
);

/// The plan engine over the real store, with the learner's settings as they
/// stand when it is read. Auto-disposing, so the next read sees a setting
/// changed in between — BR-PLAN-08's "from the next day" is the engine's to
/// enforce, not a stale instance's.
@riverpod
PlanEngine planEngine(Ref ref) {
  final settings = ref.watch(settingsProvider);
  return PlanEngine(
    store: DriftPlanStore(ref.watch(appDatabaseProvider), settings),
    reviseCount: settings.read(SettingKeys.reviseCount),
    backlogCatchupDays: settings.read(SettingKeys.backlogCatchupDays),
    autoAdvance: settings.read(SettingKeys.autoAdvance),
    pauseNewWhenBacklog: settings.read(SettingKeys.pauseNewWhenBacklog),
  );
}

/// The drift side of the sentence picker, shared by the picker and Today's
/// count of rated sentences.
@riverpod
DriftSentenceStore sentenceStore(Ref ref) =>
    DriftSentenceStore(ref.watch(appDatabaseProvider));

/// `docs/03-domain/sentences.md`: the day's practice sentences.
@riverpod
SentencePicker sentencePicker(Ref ref) {
  final settings = ref.watch(settingsProvider);
  return SentencePicker(
    ref.watch(sentenceStoreProvider),
    count: settings.read(SettingKeys.sentenceCount),
    gapDays: settings.read(SettingKeys.sentenceRepeatGapDays),
  );
}

/// `docs/03-domain/quiz-engine.md` (#81): builds a quiz from `QuizArgs`. The
/// runner (L8) and the exam generator build through it.
@riverpod
QuizBuilder quizBuilder(Ref ref) => QuizBuilder(
  DriftQuizStore(ref.watch(wordRepositoryProvider)),
  fsrs: Fsrs(
    desiredRetention: ref
        .watch(settingsProvider)
        .read(SettingKeys.desiredRetention),
  ),
);

/// L12's data (#130): the paper, its answers and time, and the submit.
@riverpod
ExamRunService examRunService(Ref ref) => ExamRunService(
  ref.watch(examRepositoryProvider),
  ref.watch(settingsProvider),
  ref.watch(clockProvider),
);

/// L8's data (#123): the quiz built, recorded and finished.
@riverpod
QuizRunService quizRunService(Ref ref) => QuizRunService(
  ref.watch(quizBuilderProvider),
  ref.watch(examRepositoryProvider),
  ref.watch(ratingServiceProvider),
  ref.watch(wordRepositoryProvider),
  ref.watch(clockProvider),
);

/// FR-S2-03's coach mark on Today's primary button: whether it still has to
/// be shown. "One-time" — once shown it is marked, and never again, restart
/// setup included.
@riverpod
class CoachMark extends _$CoachMark {
  @override
  bool build() => !ref.watch(settingsProvider).read(SettingKeys.coachMarkSeen);

  /// Called the first frame it is on screen. Shown is enough: a learner who
  /// never taps it has still seen it, and it does not come back next launch.
  ///
  /// Only the flag — the mark already on screen stays until [dismiss].
  /// Rebuilding here would take it away the frame after it appeared.
  Future<void> markShown() =>
      ref.read(settingsProvider).write(SettingKeys.coachMarkSeen, true);

  /// A tap on it: gone for this visit, and — [markShown] having run — for good.
  void dismiss() => state = false;
}

/// The learner's name, trimmed; null when there is none. M1's header edits it
/// and T1's greeting says it, so a rename reaches both at once.
@riverpod
class LearnerName extends _$LearnerName {
  @override
  String? build() {
    final settings = ref.watch(settingsProvider);
    // Followed, not read once: Settings, import and reset write the name
    // too, and Today's tab stays alive to show it.
    final changes = settings.changes
        .where((key) => key == SettingKeys.learnerName)
        .listen((_) => state = _clean(settings.read(SettingKeys.learnerName)));
    ref.onDispose(changes.cancel);
    return _clean(settings.read(SettingKeys.learnerName));
  }

  /// M1's *edit name*. A blank name clears it. The state is set here as well
  /// as by the write's change, so it is new the moment this returns.
  Future<void> rename(String name) async {
    final clean = _clean(name);
    await ref.read(settingsProvider).write(SettingKeys.learnerName, clean);
    state = clean;
  }

  static String? _clean(String? name) {
    final trimmed = name?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
