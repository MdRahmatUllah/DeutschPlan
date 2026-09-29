import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';

/// #1081: a primary meaning language and an optional secondary, by code.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() async {
    db = AppDatabase.memory();
    settings = SettingsRepository(db);
    await settings.load();
  });

  tearDown(() async {
    await settings.dispose();
    await db.close();
  });

  test('#1081 before either is written, the choice is meaning_language\'s: '
      'en + bn by default', () async {
    expect(meaningChoiceOf(settings), const MeaningChoice('en', 'bn'));
    for (final (old, choice) in <(MeaningLanguage, MeaningChoice)>[
      (MeaningLanguage.english, const MeaningChoice('en')),
      (MeaningLanguage.bangla, const MeaningChoice('bn')),
      (MeaningLanguage.both, const MeaningChoice('en', 'bn')),
    ]) {
      await settings.write(SettingKeys.meaningLanguage, old);
      expect(meaningChoiceOf(settings), choice, reason: '$old');
    }
  });

  test('#1081 a written choice reads back, a database later too', () async {
    for (final choice in const <MeaningChoice>[
      MeaningChoice('ru', 'en'),
      MeaningChoice('bn', 'en'),
      MeaningChoice('ru'),
      MeaningChoice('en', 'bn'),
    ]) {
      await writeMeaningChoice(settings, choice);
      expect(meaningChoiceOf(settings), choice);
      await settings.load();
      expect(meaningChoiceOf(settings), choice, reason: 'from the database');
    }
  });

  test('#1081 a choice keeps meaning_language as near as its three come, '
      'for an older build', () async {
    for (final (choice, old) in <(MeaningChoice, MeaningLanguage)>[
      (const MeaningChoice('bn', 'en'), MeaningLanguage.both),
      (const MeaningChoice('bn'), MeaningLanguage.bangla),
      (const MeaningChoice('ru', 'bn'), MeaningLanguage.bangla),
      (const MeaningChoice('ru'), MeaningLanguage.english),
      (const MeaningChoice('en'), MeaningLanguage.english),
    ]) {
      await writeMeaningChoice(settings, choice);
      expect(settings.read(SettingKeys.meaningLanguage), old, reason: '$choice');
    }
  });

  test('#1081 a secondary the same as the primary is none', () async {
    await settings.write(SettingKeys.meaningPrimary, 'ru');
    await settings.write(SettingKeys.meaningSecondary, 'ru');
    expect(meaningChoiceOf(settings), const MeaningChoice('ru'));
  });

  test('#1081 languages lists the primary first; hasBangla either', () {
    expect(const MeaningChoice('bn', 'en').languages, <String>['bn', 'en']);
    expect(const MeaningChoice('ru').languages, <String>['ru']);
    expect(const MeaningChoice('ru', 'bn').hasBangla, isTrue);
    expect(const MeaningChoice('en', 'ru').hasBangla, isFalse);
  });
}
