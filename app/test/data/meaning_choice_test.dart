import 'package:drift/drift.dart' show OrderingTerm;
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

  test('#1081 before either is written, English then Bangla', () {
    expect(meaningChoiceOf(settings), const MeaningChoice('en', 'bn'));
    expect(MeaningChoice.fallback, const MeaningChoice('en', 'bn'));
  });

  Future<List<Setting>> rows() => (db.select(
    db.settings,
  )..orderBy([(t) => OrderingTerm(expression: t.key)])).get();

  test("#1096 an install from before #1081: meaning_language is read once "
      'into the settings that replaced it, and deleted', () async {
    for (final (stored, choice) in <(String, MeaningChoice)>[
      ('en', const MeaningChoice('en')),
      ('bn', const MeaningChoice('bn')),
      ('both', const MeaningChoice('en', 'bn')),
      ('nonsense', const MeaningChoice('en', 'bn')),
    ]) {
      await db.customStatement('DELETE FROM settings');
      await db.customStatement(
        "INSERT INTO settings (key, value) VALUES ('meaning_language', ?)",
        <Object?>[stored],
      );
      await settings.load();
      expect(meaningChoiceOf(settings), choice, reason: stored);
      expect(
        <String>[for (final row in await rows()) row.key],
        <String>[
          'meaning_primary',
          if (choice.secondary != null) 'meaning_secondary',
        ],
        reason: '$stored: the old key is gone',
      );
    }
  });

  test('#1096 a learner who chose since keeps their choice; the old key goes '
      'all the same', () async {
    await writeMeaningChoice(settings, const MeaningChoice('ru'));
    await db.customStatement(
      "INSERT INTO settings (key, value) VALUES ('meaning_language', 'both')",
    );
    await settings.load();
    expect(meaningChoiceOf(settings), const MeaningChoice('ru'));
    expect(
      <String>[for (final row in await rows()) row.key],
      <String>['meaning_primary'],
    );
  });

  test('#1156 the owner: setup opens on the app language\'s meanings, where '
      'the course ships them', () {
    const shipped = <String>{'en', 'bn', 'ru', 'pl'};
    expect(
      meaningDefaultFor(UiLanguage.russian, shipped),
      const MeaningChoice('ru'),
    );
    expect(
      meaningDefaultFor(UiLanguage.polish, shipped),
      const MeaningChoice('pl'),
    );
    expect(
      meaningDefaultFor(UiLanguage.english, shipped),
      const MeaningChoice('en', 'bn'),
    );
    expect(
      meaningDefaultFor(UiLanguage.bangla, shipped),
      const MeaningChoice('bn', 'en'),
    );
    expect(
      meaningDefaultFor(UiLanguage.russian, const <String>{'en', 'bn'}),
      MeaningChoice.fallback,
      reason: 'a course without Russian: English then Bangla',
    );
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

  test('#1096 a choice writes the two settings and nothing else', () async {
    await writeMeaningChoice(settings, const MeaningChoice('bn', 'en'));
    expect(
      <(String, String)>[for (final row in await rows()) (row.key, row.value)],
      <(String, String)>[
        ('meaning_primary', 'bn'),
        ('meaning_secondary', 'en'),
      ],
    );
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
