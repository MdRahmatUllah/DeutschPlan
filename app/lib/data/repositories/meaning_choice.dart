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

  /// Today's three, as `meaning_language` stored them: *English* is English
  /// alone, *Bangla* Bangla alone, and *Both* English then Bangla.
  factory MeaningChoice.of(MeaningLanguage old) => switch (old) {
    MeaningLanguage.english => const MeaningChoice('en'),
    MeaningLanguage.bangla => const MeaningChoice('bn'),
    MeaningLanguage.both => const MeaningChoice('en', 'bn'),
  };

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

/// The learner's [MeaningChoice]. `meaning_primary` and `meaning_secondary`
/// once written; before, read from `meaning_language`, so an upgrade, a
/// backup from an older build and a reset need no step of their own (#1081).
MeaningChoice meaningChoiceOf(SettingsRepository settings) {
  final primary = settings.read(SettingKeys.meaningPrimary);
  if (primary == null || primary.isEmpty) {
    return MeaningChoice.of(settings.read(SettingKeys.meaningLanguage));
  }
  final secondary = settings.read(SettingKeys.meaningSecondary);
  return MeaningChoice(
    primary,
    secondary == null || secondary.isEmpty || secondary == primary
        ? null
        : secondary,
  );
}

/// Writes [choice]. `meaning_language` too, as near as its three come, for
/// what still reads it: a backup opened by an older build.
Future<void> writeMeaningChoice(
  SettingsRepository settings,
  MeaningChoice choice,
) => Future.wait(<Future<void>>[
  settings.write(SettingKeys.meaningPrimary, choice.primary),
  settings.write(SettingKeys.meaningSecondary, choice.secondary),
  settings.write(SettingKeys.meaningLanguage, choice.nearestOld),
]);

extension on MeaningChoice {
  MeaningLanguage get nearestOld => has('en') && hasBangla
      ? MeaningLanguage.both
      : hasBangla
      ? MeaningLanguage.bangla
      : MeaningLanguage.english;
}
