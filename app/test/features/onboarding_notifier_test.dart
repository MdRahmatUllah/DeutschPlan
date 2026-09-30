import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/db/content_dao.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/features/onboarding/onboarding_notifier.dart';

import '../db/content_fixture.dart';

/// S2's draft — `onboarding.md`: "`OnboardingNotifier` holds draft values".
void main() {
  test('starts on A1.1, the first step of the course', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(onboardingProvider).step, 'A1.1');
  });

  test('holds new words to 3–30 and revisions to 0–100', () {
    // The slider cannot leave 3–30 by itself, but a preset or restart setup
    // can hand the draft anything; the rule lives here, not in the widget.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(onboardingProvider.notifier);

    notifier.setDailyNew(99);
    expect(container.read(onboardingProvider).dailyNew, 30);
    notifier.setDailyNew(1);
    expect(container.read(onboardingProvider).dailyNew, 3);

    notifier.setReviseCount(250);
    expect(container.read(onboardingProvider).reviseCount, 100);
    notifier.setReviseCount(-4);
    expect(container.read(onboardingProvider).reviseCount, 0);
  });

  test('starts on the documented pace defaults', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final draft = container.read(onboardingProvider);

    expect(
      (draft.dailyNew, draft.reviseCount, draft.studyDaysMask),
      (7, 10, 127),
    );
  });

  test('FR-S2-02 outlives the pages that show it', () async {
    // Going back from page 3 to page 2 unmounts page 3, and nothing else
    // watches the draft. An auto-disposing provider would go with it, and
    // coming forward again would show A1.1 however the learner had chosen.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final page = container.listen(onboardingProvider, (_, _) {});
    container.read(onboardingProvider.notifier).chooseStep('B1.2');
    page.close();

    // The turns Riverpod's dispose takes when the last listener leaves.
    await pumpEventQueue();

    expect(container.read(onboardingProvider).step, 'B1.2');
  });

  group('#1156 page 1 hands page 2 the app language\'s meanings', () {
    late SettingsRepository settings;
    late ProviderContainer container;

    /// A setup on a course with Russian ([course]) or without a course.
    Future<void> setUpWith({bool course = true, bool russian = true}) async {
      final db = AppDatabase(DatabaseConnection(NativeDatabase.memory()));
      addTearDown(db.close);
      if (course) {
        final file = ContentFixture.write(
          '${tempDir('sg_setup').path}/content.db',
          russian: russian,
        ).file;
        await db.customStatement(
          "ATTACH DATABASE '${ContentDao.attachPath(file)}' AS c",
        );
      }
      settings = SettingsRepository(db);
      await settings.load();
      addTearDown(settings.dispose);
      container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
        ],
      );
      addTearDown(container.dispose);
    }

    Future<MeaningChoice> start(UiLanguage ui) async {
      await container.read(languagesProvider.notifier).setUi(ui);
      await container.read(onboardingProvider.notifier).preselectMeaning();
      return meaningChoiceOf(settings);
    }

    test('each app language its own, and Russian alone where the course '
        'ships it', () async {
      await setUpWith();
      expect(await start(UiLanguage.russian), const MeaningChoice('ru'));
      expect(
        settings.read(SettingKeys.showPronBn),
        isFalse,
        reason: 'no Bangla chosen: no Bangla guide (#1077)',
      );
      // Back to page 1 and another language: page 2 follows, its own pick.
      expect(await start(UiLanguage.bangla), const MeaningChoice('bn', 'en'));
      expect(await start(UiLanguage.english), const MeaningChoice('en', 'bn'));
      expect(
        await start(UiLanguage.polish),
        const MeaningChoice('en', 'bn'),
        reason: 'the fixture course ships no Polish',
      );
    });

    test(
      'never over a choice made on page 2, nor one a backup brought',
      () async {
        await setUpWith();
        await start(UiLanguage.english);
        await container
            .read(languagesProvider.notifier)
            .chooseMeaning(const MeaningChoice('bn'));
        expect(await start(UiLanguage.russian), const MeaningChoice('bn'));

        await setUpWith();
        await writeMeaningChoice(settings, const MeaningChoice('ru', 'en'));
        expect(
          await start(UiLanguage.english),
          const MeaningChoice('ru', 'en'),
          reason: 'a restored backup\'s choice',
        );
      },
    );

    test(
      'an empty meaning_primary, as a backup may bring, is no choice',
      () async {
        await setUpWith();
        await settings.write(SettingKeys.meaningPrimary, 'ru');
        await container
            .read(appDatabaseProvider)
            .customStatement(
              "UPDATE settings SET value = '' WHERE key = 'meaning_primary'",
            );
        await settings.load();
        expect(await start(UiLanguage.bangla), const MeaningChoice('bn', 'en'));
      },
    );

    test('with no course to read, the two it always has', () async {
      await setUpWith(course: false);
      expect(await start(UiLanguage.russian), MeaningChoice.fallback);
    });
  });
}
