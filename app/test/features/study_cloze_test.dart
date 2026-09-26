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

import '../core/text_clipping.dart' show AndroidTextScaler;
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
  Future<void> open({
    String mode = 'cloze',
    String? example,
    bool chosen = false,
  }) async {
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
  difficulty, reps, lapses, fsrs_state, last_review, card_mode,
  card_mode_manual)
VALUES ('$strasse', 'learning', '2026-09-10', '2026-09-21', 4.5, 5.2, 2, 0,
  2, '2026-09-15T08:00:00.000Z', '$mode', ${chosen ? 1 : 0})
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
    bool chosen = false,
    TextScaler? textScaler,
    Locale? locale,
  }) async {
    spoken = <String>[];
    await tester.runAsync(
      () => open(mode: mode, example: example, chosen: chosen),
    );
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
          fakeVoice(FakeTts(voice: voice, spoken: spoken)),
          clockProvider.overrideWithValue(() => DateTime(2026, 9, 21, 9)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: locale,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          builder: textScaler == null
              ? null
              : (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: child!,
                ),
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

  testWidgets("#515 L8's and L12's answer field keeps Flutter's 20 dp: their "
      'umlaut row is pinned above the keyboard', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: supportedLocales,
        home: Scaffold(
          body: StudyAnswerField(
            controller: TextEditingController(),
            onSubmitted: () {},
          ),
        ),
      ),
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).scrollPadding,
      const EdgeInsets.all(20),
    );
  });

  testWidgets('#515 on focus, the answer scrolls up with its umlaut row and '
      '*Check* above the keyboard', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(StudyAnswerField));
    await tester.pump();
    // A keyboard with its suggestion bar: 350 dp of the 600 left.
    // Physical pixels: the test view is 800 × 600 at 3.0.
    tester.view.viewInsets = const FakeViewPadding(bottom: 250 * 3);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    const keyboardTop = 600.0 - 250;
    expect(
      tester.getRect(find.byType(DpUmlautBar)).bottom,
      lessThanOrEqualTo(keyboardTop),
      reason: 'the umlaut row, whole',
    );
    expect(
      tester
          .getRect(find.widgetWithText(DpButton, l10n.studyClozeCheck))
          .bottom,
      lessThanOrEqualTo(keyboardTop),
      reason: 'and Check',
    );
  });

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

  testWidgets('#515 BR-FSRS-06 a cloze card the learner chose in W1 says so, '
      'not the two ratings', (tester) async {
    await pump(tester, chosen: true);
    await answer(tester, 'Straße');
    expect(find.text(l10n.studyClozeFootnoteChosen), findsOneWidget);
    expect(find.text(l10n.studyClozeFootnote), findsNothing);
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

  /// Whether [rating]'s button takes a tap.
  bool offered(WidgetTester tester, String rating) {
    final node = tester.getSemantics(find.bySemanticsLabel(RegExp('^$rating')));
    return isSemantics(isEnabled: true).matches(node, <dynamic, dynamic>{});
  }

  testWidgets('#345 wrong: Again and Hard only; Good and Easy are for a right '
      'or almost answer', (tester) async {
    await pump(tester);
    await answer(tester, 'Haus');
    // The intervals load before the bar takes a rating.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(offered(tester, l10n.ratingAgain), isTrue);
    expect(offered(tester, l10n.ratingHard), isTrue);
    expect(offered(tester, l10n.ratingGood), isFalse);
    expect(offered(tester, l10n.ratingEasy), isFalse);
  });

  testWidgets('#345 almost: all four offered', (tester) async {
    await pump(tester);
    await answer(tester, 'Strase');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    for (final rating in <String>[
      l10n.ratingAgain,
      l10n.ratingHard,
      l10n.ratingGood,
      l10n.ratingEasy,
    ]) {
      expect(offered(tester, rating), isTrue, reason: rating);
    }
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

  group('T2 #564 a cloze typed with the keyboard up', () {
    const keyboardTop = 731.0 - 300;

    // SQA's 731 dp phone, its status bar, and a 300 dp keyboard.
    Future<void> typing(
      WidgetTester tester,
      TextScaler textScaler, {
      String? example,
      Size size = const Size(390, 731),
      double keyboard = 300,
      Locale? locale,
    }) async {
      tester.view
        ..physicalSize = size * 3
        ..devicePixelRatio = 3
        ..padding = const FakeViewPadding(top: 24 * 3);
      addTearDown(tester.view.reset);
      await pump(
        tester,
        textScaler: textScaler,
        example: example,
        locale: locale,
      );
      await tester.showKeyboard(find.byType(TextField));
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
    }

    Finder close() => find.byIcon(Icons.close);

    for (final (percent, example) in <(int, String?)>[
      (200, null),
      (150, null),
      // Three lines at 200 %.
      (200, 'Die Straße vor unserem Haus ist lang.'),
    ]) {
      testWidgets(
        'at $percent %${example == null ? '' : ', three lines,'} the sentence and its translation show whole '
        "above the field; the top bar comes back with the keyboard's going",
        (tester) async {
          await typing(
            tester,
            AndroidTextScaler(percent / 100),
            example: example,
          );
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .focusNode
                .hasFocus,
            isTrue,
            reason: 'the field kept the keyboard',
          );
          expect(close(), findsNothing, reason: 'the top bar gave its row');
          final window = tester.getRect(
            find
                .ancestor(
                  of: find.byType(TextField),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          for (final (name, shown) in <(String, Finder)>[
            (
              'the sentence',
              find.textContaining('ist lang', findRichText: true).first,
            ),
            ('the translation', find.text('The street is long.')),
            ('the field', find.byType(TextField)),
          ]) {
            final rect = tester.getRect(shown);
            expect(rect.top, greaterThanOrEqualTo(window.top), reason: name);
            expect(rect.bottom, lessThanOrEqualTo(window.bottom), reason: name);
          }
          expect(
            tester.getRect(find.byType(DpUmlautBar)).bottom,
            lessThanOrEqualTo(keyboardTop),
          );

          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          expect(close(), findsOneWidget, reason: 'the top bar is back');
        },
      );
    }

    testWidgets('at 100 % the keyboard keeps the top bar', (tester) async {
      await typing(tester, TextScaler.noScaling);
      expect(close(), findsOneWidget);
    });
    // #572: a 360 × 640 budget phone and its 280 dp keyboard, where a
    // three-line sentence was 66 dp under the top. Typing past 130 % the
    // sentence and its translation are a role smaller, the gaps and the
    // field close, and the umlaut row's reserve is its real height.
    for (final (percent, example) in <(int, String?)>[
      (200, null),
      (150, null),
      (200, 'Die Straße vor unserem Haus ist lang.'),
      (150, 'Die Straße vor unserem Haus ist lang.'),
    ]) {
      for (final lang in <String>['en', 'bn']) {
        testWidgets('#572 in $lang at $percent % on a 360 × 640 phone'
            '${example == null ? '' : ', three lines at 200 %,'} the sentence '
            'and its translation show whole above the field, a role smaller; '
            "their size is back at the keyboard's going", (tester) async {
          await typing(
            tester,
            AndroidTextScaler(percent / 100),
            example: example,
            size: const Size(360, 640),
            keyboard: 280,
            locale: Locale(lang),
          );
          final sentence = find
              .textContaining('ist lang', findRichText: true)
              .first;
          // A role smaller draws shorter lines.
          double size() => tester.getSize(sentence).height;
          final typed = size();
          final window = tester.getRect(
            find
                .ancestor(
                  of: find.byType(TextField),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          for (final (name, shown) in <(String, Finder)>[
            ('the sentence', sentence),
            ('the translation', find.text('The street is long.')),
            ('the field', find.byType(TextField)),
          ]) {
            final rect = tester.getRect(shown);
            expect(rect.top, greaterThanOrEqualTo(window.top), reason: name);
            expect(rect.bottom, lessThanOrEqualTo(window.bottom), reason: name);
          }
          expect(
            tester.getRect(find.byType(DpUmlautBar)).bottom,
            lessThanOrEqualTo(640 - 280),
          );

          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          expect(size(), greaterThan(typed), reason: 'its own role again');
        });
      }
    }
  });
}
