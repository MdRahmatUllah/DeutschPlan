import 'dart:io';

import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/components/dp_rating_bar.dart';
import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/study/study_card.dart';
import 'package:deutschplan/features/study/study_cloze.dart';
import 'package:deutschplan/features/study/study_screen.dart';
import 'package:deutschplan/features/study/study_session.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/router/routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../services/fake_tts.dart';

import '../db/content_fixture.dart';

/// T2 · StudyCloze — #104.
void main() {
  const today = '2026-09-21';
  const strasse = ContentFixture.strasse;
  const haus = ContentFixture.haus;

  late AppDatabase db;
  late SettingsRepository settings;
  late AppLocalizations l10n;
  late List<String> spoken;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  /// Straße to revise — a cloze card, BR-FSRS-06 — then Haus, new.
  Future<void> open({String mode = 'cloze', String? example}) async {
    db = AppDatabase.memory();
    final directory = Directory.systemTemp.createTempSync('dp_cloze');
    final content = ContentFixture.write('${directory.path}/content.db');
    await db.customStatement(
      "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
    );
    if (example != null) {
      await db.customStatement(
        "UPDATE c.word_examples SET german = '$example' "
        "WHERE word_uid = '$strasse'",
      );
    }
    await db.customStatement('''
INSERT INTO plan_items (plan_date, word_uid, kind, sublevel_code) VALUES
  ('$today', '$strasse', 'revise', 'A1.2'),
  ('$today', '$haus', 'new', 'A1.1')
''');
    await db.customStatement('''
INSERT INTO word_state (word_uid, status, introduced_on, due, stability,
  difficulty, reps, lapses, fsrs_state, last_review, card_mode)
VALUES ('$strasse', 'learning', '2026-09-10', '2026-09-21', 4.5, 5.2, 2, 0,
  2, '2026-09-15T08:00:00.000Z', '$mode')
''');
    settings = SettingsRepository(db);
    await settings.load();
    await settings.write(SettingKeys.autoplayHeadword, false);
  }

  const args = SessionArgs(
    planDate: today,
    blocks: <SessionBlock>[
      SessionBlock(SessionBlockKind.revise, <String>[strasse]),
      SessionBlock(SessionBlockKind.newWords, <String>[haus]),
    ],
  );

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    String mode = 'cloze',
    String? example,
    bool voice = true,
  }) async {
    spoken = <String>[];
    await tester.runAsync(() => open(mode: mode, example: example));
    addTearDown(
      () => tester.runAsync(() async {
        await settings.dispose();
        await db.close();
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
          ttsProvider.overrideWithValue(FakeTts(voice: voice, spoken: spoken)),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 9)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: const StudyScreen(args: args),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(StudyScreen.bannerTime);
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(StudyScreen)));
  }

  Future<void> answer(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.widgetWithText(DpButton, l10n.studyClozeCheck));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('FR-T2-10 a cloze word: the gap, not the front', (tester) async {
    await pump(tester);

    expect(find.byType(StudyClozeCard), findsOneWidget);
    expect(find.byType(StudyWordCard), findsNothing);
    expect(find.text(l10n.studyClozeChip), findsOneWidget);
    expect(find.text(l10n.studyClozePrompt.toUpperCase()), findsOneWidget);
    expect(find.text('The street is long.'), findsOneWidget);
    // The word itself is what is asked: not shown, not spoken.
    expect(find.text('Straße'), findsNothing);
    expect(find.byType(DpSpeakerButton), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(DpUmlautBar), findsOneWidget);
    // No Show meaning, and no rating bar yet.
    expect(find.text(l10n.studyShowMeaning), findsNothing);
    expect(find.byType(DpRatingBar), findsNothing);
  });

  testWidgets('a plain word keeps the plain front', (tester) async {
    await pump(tester, mode: 'plain');
    expect(find.byType(StudyClozeCard), findsNothing);
    expect(find.byType(StudyWordCard), findsOneWidget);
  });

  testWidgets('no example holds the word: the plain card instead', (
    tester,
  ) async {
    await pump(tester, example: 'Sie ist lang.');
    expect(find.byType(StudyClozeCard), findsNothing);
    expect(find.byType(StudyWordCard), findsOneWidget);
    expect(find.text(l10n.studyShowMeaning), findsOneWidget);
  });

  testWidgets('an inflected form is blanked and asked', (tester) async {
    await pump(tester, example: 'Die Straßen sind lang.');
    await answer(tester, 'Straßen');
    expect(find.text(l10n.studyClozeCorrect), findsOneWidget);
    expect(find.text('Straßen'), findsOneWidget);
  });

  testWidgets('Check waits for an answer', (tester) async {
    await pump(tester);
    expect(
      tester
          .widget<DpButton>(find.widgetWithText(DpButton, l10n.studyClozeCheck))
          .onPressed,
      isNull,
    );
  });

  testWidgets('correct: the sentence plays, then the rating bar and its '
      'prompt', (tester) async {
    final container = await pump(tester);
    await answer(tester, 'Straße');

    expect(find.text(l10n.studyClozeCorrect), findsOneWidget);
    expect(spoken, <String>['Die Straße ist lang.']);
    // The gap now holds the word, and the footnote explains the card.
    expect(find.text('Straße'), findsOneWidget);
    expect(find.text(l10n.studyClozeFootnote), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text(l10n.studyClozeRatePrompt), findsOneWidget);
    expect(find.byType(DpRatingBar), findsOneWidget);
    expect(container.read(studySessionProvider(args)).value?.revealed, isTrue);
  });

  testWidgets('BR-ANS-02 the article is not required, nor wrong to add', (
    tester,
  ) async {
    await pump(tester);
    await answer(tester, 'die Straße');
    expect(find.text(l10n.studyClozeCorrect), findsOneWidget);
  });

  testWidgets('the keyboard\'s done checks it too', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'Straße');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text(l10n.studyClozeCorrect), findsOneWidget);
  });

  testWidgets('BR-ANS-01 almost: the spelling shown, and rating allowed', (
    tester,
  ) async {
    await pump(tester);
    await answer(tester, 'Strase');

    expect(find.text(l10n.studyClozeAlmost('Straße')), findsOneWidget);
    expect(spoken, isEmpty);
    expect(find.byType(DpRatingBar), findsOneWidget);
  });

  testWidgets('wrong: the answer shown, and rating allowed', (tester) async {
    await pump(tester);
    await answer(tester, 'Haus');

    expect(find.text(l10n.studyClozeWrong('Straße')), findsOneWidget);
    expect(spoken, isEmpty);
    expect(find.byType(DpRatingBar), findsOneWidget);
  });

  testWidgets('the footnote play button plays the sentence again', (
    tester,
  ) async {
    await pump(tester);
    await answer(tester, 'Haus');
    await tester.tap(find.bySemanticsLabel(l10n.studyPlaySentence));
    await tester.pump();
    expect(spoken, <String>['Die Straße ist lang.']);
  });

  testWidgets('V01 with no German voice, a right answer plays nothing and '
      'says nothing: T2 has said it once already', (tester) async {
    await pump(tester, voice: false);
    await answer(tester, 'Straße');
    await tester.pump();
    expect(spoken, isEmpty);
    expect(find.text(l10n.speakerNoVoice), findsNothing);
  });

  testWidgets('V01 with no German voice, it says how to install one', (
    tester,
  ) async {
    await pump(tester, voice: false);
    await answer(tester, 'Haus');
    await tester.tap(find.bySemanticsLabel(l10n.studyPlaySentence));
    await tester.pump();
    expect(find.text(l10n.speakerNoVoice), findsOneWidget);
  });

  testWidgets('rated, the next card; undone, a clean gap again', (
    tester,
  ) async {
    final container = await pump(tester);
    await answer(tester, 'Straße');

    await tester.runAsync(() async {
      await tester.tap(find.text(l10n.ratingGood));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(
      container.read(studySessionProvider(args)).value?.current?.uid,
      haus,
    );

    await tester.runAsync(() async {
      await container.read(studySessionProvider(args).notifier).undo();
    });
    await tester.pumpAndSettle();
    expect(find.byType(StudyClozeCard), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
    expect(find.byType(DpRatingBar), findsNothing);
  });

  testWidgets('two cloze cards in a row: the second starts clean', (
    tester,
  ) async {
    final container = await pump(tester);
    await tester.runAsync(
      () => db.customStatement('''
INSERT INTO word_state (word_uid, status, stability, difficulty, reps,
  lapses, fsrs_state, card_mode)
VALUES ('$haus', 'learning', 8, 5, 2, 0, 2, 'cloze')
'''),
    );
    await answer(tester, 'Straße');
    await tester.runAsync(() async {
      await tester.tap(find.text(l10n.ratingGood));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(
      container.read(studySessionProvider(args)).value?.current?.uid,
      haus,
    );
    expect(find.byType(StudyClozeCard), findsOneWidget);
    expect(find.text(l10n.studyClozeCorrect), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
  });

  test('clozeOf takes the first example that holds the word', () {
    const word = Word(
      uid: 'w',
      sublevelCode: 'A1.1',
      levelCode: 'A1',
      seq: 1,
      seqInSublevel: 1,
      german: 'Haus',
      english: 'house',
      searchKey: 'haus',
      searchKeyAlt: 'haus',
    );
    final cloze = clozeOf(word, const <({String german, String? english})>[
      (german: 'Das ist gut.', english: null),
      (german: 'Das Haus ist groß.', english: 'The house is big.'),
    ]);
    expect(cloze?.example.german, 'Das Haus ist groß.');
    expect(cloze?.gap, (start: 4, end: 8));
  });
}
