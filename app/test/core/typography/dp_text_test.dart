import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';

import 'dart:ui' show LocaleStringAttribute;

import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart' show appLocalizationsDelegates;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show AttributedString;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../text_clipping.dart';

/// theming.md: the seven-role scale, and "Bangla is set one step larger at the
/// same role". accessibility-performance.md: "Text scaling to 200 %; long
/// compounds soft-hyphenate" and the de-DE / bn-BD locale tagging so TalkBack
/// and VoiceOver switch voices.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double textScale = 1,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('script runs', () {
    test('a German-only string is one Latin run', () {
      expect(DpScript.runs('die Wohnung'), [('die Wohnung', false)]);
      expect(DpScript.hasBengali('die Wohnung'), isFalse);
    });

    test('a Bangla-only string is one Bengali run', () {
      expect(DpScript.runs('ফ্ল্যাট'), [('ফ্ল্যাট', true)]);
    });

    test('a mixed string splits, and the separator adds no third run', () {
      const mixed = 'die Wohnung · ফ্ল্যাট';
      final runs = DpScript.runs(mixed);

      expect(runs, hasLength(2));
      expect(runs.first.$2, isFalse);
      expect(runs.last.$2, isTrue);
      expect(
        runs.map((r) => r.$1).join(),
        mixed,
        reason: 'splitting must not lose or duplicate a character',
      );
    });

    test(
      'the pronunciation caption from study-session.md splits correctly',
      () {
        // "Nomen · die Rechnung, -en · /রেশনুং/"
        const caption =
            'Nomen · die Rechnung, -en · '
            '/রেশনুং/';
        final runs = DpScript.runs(caption);

        expect(runs.map((r) => r.$1).join(), caption);
        expect(runs.where((r) => r.$2), hasLength(1));
      },
    );

    test('a leading separator waits for the first letter', () {
      // Otherwise '  Bangla' opens a Latin run for the spaces.
      final runs = DpScript.runs('  ফ্ল');
      expect(runs, hasLength(1));
      expect(runs.single.$2, isTrue);
      expect(runs.single.$1, '  ফ্ল');
    });

    test('an empty string has no runs', () {
      expect(DpScript.runs(''), isEmpty);
    });
  });

  group('Bangla is one step larger at the same role', () {
    test('every role maps to the next one up, and display is the ceiling', () {
      expect(DpTextRole.caption.oneStepLarger, DpTextRole.label);
      expect(DpTextRole.label.oneStepLarger, DpTextRole.body);
      expect(DpTextRole.body.oneStepLarger, DpTextRole.bodyLarge);
      expect(DpTextRole.bodyLarge.oneStepLarger, DpTextRole.title);
      expect(DpTextRole.title.oneStepLarger, DpTextRole.headline);
      expect(DpTextRole.headline.oneStepLarger, DpTextRole.display);
      expect(
        DpTextRole.display.oneStepLarger,
        DpTextRole.display,
        reason: 'display is already the largest role — it cannot step up',
      );
    });

    testWidgets('#166 at every role, the Bangla run is set one role larger '
        'than the German beside it', (tester) async {
      final tokens = DpTokens.light();
      for (final role in DpTextRole.values) {
        await pump(tester, DpText('die Wohnung · ফ্ল্যাট', role: role));
        final runs =
            (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan)
                .children!
                .cast<TextSpan>();
        expect(
          runs.first.style!.fontSize,
          role.token(tokens.typography).size,
          reason: '$role German',
        );
        expect(
          runs.last.style!.fontSize,
          role.oneStepLarger.token(tokens.typography).size,
          reason: '$role Bangla',
        );
      }
    });

    testWidgets('an explicit weight reaches both scripts, not just the Latin', (
      tester,
    ) async {
      await pump(
        tester,
        const DpText(
          'die Wohnung · ফ্ল্যাট',
          role: DpTextRole.body,
          weight: 700,
        ),
      );
      final children =
          (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan)
              .children!
              .cast<TextSpan>();

      for (final span in children) {
        expect(
          span.style!.fontVariations!.single.value,
          700,
          reason:
              'a weight dropped on mixed strings is a weight dropped on '
              'most of this app, since most of its copy is mixed',
        );
      }
    });

    testWidgets('German renders at its role and Bangla one step above it', (
      tester,
    ) async {
      await pump(
        tester,
        const DpText('die Wohnung · ফ্ল্যাট', role: DpTextRole.body),
      );

      final span = tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;
      final children = span.children!.cast<TextSpan>();
      expect(children, hasLength(2));

      const type = DpTypeTokens.defaults;
      expect(children.first.style!.fontSize, type.body.size, reason: 'German');
      expect(
        children.last.style!.fontSize,
        type.bodyLarge.size,
        reason: 'Bangla one step up: 15 becomes 17, not 15',
      );
    });

    testWidgets('a German-only string stays a plain Text at its role', (
      tester,
    ) async {
      await pump(tester, const DpText('die Wohnung', role: DpTextRole.body));
      final text = tester.widget<Text>(find.byType(Text));

      expect(text.textSpan, isNull, reason: 'no need to split a single script');
      expect(text.style!.fontSize, DpTypeTokens.defaults.body.size);
    });

    testWidgets('each run carries its own locale for the screen reader', (
      tester,
    ) async {
      await pump(
        tester,
        const DpText(
          'die Wohnung · ফ্ল্যাট',
          role: DpTextRole.body,
          german: true,
        ),
      );
      final children =
          (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan)
              .children!
              .cast<TextSpan>();

      expect(children.first.locale, const Locale('de', 'DE'));
      expect(children.last.locale, const Locale('bn', 'BD'));
    });
  });

  group('#162 screen-reader voices', () {
    // What TalkBack and VoiceOver are given: the words, and the stretches
    // each voice reads.
    Future<AttributedString> said(
      WidgetTester tester,
      Widget child, {
      Locale locale = const Locale('en'),
    }) async {
      await pump(tester, child, locale: locale);
      // From its paragraph: a hyphenated text's first box is the one that
      // breaks its lines (#419), which has no node of its own.
      return tester
          .getSemantics(
            find.descendant(
              of: find.byWidget(child),
              matching: find.byType(RichText),
            ),
          )
          .attributedLabel;
    }

    List<(String, Locale)> voices(AttributedString label) => <(String, Locale)>[
      for (final attribute in label.attributes)
        if (attribute is LocaleStringAttribute)
          (
            label.string.substring(attribute.range.start, attribute.range.end),
            attribute.locale,
          ),
    ];

    testWidgets('#162 Y01 the course German is read in a German voice', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final label = await said(
        tester,
        const DpText(
          'Ich wohne in Berlin.',
          role: DpTextRole.body,
          german: true,
        ),
      );
      expect(label.string, 'Ich wohne in Berlin.');
      expect(voices(label), <(String, Locale)>[
        ('Ich wohne in Berlin.', DpScript.deDE),
      ]);
      semantics.dispose();
    });

    testWidgets("#162 Y01 the app's copy is untagged, so it is read in the "
        "app's language, not in German", (tester) async {
      final semantics = tester.ensureSemantics();
      final copy = await said(
        tester,
        const DpText('Continue', role: DpTextRole.body),
      );
      expect(copy.string, 'Continue');
      expect(voices(copy), isEmpty);

      final mixed = await said(
        tester,
        const DpText('Meaning · অর্থ', role: DpTextRole.body),
      );
      expect(voices(mixed), <(String, Locale)>[('অর্থ', DpScript.bnBD)]);
      semantics.dispose();
    });

    testWidgets('#162 Y01 German with its Bangla: each in its own voice', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final label = await said(
        tester,
        const DpText(
          'die Wohnung · ফ্ল্যাট',
          role: DpTextRole.body,
          german: true,
        ),
      );
      expect(voices(label), <(String, Locale)>[
        ('die Wohnung · ', DpScript.deDE),
        ('ফ্ল্যাট', DpScript.bnBD),
      ]);
      semantics.dispose();
    });

    testWidgets('#162 Y01 a soft hyphen offered for a break is not read', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final label = await said(
        tester,
        const DpText(
          'Haftpflichtversicherung',
          role: DpTextRole.body,
          allowBreaks: true,
          german: true,
        ),
      );
      expect(label.string, 'Haftpflichtversicherung');
      expect(voices(label).single.$2, DpScript.deDE);
      semantics.dispose();
    });

    testWidgets('#162 Y01 the headword: article and gender, the German in a '
        'German voice ("die Wohnung, feminine")', (tester) async {
      final semantics = tester.ensureSemantics();
      final die = await said(
        tester,
        const DpHeadword('Wohnung', article: 'die', plural: 'Wohnungen'),
      );
      expect(die.string, 'die Wohnung, feminine');
      expect(voices(die), <(String, Locale)>[('die Wohnung', DpScript.deDE)]);

      final der = await said(tester, const DpHeadword('Tisch', article: 'der'));
      expect(der.string, 'der Tisch, masculine');

      final das = await said(tester, const DpHeadword('Haus', article: 'das'));
      expect(das.string, 'das Haus, neuter');
      semantics.dispose();
    });

    testWidgets('#162 Y01 die without a plural says no gender: a plural-only '
        'noun takes die too', (tester) async {
      final semantics = tester.ensureSemantics();
      final label = await said(
        tester,
        const DpHeadword('Leute', article: 'die'),
      );
      expect(label.string, 'die Leute');
      semantics.dispose();
    });

    testWidgets("#162 Y01 the gender is in the app's language: Bangla", (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final label = await said(
        tester,
        const DpHeadword('Tisch', article: 'der'),
        locale: const Locale('bn'),
      );
      expect(label.string, 'der Tisch, পুংলিঙ্গ');
      expect(voices(label), <(String, Locale)>[('der Tisch', DpScript.deDE)]);
      semantics.dispose();
    });

    testWidgets('#162 Y01 no article, no gender: a verb is only itself', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final label = await said(tester, const DpHeadword('schnell'));
      expect(label.string, 'schnell');
      expect(voices(label), <(String, Locale)>[('schnell', DpScript.deDE)]);
      semantics.dispose();
    });
  });

  group('#419 a hyphen where a headword breaks at a syllable', () {
    // The text the headword's paragraph draws.
    String drawn(WidgetTester tester) => tester
        .renderObject<RenderParagraph>(find.byType(RichText))
        .text
        .toPlainText(includeSemanticsLabels: false)
        .replaceAll(DpScript.softHyphen, '');

    testWidgets('#419 a line that ends at a syllable ends in "-", and the '
        'word is read whole', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        const SizedBox(
          width: 220,
          child: DpHeadword(
            'Geschwindigkeitsbegrenzung',
            article: 'die',
            plural: 'Geschwindigkeitsbegrenzungen',
          ),
        ),
      );
      final lines = drawn(tester).split('\n');
      expect(lines.length, greaterThan(1));
      // Every line but the last ends at a syllable, with its "-", or is the
      // article alone, which ends at a space.
      for (final line in lines.take(lines.length - 1)) {
        expect(line == 'die' || line.endsWith('-'), isTrue, reason: line);
      }
      expect(
        lines.join(' ').replaceAll('- ', ''),
        'die Geschwindigkeitsbegrenzung',
      );
      expect(
        tester.getSemantics(find.byType(DpHeadword)).label,
        'die Geschwindigkeitsbegrenzung, feminine',
      );
      semantics.dispose();
    });

    testWidgets('#419 a word that fits has no hyphen, and no line runs past '
        'its box', (tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 400,
          child: DpHeadword('Wohnung', article: 'die'),
        ),
      );
      expect(drawn(tester), 'die Wohnung');

      await pump(
        tester,
        const SizedBox(
          width: 160,
          child: DpHeadword('Haftpflichtversicherung', role: DpTextRole.title),
        ),
      );
      expect(drawn(tester), contains('-'));
      // Each line it drew is one line: none ran past the box and wrapped
      // again, at a syllable or anywhere else.
      expectNoWordBroken(tester, syllables: false);
      expect(tester.getSize(find.byType(DpHeadword)).width, 160);
    });
  });

  group('#419 a hyphen in running text too', () {
    testWidgets('#419 DpText: a line that ends at a syllable shows "-", and '
        'a screen reader hears the words as they are, in their voice', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        const SizedBox(
          width: 150,
          child: DpText(
            'die Haftpflichtversicherung zahlt',
            role: DpTextRole.body,
            allowBreaks: true,
            german: true,
          ),
        ),
      );
      final drawn = tester
          .renderObject<RenderParagraph>(find.byType(RichText))
          .text
          .toPlainText(includeSemanticsLabels: false);
      expect(drawn, contains('-\n'));
      expectNoWordBroken(tester, syllables: false);

      final label = tester.getSemantics(find.byType(RichText)).attributedLabel;
      expect(label.string, 'die Haftpflichtversicherung zahlt');
      expect(
        label.attributes.whereType<LocaleStringAttribute>().single.locale,
        DpScript.deDE,
      );
      semantics.dispose();
    });
  });

  group('long German compounds', () {
    test('a short word is left alone', () {
      expect(DpScript.allowBreaks('Wohnung'), 'Wohnung');
    });

    test('#405 a long compound breaks where a syllable begins', () {
      String shown(String word) =>
          DpScript.allowBreaks(word).replaceAll(DpScript.softHyphen, '|');
      expect(shown('Haftpflichtversicherung'), 'Haft|pflicht|ver|si|che|rung');
      expect(shown('Donaudampfschifffahrt'), 'Do|nau|dampf|schiff|fahrt');
      expect(shown('Reiseversicherung'), 'Rei|se|ver|si|che|rung');
      expect(
        shown('Geschwindigkeitsbegrenzung'),
        'Ge|schwin|dig|keits|be|gren|zung',
      );
      expect(shown('Wohnung'), 'Wohnung', reason: 'short: left alone');
      for (final word in <String>[
        'Haftpflichtversicherung',
        'Geschwindigkeitsbegrenzung',
      ]) {
        expect(
          DpScript.allowBreaks(word).replaceAll(DpScript.softHyphen, ''),
          word,
          reason: 'the word itself is unchanged',
        );
      }
    });

    test('#405 never before a vowel, and never splitting ch, ck or sch', () {
      for (final word in <String>[
        'Reiseversicherung',
        'Krankenversicherung',
        'Arbeitnehmerüberlassung',
        'Zuckerbäckerei',
        'Wohnungsgeberbestaetigung',
      ]) {
        final broken = DpScript.allowBreaks(word);
        for (final match in DpScript.softHyphen.allMatches(broken)) {
          final after = broken[match.end];
          final before = broken[match.start - 1].toLowerCase();
          expect(
            'aeiouyäöü'.contains(after.toLowerCase()),
            isFalse,
            reason: '$broken: a syllable starts with its consonant',
          );
          expect(
            <String>['c', 's'].contains(before) &&
                <String>['h', 'k'].contains(after),
            isFalse,
            reason: '$broken splits ch, ck or sch',
          );
        }
      }
    });

    test('content that already carries soft hyphens is not second-guessed', () {
      const authored = 'Woh­nungs­geber';
      expect(DpScript.allowBreaks(authored), authored);
    });

    testWidgets('breaks are off by default, so a headword is never broken up', (
      tester,
    ) async {
      await pump(
        tester,
        const DpText('Wohnungsgeberbestaetigung', role: DpTextRole.body),
      );
      expect(
        tester.widget<Text>(find.byType(Text)).data,
        isNot(contains(DpScript.softHyphen)),
      );
    });
  });

  group('text scaling to 200 %', () {
    testWidgets(
      'a long headword keeps its size at 200 % instead of shrinking',
      (tester) async {
        // The earlier version of this test only asserted that nothing threw.
        // FittedBox never overflows — it scales until it fits — so it passed
        // while the headword rendered about 3 px tall. Assert the size instead.
        await pump(
          tester,
          const SizedBox(
            width: 200,
            child: DpHeadword('Wohnungsgeberbestaetigung', article: 'die'),
          ),
          textScale: 2,
        );

        expect(
          find.byType(FittedBox),
          findsNothing,
          reason: 'scaling down to fit inverts the setting the learner chose',
        );

        // The root span inherits from DefaultTextStyle; the roles live on the
        // children, which is where the headword's own size is set.
        final span =
            tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;
        for (final child in span.children!.cast<TextSpan>()) {
          expect(
            child.style!.fontSize,
            DpTypeTokens.defaults.display.size,
            reason:
                'the headword stays at its role; the scaler makes it bigger',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a long headword wraps rather than clipping', (tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 200,
          child: DpHeadword('Wohnungsgeberbestaetigung', article: 'die'),
        ),
        textScale: 2,
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText),
      );
      expect(
        paragraph.size.height,
        greaterThan(DpTypeTokens.defaults.display.height),
        reason: 'a compound too wide for the card must run onto more lines',
      );
    });

    testWidgets('the article is printed, not only coloured', (tester) async {
      await pump(tester, const DpHeadword('Wohnung', article: 'die'));
      final span = tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;

      expect(span.toPlainText(), 'die Wohnung');
      expect(
        (span.children!.first as TextSpan).style!.color,
        DpPalette.light.dieText,
        reason:
            'gender is carried by colour AND by the printed article — '
            'accessibility-performance.md forbids colour alone',
      );
    });

    testWidgets('a word with no article renders without one', (tester) async {
      await pump(tester, const DpHeadword('schnell'));
      final span = tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;
      expect(span.toPlainText(), 'schnell');
    });
  });

  testWidgets('every role reads its size from the tokens, in every mode', (
    tester,
  ) async {
    for (final (theme, tokens) in <(ThemeData, DpTokens)>[
      (AppTheme.light(), DpTokens.light()),
      (AppTheme.dark(), DpTokens.dark()),
      (AppTheme.glass(), DpTokens.glass()),
    ]) {
      for (final role in DpTextRole.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(body: DpText('Revise', role: role)),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.widget<Text>(find.byType(Text)).style!.fontSize,
          role.token(tokens.typography).size,
        );
      }
    }
  });

  testWidgets("#280 a cut drops the joiner before its '…': never "
      "'Argumentation &…'", (tester) async {
    for (final (title, shown) in <(String, String)>[
      ('Argumentation & Diskussion im Alltag', 'Argumentation…'),
      ('Wohnen · Haushalt und Nachbarschaft', 'Wohnen…'),
      ('Doctor, pharmacy and emergency care', 'Doctor…'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: DpOneLine(title, role: DpTextRole.title),
              ),
            ),
          ),
        ),
      );
      expect(tester.widget<Text>(find.byType(Text)).data, shown, reason: title);
    }
  });
}
