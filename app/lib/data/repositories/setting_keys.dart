/// The settings catalogue: every key the app stores, its type and its default.
///
/// The table in `docs/02-data/user-database.md` is the source. `SettingKeys.all`
/// is checked against it by a test, so a key added here and not there — or the
/// other way round — fails rather than drifting.
///
/// The stored form is always text, because the `settings` table is
/// `(key, value)` and nothing else. Typing lives here so no call site parses a
/// string, which is where the wrong default and the silent `int.parse` failure
/// come from.
library;

/// One setting: its key, its type, its default, and how it is stored.
///
/// `T` may be nullable, for the two keys the doc leaves blank.
sealed class SettingKey<T> {
  const SettingKey(this.name, this.defaultValue);

  /// The `settings.key` column value. Snake case, matching the doc.
  final String name;

  final T defaultValue;

  /// Returns [defaultValue] when the stored text cannot be read as a `T`.
  ///
  /// A settings row is not worth crashing the app over: a bad value means one
  /// preference resets, while throwing here would mean nothing opens at all.
  T decode(String raw);

  /// `null` means "store nothing" — the row is deleted instead.
  String? encode(T value);

  @override
  String toString() => 'SettingKey($name)';
}

class IntSetting extends SettingKey<int> {
  const IntSetting(super.name, super.defaultValue, [this.range, this.choices]);

  /// The values allowed: `settings.md`'s stepper, or a bound no screen
  /// sets. The one source for M3 and for an import's check (#820).
  final ({int min, int max})? range;

  /// Where only some values in [range] are offered (`doc_autodelete_days`:
  /// never, 30, 90 or 365 days), those; an import refuses the rest (#820).
  final Set<int>? choices;

  @override
  int decode(String raw) => int.tryParse(raw) ?? defaultValue;

  @override
  String encode(int value) => '$value';
}

/// Stored as `1` / `0`, which is what SQLite and the doc both use.
class BoolSetting extends SettingKey<bool> {
  const BoolSetting(super.name, super.defaultValue);

  @override
  bool decode(String raw) => switch (raw) {
    '1' || 'true' => true,
    '0' || 'false' => false,
    _ => defaultValue,
  };

  @override
  String encode(bool value) => value ? '1' : '0';
}

class DoubleSetting extends SettingKey<double> {
  const DoubleSetting(super.name, super.defaultValue);

  @override
  double decode(String raw) => double.tryParse(raw) ?? defaultValue;

  @override
  String encode(double value) => '$value';
}

/// A free-text value. Empty is stored as an absent row, so clearing a name and
/// never having set one read back the same.
class StringSetting extends SettingKey<String?> {
  const StringSetting(super.name, [super.defaultValue]);

  @override
  String? decode(String raw) => raw.isEmpty ? defaultValue : raw;

  @override
  String? encode(String? value) =>
      value == null || value.isEmpty ? null : value;
}

/// One of a closed set, stored by its wire name.
///
/// The wire name is written out rather than taken from `Enum.name` so renaming
/// a Dart constant cannot silently orphan every learner's stored value.
class EnumSetting<E extends Enum> extends SettingKey<E> {
  const EnumSetting(super.name, super.defaultValue, this.values, this.wire);

  final List<E> values;

  /// The stored text for each value.
  final Map<E, String> wire;

  @override
  E decode(String raw) {
    for (final value in values) {
      if (wire[value] == raw) return value;
    }
    return defaultValue;
  }

  @override
  String encode(E value) => wire[value]!;
}

/// A time of day, stored as `HH:mm`.
///
/// A record rather than `TimeOfDay`: the data layer has no business importing a
/// widget library, and this is only two numbers.
typedef Clock = ({int hour, int minute});

class TimeSetting extends SettingKey<Clock> {
  const TimeSetting(super.name, super.defaultValue);

