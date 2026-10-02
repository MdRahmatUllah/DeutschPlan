/// The app's core providers. `state-management.md`'s provider map.
///
/// Which providers are `keepAlive` is not a matter of taste:
/// `state-management.md` names each one and why (#596). The four every
/// screen leans on:
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
/// `architecture_test.dart` holds the set to exactly the doc's, read out of
/// it rather than restated here.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:material_ui/material_ui.dart' show Brightness;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/theme/theme_mode.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/db/content_update.dart';
import 'package:sogda/data/repositories/backup_repository.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/data/repositories/exam_repository.dart';
import 'package:sogda/data/repositories/exam_result_service.dart';
import 'package:sogda/data/repositories/exam_run_service.dart';
import 'package:sogda/data/repositories/grammar_repository.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/model_repository.dart';
import 'package:sogda/data/repositories/plan_repository.dart';
import 'package:sogda/data/repositories/plan_store.dart';
import 'package:sogda/data/repositories/progress_repository.dart';
import 'package:sogda/data/repositories/quiz_run_service.dart';
import 'package:sogda/data/repositories/quiz_store.dart';
import 'package:sogda/data/repositories/rating_service.dart';
import 'package:sogda/data/repositories/reset_repository.dart';
import 'package:sogda/data/repositories/search_repository.dart';
import 'package:sogda/data/repositories/sentence_store.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/setup_repository.dart';
import 'package:sogda/data/repositories/synthesis_cache.dart';
import 'package:sogda/data/repositories/translation_repository.dart';
import 'package:sogda/data/repositories/word_actions.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/domain/fsrs.dart';
import 'package:sogda/domain/plan_engine.dart';
import 'package:sogda/domain/quiz_builder.dart';
import 'package:sogda/domain/sentence_picker.dart';
import 'package:sogda/services/device_storage.dart';
import 'package:sogda/services/exam_recorder.dart';
import 'package:sogda/services/model_downloads.dart';
import 'package:sogda/services/notification_permission.dart';
import 'package:sogda/services/translation/hymt_translator.dart';
import 'package:sogda/services/translation/translator.dart';
import 'package:sogda/services/tts/supertonic_tts.dart';
import 'package:sogda/services/tts/system_tts.dart';
import 'package:sogda/services/tts/tts_engine.dart';
import 'package:sogda/services/tts/tts_service.dart';
import 'package:url_launcher/url_launcher.dart';

part 'app_providers.g.dart';

/// The open database. Supplied by `bootstrap()` through an override, because
/// opening it is I/O and FR-S1-01 says all of that happens before the app's
/// first frame.
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

/// The settings the screens read and write: the app's own. A provider of its
/// own so a test that only needs a screen drawn can give it settings without
/// a database (#511).
@riverpod
SettingsRepository settingsSource(Ref ref) => ref.watch(settingsProvider);

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
/// (FR-M3-02) and the write has to reach every frame at once. Named with its
/// suffix, which the provider drops (`themeProvider`): a class `Theme` made
/// material's `Theme` ambiguous in a file that imported both (#698).
@Riverpod(keepAlive: true)
class ThemeNotifier extends _$ThemeNotifier {
  @override
  SgMode build() {
    final settings = ref.watch(settingsProvider);
    // Followed, not read once (#672): a Replace import and Reset everything
    // write the setting too, not only [choose], and `reload` announces it.
    _followSettings(ref, settings, const <SettingKey<Object?>>{
      SettingKeys.themeMode,
    });
    return settings.read(SettingKeys.themeMode).resolve(_platformBrightness);
  }

