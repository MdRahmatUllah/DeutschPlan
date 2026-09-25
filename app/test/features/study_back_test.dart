import 'dart:io';

import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/db/content_dao.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/study/study_back.dart';
import 'package:deutschplan/features/study/study_card.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../services/fake_tts.dart';

import '../db/content_fixture.dart';

/// T2 · StudyBack — #102.
void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  group('the back, from the course', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase.memory();
      final directory = Directory.systemTemp.createTempSync('dp_back');
      final content = ContentFixture.write('${directory.path}/content.db');
      await db.customStatement(
        "ATTACH DATABASE '${ContentDao.attachPath(content.file)}' AS c",
      );
      container = ProviderContainer(
        overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test(
      'the first two examples in their order, with their translations',
      () async {
        // A third, which the card has no room for.
        await db.customStatement(
          "INSERT INTO c.word_examples (word_uid, ord, german, english) "
          "VALUES ('${ContentFixture.haus}', 3, 'Wo ist das Haus?', NULL)",
        );
        final back = await container.read(
          studyBackProvider(ContentFixture.haus).future,
        );
        expect(back.examples, <StudyExample>[
          (german: 'Das Haus ist groß.', english: 'The house is big.'),
          (german: 'Ich sehe das Haus.', english: null),
        ]);
        expect(back.tip, isNull);
      },
    );

    test('and the interference tip, when the word has one', () async {
      final back = await container.read(
        studyBackProvider(ContentFixture.strasse).future,
      );
      expect(back.tip, (en: 'Straße is die, not der.', bn: 'Straße হলো die।'));
    });
  });

  group('the card turned over', () {
    late AppDatabase db;
    late SettingsRepository settings;
    late FakeTts tts;

    final rechnung = Word(
      uid: 'rechnung',
      sublevelCode: 'A2.1',
      levelCode: 'A2',
      seq: 1,
      seqInSublevel: 1,
      article: 'die',
      german: 'Rechnung',
      forms: 'Rechnungen',
      pos: 'noun',
      english: 'bill, invoice',
      bangla: 'বিল, চালান',
      collocations: 'die Rechnung bezahlen; eine Rechnung stellen',
      synonymsRegister: 'Im Restaurant auch: „Zahlen, bitte!“',
      searchKey: 'rechnung',
      searchKeyAlt: 'rechnung',
    );

    const extras = (
      examples: <StudyExample>[
        (
          german: 'Ich habe die Rechnung noch nicht bezahlt.',
          english: "I haven't paid the bill yet.",
        ),
        (
          german: 'Können wir bitte die Rechnung haben?',
          english: 'Could we have the bill, please?',
        ),
      ],
      tip: (
        en: 'Rechnung is a bill, not a calculation.',
        bn: 'রেশনুং মানে বিল।',
      ),
    );

    /// Flipped by the tests to turn the card over in place, as the session
    /// does.
    late ValueNotifier<bool> turned;

    Future<void> pump(
      WidgetTester tester, {
      Word? word,
      bool revealed = true,
      MeaningLanguage meaning = MeaningLanguage.both,
      bool autoplayExample = false,
      bool broken = false,
      VoidCallback? onReveal,
      Set<String> updated = const <String>{},
    }) async {
      await tester.runAsync(() async {
        db = AppDatabase.memory();
        settings = SettingsRepository(db);
        await settings.load();
        await settings.write(SettingKeys.autoplayHeadword, false);
        await settings.write(SettingKeys.autoplayExample, autoplayExample);
        await settings.write(SettingKeys.meaningLanguage, meaning);
      });
      addTearDown(
        () => tester.runAsync(() async {
          await settings.dispose();
          await db.close();
        }),
      );
      tts = FakeTts();
      turned = ValueNotifier<bool>(revealed);
      addTearDown(turned.dispose);
      final shown = word ?? rechnung;
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            settingsProvider.overrideWithValue(settings),
            fakeVoice(tts),
            studyBackProvider(shown.uid).overrideWith((ref) async {
              if (broken) throw StateError('content.db is being replaced');
              return extras;
            }),
            recentlyUpdatedProvider.overrideWith((ref) async => updated),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ValueListenableBuilder<bool>(
                  valueListenable: turned,
                  builder: (context, revealed, _) => StudyWordCard(
                    word: shown,
                    revealed: revealed,
                    onReveal: onReveal,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('face down there is no back', (tester) async {
      await pump(tester, revealed: false);
      expect(find.byType(StudyBack), findsNothing);
      expect(find.text('bill, invoice'), findsNothing);
    });

    testWidgets('FR-T2-01 a tap on the card turns it over', (tester) async {
      var turned = 0;
      await pump(tester, revealed: false, onReveal: () => turned++);
      await tester.tap(find.textContaining('Nomen'));
      expect(turned, 1);
    });

    testWidgets('meaning_language both: English, then Bangla', (tester) async {
      await pump(tester);
      expect(find.text('bill, invoice'), findsOneWidget);
      expect(find.text('বিল, চালান'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('বিল, চালান')).dy,
        greaterThan(tester.getTopLeft(find.text('bill, invoice')).dy),
      );
    });

    testWidgets('EN: English alone', (tester) async {
      await pump(tester, meaning: MeaningLanguage.english);
      expect(find.text('bill, invoice'), findsOneWidget);
      expect(find.text('বিল, চালান'), findsNothing);
    });

    testWidgets('বাংলা: Bangla alone, in ink', (tester) async {
      await pump(tester, meaning: MeaningLanguage.bangla);
      expect(find.text('bill, invoice'), findsNothing);
      expect(find.text('বিল, চালান'), findsOneWidget);
    });

    testWidgets('বাংলা, where the course has none: English instead', (
      tester,
    ) async {
      await pump(
        tester,
        word: rechnung.copyWith(bangla: const Value<String?>(null)),
        meaning: MeaningLanguage.bangla,
      );
      expect(find.text('bill, invoice'), findsOneWidget);
    });

    testWidgets('the interference tip is a Tangerine callout under them', (
      tester,
    ) async {
      await pump(tester, meaning: MeaningLanguage.english);
      final callout = find.byType(DpCallout);
      expect(callout, findsOneWidget);
      expect(
        find.descendant(
          of: callout,
          matching: find.text(
            l10n.studyTip('Rechnung is a bill, not a calculation.'),
          ),
        ),
        findsOneWidget,
      );
      final bar = tester.widget<ColoredBox>(
        find.descendant(of: callout, matching: find.byType(ColoredBox)).first,
      );
      expect(bar.color, DpPalette.light.hard);
      expect(
        tester.getTopLeft(callout).dy,
        greaterThan(tester.getTopLeft(find.text('bill, invoice')).dy),
      );
      expect(
        tester.getTopLeft(callout).dy,
        lessThan(
          tester
              .getTopLeft(
                find.text('Ich habe die Rechnung noch nicht bezahlt.'),
              )
              .dy,
        ),
      );
    });

    testWidgets('and in both languages when both are chosen', (tester) async {
      await pump(tester);
      // The callout lets long words break, so match the two lines' ends.
      final tip = find.descendant(
        of: find.byType(DpCallout),
        matching: find.byType(DpText),
      );
      final text = tester.widget<DpText>(tip).data;
      expect(text, startsWith('⚠ Rechnung is a bill, not a calculation.\n'));
      expect(text, endsWith('রেশনুং মানে বিল।'));
    });

    testWidgets('two examples with their translations', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      expect(
        find.text('Ich habe die Rechnung noch nicht bezahlt.'),
        findsOneWidget,
      );
      expect(find.text("I haven't paid the bill yet."), findsOneWidget);
      expect(find.text('Können wir bitte die Rechnung haben?'), findsOneWidget);
      // A screen reader hears the button with its sentence.
      expect(
        find.bySemanticsLabel(RegExp('^${l10n.studyPlaySentence}')),
        findsNWidgets(2),
      );
      semantics.dispose();
    });

    testWidgets('an example plays at the chosen speed', (tester) async {
      await pump(tester);
      await tester.runAsync(() => settings.write(SettingKeys.ttsSpeed, 1.25));
      await tester.tap(find.text('Können wir bitte die Rechnung haben?'));
      await tester.pump();
      expect(tts.said, <(String, double)>[
        ('Können wir bitte die Rechnung haben?', 1.25),
      ]);
    });

    testWidgets('collocations after ⟶, dotted; register after ≈', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.text(
          l10n.studyCollocations(
            'die Rechnung bezahlen · eine Rechnung stellen',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(l10n.studyRegister('Im Restaurant auch: „Zahlen, bitte!“')),
        findsOneWidget,
      );
    });

    testWidgets('a word without them leaves the lines out', (tester) async {
      await pump(
        tester,
        word: rechnung.copyWith(
          collocations: const Value<String?>(null),
          synonymsRegister: const Value<String?>(null),
        ),
      );
      expect(find.textContaining('⟶'), findsNothing);
      expect(find.textContaining('≈'), findsNothing);
    });

    testWidgets('BR-CONTENT-02 FR-T2-01 a meaning updated this week wears the '
        'Updated chip, over the meaning', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, updated: <String>{'rechnung'});
      expect(find.text(l10n.wordUpdated), findsOneWidget);
      expect(find.bySemanticsLabel(l10n.wordUpdatedSemantic), findsOneWidget);
      semantics.dispose();
      expect(
        tester.getTopLeft(find.text(l10n.wordUpdated)).dy,
        lessThan(tester.getTopLeft(find.text('bill, invoice')).dy),
      );
    });

    testWidgets('BR-CONTENT-02 FR-T2-01 and none for a word the update left '
        'alone', (tester) async {
      await pump(tester, updated: <String>{'haus'});
      expect(find.text('bill, invoice'), findsOneWidget);
      expect(find.text(l10n.wordUpdated), findsNothing);
    });

    testWidgets('V03 FR-T2-01 autoplay_example on: the first example plays on '
        'reveal', (tester) async {
      await pump(tester, revealed: false, autoplayExample: true);
      expect(tts.said, isEmpty);

      turned.value = true;
      await tester.pumpAndSettle();
      expect(tts.said, <(String, double)>[
        ('Ich habe die Rechnung noch nicht bezahlt.', 1),
      ]);

      // Once per reveal, not on every rebuild of a card already turned.
      tester
          .element(
            find
                .ancestor(
                  of: find.byType(StudyWordCard),
                  matching: find.byType(ValueListenableBuilder<bool>),
                )
                .first,
          )
          .markNeedsBuild();
      await tester.pumpAndSettle();
      expect(tts.said, hasLength(1));
    });

    testWidgets('and a failed example query just means no autoplay', (
      tester,
    ) async {
      await pump(tester, revealed: false, autoplayExample: true, broken: true);
      turned.value = true;
      await tester.pumpAndSettle();
      expect(tts.said, isEmpty);
      expect(find.text('bill, invoice'), findsOneWidget);
    });

    testWidgets('V03 autoplay_example off: nothing plays', (tester) async {
      await pump(tester, revealed: false);
      turned.value = true;
      await tester.pumpAndSettle();
      expect(tts.said, isEmpty);
    });

    testWidgets('the reveal grows the card and fades the back in, 4 px up', (
      tester,
    ) async {
      await pump(tester, revealed: false);
      final before = tester.getSize(find.byType(StudyWordCard)).height;

      turned.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byType(StudyBack),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, inExclusiveRange(0, 1));
      final slide = tester.widget<Transform>(
        find
            .ancestor(
              of: find.byType(StudyBack),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(slide.transform.getTranslation().y, inExclusiveRange(0, 4));

      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(StudyWordCard)).height,
        greaterThan(before),
      );
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(
                of: find.byType(StudyBack),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        1,
      );
    });

    testWidgets('quick, and instant with reduced motion', (tester) async {
      await pump(tester, revealed: false);
      expect(
        tester.widget<AnimatedSize>(find.byType(AnimatedSize)).duration,
        DpMotionTokens.defaults.quick,
      );

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      turned.value = true;
      await tester.pump();
      expect(find.byType(AnimatedSize), findsNothing);
      expect(find.text('bill, invoice'), findsOneWidget);
    });
  });
}
