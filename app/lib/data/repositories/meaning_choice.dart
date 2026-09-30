import 'package:flutter/foundation.dart' show immutable;
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';

/// #1081: the languages a German word is explained in: a [primary], shown
/// first and asked in the quizzes and exams, and an optional [secondary]
/// shown after it. Codes of the course's languages (`course_languages`,
/// #1080): `en`, `bn`, and whatever a later workbook adds.
///
/// Apart from the app's own language (`ui_language`): the owner, #1092.
@immutable
class MeaningChoice {
  const MeaningChoice(this.primary, [this.secondary])
    : assert(secondary != primary, 'a secondary differs from the primary');

  /// Before the learner chooses (a first run, Reset everything): English,
  /// then Bangla.
  static const MeaningChoice fallback = MeaningChoice('en', 'bn');

  final String primary;
  final String? secondary;

  /// The chosen languages, primary first.
  List<String> get languages => <String>[primary, ?secondary];

  bool has(String code) => primary == code || secondary == code;

  /// #1077: the Bangla pronunciation shows only while Bangla is chosen.
  bool get hasBangla => has('bn');

  @override
  bool operator ==(Object other) =>
      other is MeaningChoice &&
      other.primary == primary &&
      other.secondary == secondary;

  @override
  int get hashCode => Object.hash(primary, secondary);

  @override
  String toString() => 'MeaningChoice(${languages.join(' + ')})';
}

/// The learner's [MeaningChoice]: `meaning_primary` and `meaning_secondary`,
/// or [MeaningChoice.fallback] before either is written.
MeaningChoice meaningChoiceOf(SettingsRepository settings) {
  final primary = settings.read(SettingKeys.meaningPrimary);
  if (primary == null || primary.isEmpty) return MeaningChoice.fallback;
  final secondary = settings.read(SettingKeys.meaningSecondary);
  return MeaningChoice(
    primary,
    secondary == null || secondary.isEmpty || secondary == primary
        ? null
        : secondary,
  );
}

/// Writes [choice].
Future<void> writeMeaningChoice(
  SettingsRepository settings,
  MeaningChoice choice,
) => Future.wait(<Future<void>>[
  settings.write(SettingKeys.meaningPrimary, choice.primary),
  settings.write(SettingKeys.meaningSecondary, choice.secondary),
]);

/// The setting `meaning_primary` and `meaning_secondary` replaced (#1081),
/// retired by #1096. An install from before them still has it, and so does
/// its backup: [SettingsRepository.load] and an import read it into them
/// once ([retiredMeaningKeys]).
const String retiredMeaningLanguage = 'meaning_language';

/// What `meaning_language` stored as the settings that replaced it: `en` is
/// English alone, `bn` Bangla alone, and `both`, its default (and so
/// anything else), English then Bangla.
Map<String, String> retiredMeaningKeys(String stored) {
  final choice = switch (stored) {
    'en' => const MeaningChoice('en'),
    'bn' => const MeaningChoice('bn'),
    _ => MeaningChoice.fallback,
  };
  return <String, String>{
    SettingKeys.meaningPrimary.name: choice.primary,
    SettingKeys.meaningSecondary.name: ?choice.secondary,
  };
}