  /// The platform's current brightness.
  ///
  /// Told by `BootstrapHost` when the app starts and on every switch after
  /// (#644). The default here is only what a test gets before it says
  /// otherwise, and leaving it as the app's real starting value would show a
  /// dark phone a light first frame.
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

/// Whether the theme setting follows the phone's light/dark (*System*). The
/// root reads it for `ThemeMode.system`, as it reads Glass from [Theme].
///
/// A provider of its own, and followed rather than read once (#649): [Theme]'s
/// mode can't carry it. *Dark* chosen on a dark phone resolves to the mode
/// *System* already had, so nothing rebuilt, and the app went on following
/// the phone despite the choice. Settings, import and reset all write it.
@riverpod
class ThemeFollowsPlatform extends _$ThemeFollowsPlatform {
  @override
  bool build() {
    final settings = ref.watch(settingsProvider);
    bool follows() => settings.read(SettingKeys.themeMode).followsPlatform;
    final changes = settings.changes
        .where((key) => key == SettingKeys.themeMode)
        .listen((_) => state = follows());
    ref.onDispose(changes.cancel);
    return follows();
  }
}

/// The two languages: the meaning printed beside each German word, and the
/// app's own. Kept together because the root and the pickers read both; each
/// is set on its own (#1078): S2's page 1 and M3 the app's, page 2 and M3 the
/// meaning's.
///
/// A notifier for the same reason as [Theme]: the root reads [UiLanguage] for
/// the locale, and a write has to reach it on the next frame, not the next
/// launch.
@Riverpod(keepAlive: true)
class Languages extends _$Languages {
  @override
  ({MeaningChoice meaning, UiLanguage ui}) build() {
    final settings = ref.watch(settingsProvider);
    // Followed, not read once (#672): a Replace import writes both, and
    // Reset everything the meaning language, not only this notifier.
    _followSettings(ref, settings, const <SettingKey<Object?>>{
      SettingKeys.meaningPrimary,
      SettingKeys.meaningSecondary,
      SettingKeys.uiLanguage,
    });
    return (
      meaning: meaningChoiceOf(settings),
      ui: settings.read(SettingKeys.uiLanguage),
    );
  }

  /// S2 page 2. Written as it is tapped rather than held for the finish with
  /// the plan: a language is not a plan setting, so #92's one transaction is
  /// not where it belongs.
  ///
  /// It leaves the app language alone (#1078): page 1 chose it, and Polish
  /// screens with English meanings stay Polish.
  ///
  /// Invalidated before the disk write finishes, not after: `write` puts the
  /// value in memory first, so the tick and the new locale land on the next
  /// frame instead of waiting on SQLite.
  ///
  /// The Bangla pronunciation follows too: off for a learner who chose no
  /// Bangla, who may not read it, as #339 did for the quiz's direction
  /// (#396, #527). M3's switch changes it after.
  Future<void> chooseMeaning(MeaningChoice meaning) {
    final settings = ref.read(settingsProvider);
    final written = Future.wait(<Future<void>>[
      writeMeaningChoice(settings, meaning),
      settings.write(SettingKeys.showPronBn, meaning.hasBangla),
    ]);
    ref.invalidateSelf();
    return written;
  }

  /// Settings (M3) sets the meaning apart from the app's language: Bangla
  /// meanings in an English app is what its rows are for.
  Future<void> setMeaning(MeaningChoice meaning) {
    final written = writeMeaningChoice(ref.read(settingsProvider), meaning);
    ref.invalidateSelf();
    return written;
  }

