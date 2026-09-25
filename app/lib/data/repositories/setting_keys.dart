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
  const IntSetting(super.name, super.defaultValue);

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

/// Which language a word's meaning is shown in.
enum MeaningLanguage { english, bangla, both }

/// The app's own language. German strings live in content, not in the ARBs.
enum UiLanguage { english, bangla }

/// S2 page 2: "This also sets the app language."
///
/// *Both* gives English, the `ui_language` default: the app can only speak
/// one, and *Both* lists English first. ponytail: a guess the docs leave
/// open — if Bangla-first readers pick *Both*, this is the line to change.
extension MeaningLanguageUi on MeaningLanguage {
  UiLanguage get uiLanguage => switch (this) {
    MeaningLanguage.bangla => UiLanguage.bangla,
    MeaningLanguage.english || MeaningLanguage.both => UiLanguage.english,
  };
}

/// `system` follows the platform; the other three are the modes in
/// `theming.md`.
enum ThemeModeSetting { system, light, dark, glass }

/// `supertonic` is the bundled on-device voice; `system` is the platform's.
///
/// `…Setting`, like [ThemeModeSetting]: `TtsEngine` is the speech interface in
/// `services/tts/`, and one name for both made every file that needs the two
/// an ambiguous import.
enum TtsEngineSetting { supertonic, system }

/// The translation model's quantisation. ADR 9 defaults to 1.25-bit.
enum MtVariant { q1_25, q2_5, fp16 }

/// Every key the app stores.
abstract final class SettingKeys {
  // Daily plan. BR-PLAN-08: changing the first three is visible at once but
  // only reaches the plan from tomorrow, because the plan engine generates
  // from last_planned_date + 1 and never rewrites today.
  static const dailyNew = IntSetting('daily_new', 7);
  static const reviseCount = IntSetting('revise_count', 10);
  static const sentenceCount = IntSetting('sentence_count', 3);
  static const sentenceRepeatGapDays = IntSetting(
    'sentence_repeat_gap_days',
    14,
  );

  /// A bitmask of weekdays, Monday the lowest bit. 127 is all seven.
  static const studyDaysMask = IntSetting('study_days_mask', 127);

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
  static const backlogCatchupDays = IntSetting('backlog_catchup_days', 30);

  // Revision.
  static const desiredRetention = DoubleSetting('desired_retention', 0.90);
  static const doneStabilityDays = IntSetting('done_stability_days', 7);
  static const swipeToRate = BoolSetting('swipe_to_rate', false);

  /// FR-R2-04 (#363): all-learned quizzes also ask the learner's own words.
  static const quizCustomWords = BoolSetting('quiz_custom_words', false);

  // Display.
  static const meaningLanguage = EnumSetting<MeaningLanguage>(
    'meaning_language',
    MeaningLanguage.both,
    MeaningLanguage.values,
    <MeaningLanguage, String>{
      MeaningLanguage.english: 'en',
      MeaningLanguage.bangla: 'bn',
      MeaningLanguage.both: 'both',
    },
  );
  static const uiLanguage = EnumSetting<UiLanguage>(
    'ui_language',
    UiLanguage.english,
    UiLanguage.values,
    <UiLanguage, String>{UiLanguage.english: 'en', UiLanguage.bangla: 'bn'},
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

  // Exams.
  static const examUnlockPercent = IntSetting('exam_unlock_percent', 90);
  static const examPassPercent = IntSetting('exam_pass_percent', 60);
  static const examTimerDefault = BoolSetting('exam_timer_default', true);

  /// The timer of the mock last begun: L11's switch writes it on *Begin
  /// exam*, and L12 reads it whenever it opens, fresh or resumed, so the
  /// choice survives Resume and process death (#129, #130).
  static const examTimer = BoolSetting('exam_timer', true);

  /// The study days today was planned with (#147, BR-PLAN-08): M5's change
  /// is tomorrow's, not today's. 0 until the engine records one.
  static const plannedStudyDays = IntSetting('planned_study_days', 0);

  /// M6's "Last export: 20 Sep" (#148): the day of the last export the
  /// share sheet took. Unset until the first.
  static const lastExport = DateSetting('last_export');

  // Translation.
  static const mtEnabled = BoolSetting('mt_enabled', false);
  static const mtVariant = EnumSetting<MtVariant>(
    'mt_variant',
    MtVariant.q1_25,
    MtVariant.values,
    <MtVariant, String>{
      MtVariant.q1_25: 'q1_25',
      MtVariant.q2_5: 'q2_5',
      MtVariant.fp16: 'fp16',
    },
  );

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

  /// Every key, in the order `user-database.md` lists them.
  static const List<SettingKey<Object?>> all = <SettingKey<Object?>>[
    dailyNew,
    reviseCount,
    sentenceCount,
    sentenceRepeatGapDays,
    studyDaysMask,
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
    meaningLanguage,
    uiLanguage,
    themeMode,
    showPronBn,
    ttsEngine,
    ttsVoice,
    ttsSpeed,
    autoplayHeadword,
    autoplayExample,
    examUnlockPercent,
    examPassPercent,
    examTimerDefault,
    mtEnabled,
    mtVariant,
    listeningQuestions,
    lastPlannedDate,
    coachMarkSeen,
    dismissedCards,
    recentSearches,
    learnerName,
    examTimer,
    lastExport,
    plannedStudyDays,
  ];
}
