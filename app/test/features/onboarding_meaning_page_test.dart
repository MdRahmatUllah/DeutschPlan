@TestOn('vm')
library;

import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/components/dp_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/data/repositories/word_repository.dart';
import 'package:deutschplan/features/onboarding/onboarding_meaning_page.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqlite3/sqlite3.dart';

/// S2 page 2 · Meaning language — #88.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  const english = 'flat / apartment';
  const bangla = 'ফ্ল্যাট / অ্যাপার্টমেন্ট';

  Word wohnung({String? bn = bangla}) => Word(
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
    DpMode mode = DpMode.light,
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
            DpMode.light => AppTheme.light(),
            DpMode.dark => AppTheme.dark(),
            DpMode.glass => AppTheme.glass(),
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

  Finder card(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(DpSurface));

  bool isSelected(WidgetTester tester, String title) =>
      tester.widget<DpSurface>(card(title)).selected;

  List<String> selectedTitles(WidgetTester tester) => <String>[
    for (final title in <String>[
      l10n.onboardingMeaningEnglish,
      l10n.onboardingMeaningBangla,
      l10n.onboardingMeaningBoth,
    ])
      if (isSelected(tester, title)) title,
  ];

  group('the choice', () {
    testWidgets('starts on Both, the documented default', (tester) async {
      // `meaning_language` defaults to `both`, and the artboard draws Both
      // picked.
      await pump(tester);

      expect(selectedTitles(tester), <String>[l10n.onboardingMeaningBoth]);
    });

    testWidgets('FR-S2-02 shows what was picked when the page is revisited', (
      tester,
    ) async {
      await pump(tester, stored: MeaningLanguage.bangla);

      expect(selectedTitles(tester), <String>[l10n.onboardingMeaningBangla]);
    });

    testWidgets('moves with the tap, and only one is ever picked', (
      tester,
    ) async {
      await pump(tester);

      for (final title in <String>[
        l10n.onboardingMeaningEnglish,
        l10n.onboardingMeaningBangla,
        l10n.onboardingMeaningBoth,
      ]) {
        await tester.tap(find.text(title));
        await tester.pump();

        expect(selectedTitles(tester), <String>[title]);
      }
    });

    testWidgets('writes meaning_language and ui_language', (tester) async {
      // "This also sets the app language." Both gives English, the
      // `ui_language` default — the app can only speak one.
      await pump(tester);

      for (final (title, meaning, ui)
          in <(String, MeaningLanguage, UiLanguage)>[
            (
              l10n.onboardingMeaningBangla,
              MeaningLanguage.bangla,
              UiLanguage.bangla,
            ),
            (
              l10n.onboardingMeaningEnglish,
              MeaningLanguage.english,
              UiLanguage.english,
            ),
            (
              l10n.onboardingMeaningBoth,
              MeaningLanguage.both,
              UiLanguage.english,
            ),
          ]) {
        await tester.tap(find.text(title));
        await tester.pump();

        expect(settings.read(SettingKeys.meaningLanguage), meaning);
        expect(settings.read(SettingKeys.uiLanguage), ui, reason: title);
      }
    });

    testWidgets('and the tick sits on the picked card', (tester) async {
      await pump(tester, stored: MeaningLanguage.english);

      expect(
        find.descendant(
          of: find.ancestor(
            of: card(l10n.onboardingMeaningEnglish),
            matching: find.byType(Stack),
          ),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
    });
  });

  group('the sample', () {
    testWidgets('reads the word the way each option would', (tester) async {
      await pump(tester);

      expect(find.text('die Wohnung → $english'), findsOneWidget);
      expect(find.text('die Wohnung → $bangla'), findsOneWidget);
      expect(find.text('die Wohnung → $english · $bangla'), findsOneWidget);
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
      // `bangla` is nullable in the schema. No dangling "die Wohnung → ",
      // and Both still has the English to show.
      await pump(tester, sample: wohnung(bn: null));

      expect(find.textContaining('→'), findsNWidgets(2));
      expect(find.text('die Wohnung → $english'), findsNWidgets(2));
    });

    testWidgets('and with no sample at all the cards still choose', (
      tester,
    ) async {
      await pump(tester, noSample: true);

      expect(find.textContaining('→'), findsNothing);

      await tester.tap(find.text(l10n.onboardingMeaningBangla));
      await tester.pump();
      expect(
        settings.read(SettingKeys.meaningLanguage),
        MeaningLanguage.bangla,
      );
    });

    testWidgets('and if content.db fails, the page does not', (tester) async {
      // Held by Riverpod 3's `AsyncValue.value`, which is null on error. A
      // move to `requireValue` would throw here instead, on the one screen
      // where the learner has not seen the app work yet.
      await pump(tester, sampleThrows: true);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('→'), findsNothing);

      await tester.tap(find.text(l10n.onboardingMeaningEnglish));
      await tester.pump();
      expect(
        settings.read(SettingKeys.meaningLanguage),
        MeaningLanguage.english,
      );
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

      await tester.tap(find.widgetWithText(DpButton, l10n.continueAction));
      await tester.tap(find.widgetWithText(DpButton, l10n.back));
      await tester.pump();

      expect(<int>[continued, back], <int>[1, 1]);
    });

    testWidgets('page 2 has no Skip', (tester) async {
      // The language is the one choice made deliberately rather than
      // defaulted — Skip starts on page 3.
      await pump(tester);

      expect(find.widgetWithText(DpButton, l10n.skip), findsNothing);
    });
  });

  group('it is built from the design system', () {
    testWidgets('no Material chrome', (tester) async {
      await pump(tester);

      expect(find.byType(AdaptiveScaffold), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(RadioListTile<MeaningLanguage>), findsNothing);
    });

    testWidgets('and glass and dark render it', (tester) async {
      for (final mode in <DpMode>[DpMode.dark, DpMode.glass]) {
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
        tester.getSemantics(find.text(l10n.onboardingMeaningBangla)),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
          // The sample is read with the name — it is what the choice means.
          label: '${l10n.onboardingMeaningBangla}\ndie Wohnung → $bangla',
        ),
      );
      expect(
        tester.getSemantics(find.text(l10n.onboardingMeaningEnglish)),
        matchesSemantics(
          isButton: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
          label: '${l10n.onboardingMeaningEnglish}\ndie Wohnung → $english',
        ),
      );

      handle.dispose();
    });
  });
}