  Future<void> setUi(UiLanguage ui) {
    final written = ref
        .read(settingsProvider)
        .write(SettingKeys.uiLanguage, ui);
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

/// BR-CONTENT-02: the uids whose meaning a course update changed in the last
/// seven days, for the *Updated* chip on W1's header and T2's back.
// ponytail: autoDispose, so read again whenever something starts watching it
// (W1, each T2 card after the last listener dropped): one small query, not
// live. Updates land only at launch, so a window that closes while W1 or a
// session is open shows until the provider is read again.
@riverpod
Future<Set<String>> recentlyUpdated(Ref ref) => ref
    .watch(contentUpdaterProvider)
    .recentlyUpdated(ref.watch(clockProvider)());

/// Not retried: content.db is read-only and changes only at launch
/// (BR-CONTENT-03), so a read of it that failed would fail again.
Duration? _readOnce(int retryCount, Object error) => null;

/// #1081: the meaning languages the course ships, in its order: what S2's
/// page 2 and M3 offer. [baseLanguages] until it is read.
@Riverpod(retry: _readOnce)
Future<List<CourseLanguageName>> courseLanguages(Ref ref) async =>
    <CourseLanguageName>[
      for (final l
          in await ref.watch(contentDaoProvider).courseLanguageList().get())
        (code: l.code, ownName: l.ownName),
    ];

/// #1128: the category names in the primary meaning language. English's
/// are the course's own and need no read; a course that can't be read shows
/// English, as one without the language does.
@riverpod
Future<CategoryNames> categoryNames(Ref ref) async {
  final primary = ref.watch(languagesProvider).meaning.primary;
  if (primary == 'en') return CategoryNames.none;
  final dao = ref.watch(contentDaoProvider);
  try {
    return CategoryNames(<String, String>{
      for (final row in await dao.categoryNamesIn(primary).get())
        row.english: row.name,
    });
  } on Object {
    return CategoryNames.none;
  }
}

/// #1081: every meaning the course ships, read once per database.
@Riverpod(retry: _readOnce)
Future<CourseMeanings> courseMeanings(Ref ref) =>
    loadCourseMeanings(ref.watch(contentDaoProvider));

/// #1081: the learner's meaning languages ([Languages]) and the course's
/// meanings in them, which every screen showing a meaning reads.
///
/// Bangla's meaning and guide are the word's own row, and so is English's
/// meaning, so the course's are read only for a language beyond them or for
/// English's guide (#1082, #1150); until they are, a word shows English and
/// the guide the row has.
@riverpod
Meanings meanings(Ref ref) {
  final choice = ref.watch(languagesProvider).meaning;
  if (!_needsCourse(choice)) return Meanings(choice);
  return Meanings(
    choice,
    ref.watch(courseMeaningsProvider).value ?? CourseMeanings.none,
  );
}

/// [meanings] once the course's are read, for a reader that takes one value
/// and goes: the home widget's background refresh (#1119). A course that
/// can't be read shows English, as [meanings] does until it is.
@riverpod
Future<Meanings> meaningsLoaded(Ref ref) async {
  final choice = ref.watch(languagesProvider).meaning;
  if (!_needsCourse(choice)) return Meanings(choice);
  final course = ref.watch(courseMeaningsProvider.future);
  try {
    return Meanings(choice, await course);
  } on Object {
    return Meanings(choice);
  }
}

/// Whether [choice] reads anything from the course's meaning tables: a
/// language beyond the word's own English and Bangla, or English, whose
/// pronunciation guide is there alone (#1082, #1150).
// ponytail: loadCourseMeanings reads every language's rows, so an English
// learner loads Russian's and Polish's too (15,708 rows, about 130 ms off the
// UI isolate on 5558, #1119). Filter its query by the chosen languages when a
// later language makes that load heavy.
bool _needsCourse(MeaningChoice choice) =>
    choice.languages.any((lang) => lang != 'bn');

/// Whether [choice] has a meaning beyond the word's own English and Bangla:
/// all the quiz reads from the course (#1120).
bool _needsCourseMeanings(MeaningChoice choice) =>
    !choice.languages.every((lang) => lang == 'en' || lang == 'bn');

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

/// M7 · Reset (#149).
@riverpod
ResetRepository resetRepository(Ref ref) => ResetRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(settingsProvider),
);

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

/// Hy-MT2 (#154, `translation.md`): kept alive, since loading the model takes
/// seconds and its ~1.1 GB is mapped once. It answers nothing while
/// `mt_enabled` is off or the model isn't on the phone.
@Riverpod(keepAlive: true)
HyMtTranslator hymtTranslator(Ref ref) {
  final translator = HyMtTranslator(
    models: ref.watch(modelRepositoryProvider),
    settings: ref.watch(settingsProvider),
    downloads: ref
        .watch(modelDownloadsProvider)
        .watch(ModelRepository.translationModel),
  );
  ref.onDispose(() => unawaited(translator.dispose()));
  return translator;
}

/// On-device translation (`translation.md`): Hy-MT2 through llamadart.
@riverpod
Translator translator(Ref ref) => ref.watch(hymtTranslatorProvider);

/// W1's *Translate* (FR-W1-05): the translator through `translation_cache`.
@riverpod
TranslationRepository translationRepository(Ref ref) => TranslationRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(translatorProvider),
  ref.watch(clockProvider),
);

/// [text] from [from] into [to], through [translationRepository] (cached):
/// T5's word sheet and R1's *Translate* (#154). Null with translation off or
/// no model on the phone.
@riverpod
Future<String?> translationOf(Ref ref, String text, String from, String to) =>
    ref
        .watch(translationRepositoryProvider)
        .translate(text, from: from, to: to);

/// Opens a web page in an in-app browser tab: R1's Duden · DWDS · Wiktionary
/// · Linguee · Google chips (FR-R1-06). The app makes no request of its own
/// (BR-PRIV-01); the browser does, because the learner tapped. False when
/// it couldn't: `launchUrl` throws on a phone with no browser, and every
/// link goes through here (#692 ME-13).
typedef OpenWeb = Future<bool> Function(Uri page);

@riverpod
OpenWeb openWeb(Ref ref) => (page) async {
  try {
    return await launchUrl(page, mode: LaunchMode.inAppBrowserView);
  } on Object catch (error) {
    debugPrint('web: $error');
    return false;
  }
};

/// The phone's German voice: S2's preview (FR-S2-06) and `tts.md`'s fallback.
/// Kept alive because the plugin reports playback to one instance only.
@Riverpod(keepAlive: true)
TtsEngine systemTts(Ref ref) {
  final tts = SystemTts();
  ref.onDispose(tts.dispose);
  return tts;
}

/// Supertonic 3, once its model is downloaded (#152): the `supertonic`
/// engine #153's service chooses. Kept alive because its four ONNX sessions
/// take seconds to open, and the cache and player are one of each.
@Riverpod(keepAlive: true)
TtsEngine supertonicTts(Ref ref) {
  final tts = SupertonicTts(
    models: ref.watch(modelRepositoryProvider),
    settings: ref.watch(settingsProvider),
    // A change of the denoising steps is a change of every clip (#436).
    cache: SynthesisCache(
      version: 'supertonic3 · ${OrtSupertonicModel.steps} steps',
    ),
    downloads: ref
        .watch(modelDownloadsProvider)
        .watch(ModelRepository.voiceModel),
  );
  // About 400 MB of sessions, a player and a stream: let go of on a rebuild.
  ref.onDispose(() => unawaited(tts.dispose()));
  return tts;
}

/// Supertonic 3 for [tts] (`tts.md`): [supertonicTts] (#152). [tts] falls
/// back to the phone's voice whenever it can't speak, and a test that wants
/// Supertonic missing overrides this with null. Kept alive because [tts] is.
@Riverpod(keepAlive: true)
TtsEngine? supertonicVoice(Ref ref) => ref.watch(supertonicTtsProvider);

/// The voice every speaker uses (`tts.md`, #153): the engine `tts_engine`
/// chooses, the fallback and the one player. Kept alive because the player
/// and the once-a-session fallback toast outlive every screen.
@Riverpod(keepAlive: true)
TtsService tts(Ref ref) {
  final service = TtsService(
    ref.watch(systemTtsProvider),
    ref.watch(settingsProvider),
    supertonic: ref.watch(supertonicVoiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
}

/// What [tts] is sounding, for the speakers' playing and loading looks.
@riverpod
Stream<TtsPlayback> ttsPlayback(Ref ref) => ref.watch(ttsProvider).playback;

/// Whether [tts] can speak German now: a speaker is slashed when it cannot
/// (accessibility-performance.md). Asked afresh whenever a screen starts
/// watching it, and after a request that said nothing.
@riverpod
Future<bool> ttsAvailable(Ref ref) => ref.watch(ttsProvider).isAvailable();

/// Kept alive with the onboarding draft that asks it (FR-S2-05). Stateless,
/// so there is nothing to hold on to but the object.
@Riverpod(keepAlive: true)
NotificationPermission notificationPermission(Ref ref) =>
    const PlatformNotificationPermission();

/// The phone's free space: M4's storage card and its shortfall (#156).
@riverpod
DeviceStorage deviceStorage(Ref ref) => const PlatformDeviceStorage();

/// Kept alive for the same reason: page 5's draft queues the voice (FR-S2-06).
@Riverpod(keepAlive: true)
ModelDownloads modelDownloads(Ref ref) => BackgroundModelDownloads(
  ref.watch(modelRepositoryProvider),
  ref.watch(settingsProvider),
);

@riverpod
SetupRepository setupRepository(Ref ref) => SetupRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(settingsProvider),
);

/// The plan engine over the real store, with the learner's settings as they
/// stand. BR-PLAN-08's "from the next day" is the engine's to enforce, not a
/// stale instance's.
///
/// Rebuilt whenever a setting it holds is written (#342), by whichever
/// screen: auto-disposing isn't enough, because Today's tab stays mounted
/// and keeps it watched. A stale copy planned the catch-up days with T4's
/// old pause and walked them as paused, so they were lost.
@riverpod
PlanEngine planEngine(Ref ref) {
  final settings = ref.watch(settingsProvider);
  _followSettings(ref, settings, const <SettingKey<Object?>>{
    SettingKeys.reviseCount,
    SettingKeys.backlogCatchupDays,
    SettingKeys.autoAdvance,
    SettingKeys.pauseNewWhenBacklog,
  });
  return PlanEngine(
    store: DriftPlanStore(ref.watch(appDatabaseProvider), settings),
    reviseCount: settings.read(SettingKeys.reviseCount),
    backlogCatchupDays: settings.read(SettingKeys.backlogCatchupDays),
    autoAdvance: settings.read(SettingKeys.autoAdvance),
    pauseNewWhenBacklog: settings.read(SettingKeys.pauseNewWhenBacklog),
  );
}

/// Rebuilds [ref]'s provider when one of [keys], the settings it copies, is
/// written (#342). Its callers stay watched by Today's tab, which the shell
/// keeps mounted, so auto-disposing never gets them a fresh copy.
void _followSettings(
  Ref ref,
  SettingsRepository settings,
  Set<SettingKey<Object?>> keys,
) {
  final changes = settings.changes
      .where(keys.contains)
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(changes.cancel);
}

/// The drift side of the sentence picker, shared by the picker and Today's
/// count of rated sentences.
@riverpod
DriftSentenceStore sentenceStore(Ref ref) => DriftSentenceStore(
  ref.watch(appDatabaseProvider),
  // #1119: the translations in the primary meaning language.
  () => meaningChoiceOf(ref.read(settingsProvider)).primary,
);

/// `docs/03-domain/sentences.md`: the day's practice sentences.
@riverpod
SentencePicker sentencePicker(Ref ref) {
  final settings = ref.watch(settingsProvider);
  _followSettings(ref, settings, const <SettingKey<Object?>>{
    SettingKeys.sentenceCount,
    SettingKeys.sentenceRepeatGapDays,
  });
  return SentencePicker(
    ref.watch(sentenceStoreProvider),
    count: settings.read(SettingKeys.sentenceCount),
    gapDays: settings.read(SettingKeys.sentenceRepeatGapDays),
  );
}

/// `docs/03-domain/quiz-engine.md` (#81): builds a quiz from `QuizArgs`. The
/// runner (L8) and the exam generator build through it.
///
/// It copies two settings, so it follows them as the planner does (#342):
/// its consumers auto-dispose today, but a copy that outlives a write would
/// quiz in the old meaning languages (#698).
@riverpod
QuizBuilder quizBuilder(Ref ref) {
  final settings = ref.watch(settingsProvider);
  _followSettings(ref, settings, const <SettingKey<Object?>>{
    SettingKeys.desiredRetention,
    ..._meaningKeys,
  });
  return QuizBuilder(
    ref.watch(quizStoreProvider),
    fsrs: Fsrs(desiredRetention: settings.read(SettingKeys.desiredRetention)),
    languages: meaningChoiceOf(settings).languages,
  );
}

/// The quiz builder's words (#1120): with the course's meanings in the
/// learner's languages beyond English and Bangla, read only while one is
/// chosen, so a quiz in English or Bangla reads what it always has.
@riverpod
DriftQuizStore quizStore(Ref ref) {
  final settings = ref.watch(settingsProvider);
  _followSettings(ref, settings, _meaningKeys);
  return DriftQuizStore(
    ref.watch(wordRepositoryProvider),
    settings,
    ref.watch(contentDaoProvider),
    _needsCourseMeanings(meaningChoiceOf(settings))
        ? ref.watch(courseMeaningsProvider.future)
        : null,
  );
}

/// The settings a [MeaningChoice] is read from.
const Set<SettingKey<Object?>> _meaningKeys = <SettingKey<Object?>>{
  SettingKeys.meaningPrimary,
  SettingKeys.meaningSecondary,
};

/// M2's reads (#145): the days, the revision ratings, the totals.
@riverpod
ProgressRepository progressRepository(Ref ref) =>
    ProgressRepository(ref.watch(appDatabaseProvider));

/// L12's data (#130): the paper, its answers and time, and the submit.
@riverpod
ExamRunService examRunService(Ref ref) => ExamRunService(
  ref.watch(examRepositoryProvider),
  ref.watch(settingsProvider),
  ref.watch(clockProvider),
  ref.watch(modelRepositoryProvider),
);

/// L13's data (#135): the graded paper, the rubric re-grade and the missed
/// words into revision.
@riverpod
ExamResultService examResultService(Ref ref) => ExamResultService(
  ref.watch(examRepositoryProvider),
  ref.watch(settingsProvider),
  ref.watch(ratingServiceProvider),
  ref.watch(wordRepositoryProvider),
  ref.watch(modelRepositoryProvider),
);

/// L12's Speaking (#134): the microphone and the playback, while the task is
/// on screen.
@riverpod
ExamRecorder examRecorder(Ref ref) {
  final recorder = PlatformExamRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
}

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