  @override
  Clock decode(String raw) {
    final parts = raw.split(':');
    if (parts.length != 2) return defaultValue;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return defaultValue;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return defaultValue;
    }
    return (hour: hour, minute: minute);
  }

  @override
  String encode(Clock value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

/// A local calendar date, stored as `YYYY-MM-DD`.
///
/// Local, not UTC: `coding-standards.md` splits plan dates from timestamps
/// because a study day is a local day.
class DateSetting extends SettingKey<DateTime?> {
  const DateSetting(String name) : super(name, null);

  @override
  DateTime? decode(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return defaultValue;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  @override
  String? encode(DateTime? value) {
    if (value == null) return null;
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

/// The app's own language. German strings live in content, not in the ARBs.
///
/// Its own setting, apart from the meaning languages (#1078): Polish screens
/// with English meanings is what the two exist for. A new language is a value
/// here, its code in [SettingKeys.uiLanguage], its locale and name in
/// `ui_language_locale.dart`, and its ARB.
enum UiLanguage { english, bangla, polish, russian }

/// `system` follows the platform; the other three are the modes in
/// `theming.md`.
enum ThemeModeSetting { system, light, dark, glass }

/// `supertonic` is the bundled on-device voice; `system` is the platform's.
///
/// `…Setting`, like [ThemeModeSetting]: `TtsEngine` is the speech interface in
/// `services/tts/`, and one name for both made every file that needs the two
/// an ambiguous import.
enum TtsEngineSetting { supertonic, system }

/// Every key the app stores.
abstract final class SettingKeys {
  // Daily plan. BR-PLAN-08: changing the first three is visible at once but
  // only reaches the plan from tomorrow, because the plan engine generates
  // from last_planned_date + 1 and never rewrites today.
  static const dailyNew = IntSetting('daily_new', 7, (min: 1, max: 50));
  static const reviseCount = IntSetting('revise_count', 10, (min: 0, max: 100));
  static const sentenceCount = IntSetting('sentence_count', 3, (
    min: 0,
    max: 20,
  ));

  /// No screen sets it (#820): a year either way.
  static const sentenceRepeatGapDays = IntSetting(
    'sentence_repeat_gap_days',
    14,
    (min: 0, max: 365),
  );

  /// A bitmask of weekdays, Monday the lowest bit. 127 is all seven, and
  /// BR-PLAN-01 keeps one at least.
  static const studyDaysMask = IntSetting('study_days_mask', 127, (
    min: 1,
    max: 127,
  ));

  /// #377: the study-days masks over time, a JSON list of `{from, mask}`,
  /// so a past day keeps the mask it had. Empty until they first change.
  static const studyDaysHistory = StringSetting('study_days_history');

  static const reminderEnabled = BoolSetting('reminder_enabled', false);
  static const reminderTime = TimeSetting('reminder_time', (
    hour: 19,
    minute: 30,
  ));
  static const reminderOnlyWhenDue = BoolSetting(
    'reminder_only_when_due',
    true,
  );

  static const autoAdvance = BoolSetting('auto_advance', true);
  static const pauseNewWhenBacklog = BoolSetting(
    'pause_new_when_backlog',
    false,
  );

  /// No screen sets it (#820). A year at most: the plan engine walks every
  /// missed day in it, inside `openDay`'s write lock.
  static const backlogCatchupDays = IntSetting('backlog_catchup_days', 30, (
    min: 0,
    max: 365,
  ));

  // Revision.
  static const desiredRetention = DoubleSetting('desired_retention', 0.90);
  static const doneStabilityDays = IntSetting('done_stability_days', 7, (
    min: 3,
    max: 60,
  ));
  static const swipeToRate = BoolSetting('swipe_to_rate', false);

  /// FR-R2-04 (#363): all-learned quizzes also ask the learner's own words.
  static const quizCustomWords = BoolSetting('quiz_custom_words', false);

  // Display.
  /// #1081: the meaning languages by code (`course_languages`), a primary and
  /// an optional secondary (empty: none). Before the primary is written,
  /// English then Bangla: `meaningChoiceOf`. They replaced
  /// `meaning_language` (#1096: `retiredMeaningLanguage`).
  static const meaningPrimary = StringSetting('meaning_primary');
  static const meaningSecondary = StringSetting('meaning_secondary');
  static const uiLanguage = EnumSetting<UiLanguage>(
    'ui_language',
    UiLanguage.english,
    UiLanguage.values,
    <UiLanguage, String>{
      UiLanguage.english: 'en',
      UiLanguage.bangla: 'bn',
      UiLanguage.polish: 'pl',
      UiLanguage.russian: 'ru',
    },
  );
  static const themeMode = EnumSetting<ThemeModeSetting>(
    'theme_mode',
    ThemeModeSetting.system,
    ThemeModeSetting.values,
    <ThemeModeSetting, String>{
      ThemeModeSetting.system: 'system',
      ThemeModeSetting.light: 'light',
      ThemeModeSetting.dark: 'dark',
      ThemeModeSetting.glass: 'glass',
    },
  );
  static const showPronBn = BoolSetting('show_pron_bn', true);

  /// #1122: the learner has opened a pronunciation key once, so the line
  /// under the guide is a small ⓘ from then on.
  static const pronKeySeen = BoolSetting('pron_key_seen', false);

  // Audio.
  static const ttsEngine = EnumSetting<TtsEngineSetting>(
    'tts_engine',
    TtsEngineSetting.supertonic,
    TtsEngineSetting.values,
    <TtsEngineSetting, String>{
      TtsEngineSetting.supertonic: 'supertonic',
      TtsEngineSetting.system: 'system',
    },
  );
  static const ttsVoice = StringSetting('tts_voice', 'Anna');
  static const ttsSpeed = DoubleSetting('tts_speed', 1.0);
  static const autoplayHeadword = BoolSetting('autoplay_headword', true);
  static const autoplayExample = BoolSetting('autoplay_example', false);
  static const listeningQuestions = BoolSetting('listening_questions', true);

  /// M4's *Wi-Fi only* (FR-M4-01, #156): model downloads wait for Wi-Fi.
  static const modelsWifiOnly = BoolSetting('models_wifi_only', true);

  // Exams.
  static const examUnlockPercent = IntSetting('exam_unlock_percent', 90, (
    min: 50,
    max: 100,
  ));
  static const examPassPercent = IntSetting('exam_pass_percent', 60, (
    min: 50,
    max: 90,
  ));
  static const examTimerDefault = BoolSetting('exam_timer_default', true);

  /// The timer of the mock last begun: L11's switch writes it on *Begin
  /// exam*, and L12 reads it whenever it opens, fresh or resumed, so the
  /// choice survives Resume and process death (#129, #130).
  static const examTimer = BoolSetting('exam_timer', true);

  /// The study days today was planned with (#147, BR-PLAN-08): M5's change
  /// is tomorrow's, not today's. 0 until the engine records one.
  static const plannedStudyDays = IntSetting('planned_study_days', 0);

  /// The `doc_daily_cap` today was planned with (BR-PLAN-11, -08): M3's
  /// change is tomorrow's, not today's. -1 until the engine records one.
  static const plannedDocCap = IntSetting('planned_doc_cap', -1);

  /// M6's "Last export: 20 Sep" (#148): the day of the last export the
  /// share sheet took. Unset until the first.
  static const lastExport = DateSetting('last_export');

  /// BR-RATE-01 (#1237): Play's review card has been asked for, after the
  /// first passed mock exam, so it never is again. All the app keeps of it.
  static const playReviewAsked = BoolSetting('play_review_asked', false);

  // Translation.
  static const mtEnabled = BoolSetting('mt_enabled', false);

  // No default: the doc leaves both blank.
  static const lastPlannedDate = DateSetting('last_planned_date');

  /// FR-T1-06: the contextual cards the learner dismissed, as a JSON list of
  /// their ids — `pause`, `voice`, `exams:A2.1`. Empty when unset.
  static const dismissedCards = StringSetting('dismissed_cards');

  /// FR-S2-03: the coach mark on Today's primary button is "one-time". Set
  /// when it has been shown, and never cleared — restart setup is not a
  /// first run.
  static const coachMarkSeen = BoolSetting('coach_mark_seen', false);

  /// FR-R1-04: the last ten searches, newest first, as a JSON list. Empty
  /// when unset.
  static const recentSearches = StringSetting('recent_searches');
  static const learnerName = StringSetting('learner_name');

  /// Learn from your documents (#1219, `document-matcher.md`), as the owner
  /// decided (#1220): BR-PLAN-11's new words a day from documents (#1231),
  /// whether a document keeps its pages' images, when one deletes itself
  /// (0: never), and whether D2 lists the words the matcher thinks known.
  static const docDailyCap = IntSetting('doc_daily_cap', 5, (min: 0, max: 20));
  static const docSaveImages = BoolSetting('doc_save_images', true);
  static const docAutodeleteDays = IntSetting(
    'doc_autodelete_days',
    0,
    (min: 0, max: 365),
    <int>{0, 30, 90, 365},
  );
  static const docShowProbablyKnown = BoolSetting(
    'doc_show_probably_known',
    false,
  );

  /// Every key, in the order `user-database.md` lists them.
  static const List<SettingKey<Object?>> all = <SettingKey<Object?>>[
    dailyNew,
    reviseCount,
    sentenceCount,
    sentenceRepeatGapDays,
    studyDaysMask,
    studyDaysHistory,
    reminderEnabled,
    reminderTime,
    reminderOnlyWhenDue,
    autoAdvance,
    pauseNewWhenBacklog,
    backlogCatchupDays,
    desiredRetention,
    doneStabilityDays,
    swipeToRate,
    quizCustomWords,
    meaningPrimary,
    meaningSecondary,
    uiLanguage,
    themeMode,
    showPronBn,
    pronKeySeen,
    ttsEngine,
    ttsVoice,
    ttsSpeed,
    autoplayHeadword,
    autoplayExample,
    examUnlockPercent,
    examPassPercent,
    examTimerDefault,
    mtEnabled,
    listeningQuestions,
    modelsWifiOnly,
    lastPlannedDate,
    coachMarkSeen,
    dismissedCards,
    recentSearches,
    learnerName,
    examTimer,
    lastExport,
    playReviewAsked,
    plannedStudyDays,
    plannedDocCap,
    docDailyCap,
    docSaveImages,
    docAutodeleteDays,
    docShowProbablyKnown,
  ];
}
