@TestOn('vm')
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/components/sg_button.dart';
import 'package:sogda/core/components/sg_chip.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/course_meanings.dart';
import 'package:sogda/data/repositories/meaning_choice.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/data/repositories/word_repository.dart';
import 'package:sogda/features/onboarding/onboarding_meaning_page.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:sqlite3/sqlite3.dart';

/// S2 page 2 · Meaning language — #88.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  // The cards and chips name each language in itself (#1081).
  const en = 'English';
  const bn = 'বাংলা';
  const english = 'flat / apartment';
  const bangla = 'ফ্ল্যাট / অ্যাপার্টমেন্ট';

  Word wohnung({String? bn = bangla}) => Word(
    kind: 'vocab',
    uid: meaningSampleUid,
    sublevelCode: 'A1.1',
    levelCode: 'A1',
    seq: 1,
    seqInSublevel: 1,
    article: 'die',
    german: 'Wohnung',
    english: english,
    bangla: bn,
    searchKey: 'wohnung',
    searchKeyAlt: 'wohnung',
  );

  late SettingsRepository settings;

  Future<void> pump(
    WidgetTester tester, {
    Word? sample,
    bool noSample = false,
    bool sampleThrows = false,
    MeaningLanguage? stored,
    List<CourseLanguageName>? languages,
    CourseMeanings course = CourseMeanings.none,
    SgMode mode = SgMode.light,
    VoidCallback? onContinue,
    VoidCallback? onBack,
  }) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    settings = SettingsRepository(db);
    await settings.load();
    addTearDown(settings.dispose);
    if (stored != null) {
      await settings.write(SettingKeys.meaningLanguage, stored);
    }

    final word = noSample ? null : sample ?? wohnung();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsProvider.overrideWithValue(settings),
          if (languages != null)
            courseLanguagesProvider.overrideWith((ref) async => languages),
          courseMeaningsProvider.overrideWith((ref) async => course),
          meaningSampleProvider.overrideWith(
            (ref) async => sampleThrows
                ? throw StateError('content.db is not attached')
                : word == null
                ? null
                : WordWithState(
                    word: word,
                    state: null,
                    status: WordStatus.todo,
                  ),
          ),
        ],
        child: MaterialApp(
          theme: switch (mode) {
            SgMode.light => AppTheme.light(),
            SgMode.dark => AppTheme.dark(),
            SgMode.glass => AppTheme.glass(),
          },
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: OnboardingMeaningPage(onContinue: onContinue, onBack: onBack),
        ),
      ),
    );
    // One frame for the sample's future, one for what it rebuilds.
    await tester.pump();
    await tester.pump();
  }

  /// A language's card: the chips name the languages too, after the cards.
  Finder card(String title) => find
      .ancestor(of: find.text(title), matching: find.byType(SgSurface))
      .first;

  bool isSelected(WidgetTester tester, String title) =>
      tester.widget<SgSurface>(card(title)).selected;

  List<String> selectedTitles(WidgetTester tester) => <String>[
    for (final title in <String>[en, bn])
      if (isSelected(tester, title)) title,
  ];

  /// The *Also show* chip that is on.
  String alsoShown(WidgetTester tester) => tester
      .widgetList<SgChip>(find.byType(SgChip))
      .singleWhere((chip) => chip.selected)
      .label;

  MeaningChoice choice() => meaningChoiceOf(settings);

  group('the choice', () {
    testWidgets('#1081 starts on English, Bangla also shown: the documented '
        'default', (tester) async {
      // `meaning_language` defaults to `both`: English first, then Bangla.
      await pump(tester);

      expect(selectedTitles(tester), <String>[en]);
      expect(alsoShown(tester), bn);
    });

    testWidgets('FR-S2-02 shows what was picked when the page is revisited', (
      tester,
    ) async {
      await pump(tester, stored: MeaningLanguage.bangla);

      expect(selectedTitles(tester), <String>[bn]);
      expect(alsoShown(tester), l10n.onboardingMeaningNone);
    });

    testWidgets('#1081 a card picks the first language, and only one is ever '
        'picked; the second chosen first, the two swap', (tester) async {
      await pump(tester);

      await tester.tap(card(bn));
      await tester.pump();
      expect(selectedTitles(tester), <String>[bn]);
      expect(alsoShown(tester), en);
      expect(choice(), const MeaningChoice('bn', 'en'));

      await tester.tap(card(en));
      await tester.pump();
      expect(selectedTitles(tester), <String>[en]);
      expect(alsoShown(tester), bn);
    });

    testWidgets('#1078 #1081 writes the choice and leaves the app language '
        'page 1 chose', (tester) async {
      // Polish screens with English meanings stay Polish: the meaning
      // language no longer sets the app's.
      await pump(tester);
      await settings.write(SettingKeys.uiLanguage, UiLanguage.polish);

      for (final (tap, want) in <(Finder Function(), MeaningChoice)>[
        (() => card(bn), const MeaningChoice('bn', 'en')),
        (
          () => find.widgetWithText(SgChip, l10n.onboardingMeaningNone),
          const MeaningChoice('bn'),
        ),
        (() => card(en), const MeaningChoice('en')),
        (
          () => find.widgetWithText(SgChip, bn),
          const MeaningChoice('en', 'bn'),
        ),
      ]) {
        await tester.tap(tap());
        await tester.pump();

        expect(choice(), want);
        expect(
          settings.read(SettingKeys.uiLanguage),
          UiLanguage.polish,
          reason: '$want',
        );
      }
    });

    testWidgets('#1081 a language the course adds is a card of its own, named '
        'in itself, with the sample in it', (tester) async {
      await pump(
        tester,
        languages: const <CourseLanguageName>[
          (code: 'en', ownName: en),
          (code: 'bn', ownName: bn),
          (code: 'ru', ownName: 'Русский'),
        ],
        course: const CourseMeanings(<String, Map<String, WordMeaningText>>{
          meaningSampleUid: <String, WordMeaningText>{
            'ru': (meaning: 'квартира', pronunciation: null),
          },
        }),
      );
      expect(find.text('die Wohnung → квартира'), findsOneWidget);

      await tester.tap(card('Русский'));
      await tester.pump();
      expect(choice(), const MeaningChoice('ru', 'bn'));
      // Under three cards, the chips sit under the action bar's edge.
      await tester.ensureVisible(find.widgetWithText(SgChip, en));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SgChip, en));
      await tester.pump();
      expect(choice(), const MeaningChoice('ru', 'en'));
      expect(isSelected(tester, 'Русский'), isTrue);
    });

    testWidgets('and the tick sits on the picked card', (tester) async {
      await pump(tester, stored: MeaningLanguage.english);

      expect(
        find.descendant(
          of: find.ancestor(of: card(en), matching: find.byType(Stack)).first,
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.ancestor(of: card(bn), matching: find.byType(Stack)).first,
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
      );
    });
  });

  group('the sample', () {
    testWidgets('reads the word in each language', (tester) async {
      await pump(tester);

      expect(find.text('die Wohnung → $english'), findsOneWidget);
      expect(find.text('die Wohnung → $bangla'), findsOneWidget);
    });

    testWidgets('sets its Bangla one type step larger than its Latin', (
      tester,
    ) async {
      // theming.md: "Bangla is set one step larger at the same role." The
      // sample is `label`, so its Bangla run is `body`.
      await pump(tester);
      final tokens = tester.element(find.byType(OnboardingMeaningPage)).tokens;

      final spans = <TextSpan>[];
      tester
          .widget<RichText>(
            find.descendant(
              of: find.text('die Wohnung → $bangla'),
              matching: find.byType(RichText),
            ),
          )
          .text
          .visitChildren((span) {
            if (span is TextSpan && (span.text ?? '').trim().isNotEmpty) {
              spans.add(span);
            }
            return true;
          });

      final latin = spans.firstWhere((s) => s.text!.contains('Wohnung'));
      final bengali = spans.firstWhere((s) => s.text!.contains('ফ্ল্যাট'));
      expect(latin.style!.fontSize, tokens.typography.label.size);
      expect(bengali.style!.fontSize, tokens.typography.body.size);
    });

    testWidgets('a missing Bangla meaning drops that line only', (
      tester,
    ) async {
      // `bangla` is nullable in the schema. No dangling "die Wohnung → ".
      await pump(tester, sample: wohnung(bn: null));

      expect(find.textContaining('→'), findsOneWidget);
      expect(find.text('die Wohnung → $english'), findsOneWidget);
    });

    testWidgets('and with no sample at all the cards still choose', (
      tester,
    ) async {
      await pump(tester, noSample: true);

      expect(find.textContaining('→'), findsNothing);

      await tester.tap(card(bn));
      await tester.pump();
      expect(choice().primary, 'bn');
    });

    testWidgets('#527 #1081 FR-S2-02 a learner with no Bangla starts with the '
        'Bangla pronunciation off; with Bangla first or second, on', (
      tester,
    ) async {
      await pump(tester);
      for (final (tap, pron) in <(Finder Function(), bool)>[
        (() => find.widgetWithText(SgChip, l10n.onboardingMeaningNone), false),
        (() => card(bn), true),
        (() => card(en), false),
        (() => find.widgetWithText(SgChip, bn), true),
      ]) {
        await tester.tap(tap());
        await tester.pump();
        expect(
          settings.read(SettingKeys.showPronBn),
          pron,
          reason: '${choice()}',
        );
      }
    });

    testWidgets('and if content.db fails, the page does not', (tester) async {
      // Held by Riverpod 3's `AsyncValue.value`, which is null on error. A
      // move to `requireValue` would throw here instead, on the one screen
      // where the learner has not seen the app work yet.
      await pump(tester, sampleThrows: true);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('→'), findsNothing);

      await tester.tap(card(bn));
      await tester.pump();
      expect(choice().primary, 'bn');
    });

    test('the shipped content.db has the word, in both languages', () {
      // The uid is the one thing tying the page to content. Progress is keyed
      // on uids too, so this should never move — and if it does, this fails
      // before a learner sees three cards with no sample.
      final db = sqlite3.open('assets/db/content.db', mode: OpenMode.readOnly);
      addTearDown(db.close);

      final rows = db.select(
        'SELECT article, german, english, bangla FROM words WHERE uid = ?',
        <Object>[meaningSampleUid],
      );
      expect(rows, hasLength(1));
      expect(
        '${rows.single['article']} ${rows.single['german']}',
        'die Wohnung',
      );
      expect(rows.single['english'], isNotEmpty);
      expect(rows.single['bangla'], isNotEmpty);
    });
  });

  group('the actions', () {
    testWidgets('Continue and Back call back', (tester) async {
      var continued = 0;
      var back = 0;
      await pump(tester, onContinue: () => continued++, onBack: () => back++);

      await tester.tap(find.widgetWithText(SgButton, l10n.continueAction));
      await tester.tap(find.widgetWithText(SgButton, l10n.back));
      await tester.pump();

      expect(<int>[continued, back], <int>[1, 1]);
    });

    testWidgets('page 2 has no Skip', (tester) async {
      // The language is the one choice made deliberately rather than
      // defaulted — Skip starts on page 3.
      await pump(tester);

      expect(find.widgetWithText(SgButton, l10n.skip), findsNothing);
    });
  });

  group('it is built from the design system', () {
    testWidgets('no Material chrome', (tester) async {
      await pump(tester);

      expect(find.byType(AdaptiveScaffold), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(RadioListTile<String>), findsNothing);
    });

    testWidgets('and glass and dark render it', (tester) async {
      for (final mode in <SgMode>[SgMode.dark, SgMode.glass]) {
        await pump(tester, mode: mode);
        expect(selectedTitles(tester), hasLength(1), reason: mode.name);
      }
    });
  });

  group('accessibility', () {
    testWidgets('the cards are one group, and the picked one says so', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, stored: MeaningLanguage.bangla);

      expect(
        tester.getSemantics(find.text(bn)),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
          // The sample is read with the name — it is what the choice means.
          label: '$bn\ndie Wohnung → $bangla',
        ),
      );
      expect(
        tester.getSemantics(find.text(en).first),
        matchesSemantics(
          isButton: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
          label: '$en\ndie Wohnung → $english',
        ),
      );

      handle.dispose();
    });
  });
}
