import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// theming.md: the seven-role scale, and "Bangla is set one step larger at the
/// same role". accessibility-performance.md: "Text scaling to 200 %; long
/// compounds soft-hyphenate" and the de-DE / bn-BD locale tagging so TalkBack
/// and VoiceOver switch voices.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
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
        const DpText('die Wohnung · ফ্ল্যাট', role: DpTextRole.body),
      );
      final children =
          (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan)
              .children!
              .cast<TextSpan>();

      expect(children.first.locale, const Locale('de', 'DE'));
      expect(children.last.locale, const Locale('bn', 'BD'));
    });
  });

  group('long German compounds', () {
    test('a short word is left alone', () {
      expect(DpScript.allowBreaks('Wohnung'), 'Wohnung');
    });

    test('an over-long compound gains exactly one break opportunity', () {
      const word = 'Wohnungsgeberbestaetigung';
      final broken = DpScript.allowBreaks(word);

      expect(broken, isNot(word));
      expect(
        DpScript.softHyphen.allMatches(broken).length,
        1,
        reason:
            'one conservative break beats scattering them through a word the '
            'learner is trying to memorise',
      );
      expect(
        broken.replaceAll(DpScript.softHyphen, ''),
        word,
        reason: 'the word itself must be unchanged',
      );
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
    testWidgets('a long headword does not overflow at 100, 150 or 200 %', (
      tester,
    ) async {
      for (final scale in <double>[1, 1.5, 2]) {
        await pump(
          tester,
          const SizedBox(
            width: 300,
            child: DpHeadword('Wohnungsgeberbestaetigung', article: 'die'),
          ),
          textScale: scale,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'the headword overflowed at ${scale}x',
        );
      }
    });

    testWidgets('the headword scales down rather than clipping', (
      tester,
    ) async {
      await pump(
        tester,
        const SizedBox(
          width: 200,
          child: DpHeadword('Wohnungsgeberbestaetigung', article: 'die'),
        ),
        textScale: 2,
      );

      expect(find.byType(FittedBox), findsOneWidget);
      expect(
        tester.getSize(find.byType(FittedBox)).width,
        lessThanOrEqualTo(200),
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
}
