import 'dart:ui' show LocaleStringAttribute;

import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show AttributedString;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/l10n/generated/app_localizations.dart';
import 'package:sogda/main.dart' show appLocalizationsDelegates;

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
      expect(SgScript.runs('die Wohnung'), [('die Wohnung', false)]);
      expect(SgScript.hasBengali('die Wohnung'), isFalse);
    });

    test('a Bangla-only string is one Bengali run', () {
      expect(SgScript.runs('ফ্ল্যাট'), [('ফ্ল্যাট', true)]);
    });

    test('a mixed string splits, and the separator adds no third run', () {
      const mixed = 'die Wohnung · ফ্ল্যাট';
      final runs = SgScript.runs(mixed);

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
        final runs = SgScript.runs(caption);

        expect(runs.map((r) => r.$1).join(), caption);
        expect(runs.where((r) => r.$2), hasLength(1));
      },
    );

    test('a leading separator waits for the first letter', () {
      // Otherwise '  Bangla' opens a Latin run for the spaces.
      final runs = SgScript.runs('  ফ্ল');
      expect(runs, hasLength(1));
      expect(runs.single.$2, isTrue);
      expect(runs.single.$1, '  ফ্ল');
    });

    test('an empty string has no runs', () {
      expect(SgScript.runs(''), isEmpty);
    });
  });

  test('#573 typing past 130 %, what is asked is one role smaller: every '
      'role maps to the next one down, caption is the floor, and a step down '
      'then up is the role again', () {
    expect(SgTextRole.display.oneStepSmaller, SgTextRole.headline);
    expect(SgTextRole.headline.oneStepSmaller, SgTextRole.title);
    expect(SgTextRole.title.oneStepSmaller, SgTextRole.bodyLarge);
    expect(SgTextRole.bodyLarge.oneStepSmaller, SgTextRole.body);
    expect(SgTextRole.body.oneStepSmaller, SgTextRole.label);
    expect(SgTextRole.label.oneStepSmaller, SgTextRole.caption);
    expect(
      SgTextRole.caption.oneStepSmaller,
      SgTextRole.caption,
      reason: 'caption is already the smallest role',
    );
    for (final role in SgTextRole.values.where(
      (role) => role != SgTextRole.caption,
    )) {
      expect(role.oneStepSmaller.oneStepLarger, role, reason: '$role');
    }
  });

  group('Bangla is one step larger at the same role', () {
    test('every role maps to the next one up, and display is the ceiling', () {
      expect(SgTextRole.caption.oneStepLarger, SgTextRole.label);
      expect(SgTextRole.label.oneStepLarger, SgTextRole.body);
      expect(SgTextRole.body.oneStepLarger, SgTextRole.bodyLarge);
      expect(SgTextRole.bodyLarge.oneStepLarger, SgTextRole.title);
      expect(SgTextRole.title.oneStepLarger, SgTextRole.headline);
      expect(SgTextRole.headline.oneStepLarger, SgTextRole.display);
      expect(
        SgTextRole.display.oneStepLarger,
        SgTextRole.display,
        reason: 'display is already the largest role — it cannot step up',
      );
    });

    testWidgets('#166 at every role, the Bangla run is set one role larger '
        'than the German beside it', (tester) async {
      final tokens = SgTokens.light();
      for (final role in SgTextRole.values) {
        await pump(tester, SgText('die Wohnung · ফ্ল্যাট', role: role));
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
        const SgText(
          'die Wohnung · ফ্ল্যাট',
          role: SgTextRole.body,
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

    testWidgets('#1063 Bangla keeps the role\'s own weight: a caption is 400 '
        'and a label 600, as in English; SgOneLine agrees', (tester) async {
      for (final (role, weight) in <(SgTextRole, double)>[
        (SgTextRole.caption, 400),
        (SgTextRole.label, 600),
        (SgTextRole.bodyLarge, 400),
      ]) {
        for (final widget in <Widget>[
          SgText('A1.1 · ফ্ল্যাট', role: role),
          SgOneLine('A1.1 · ফ্ল্যাট', role: role),
        ]) {
          await pump(tester, SizedBox(width: 300, child: widget));
          final spans = <TextSpan>[];
          tester
              .renderObject<RenderParagraph>(find.byType(RichText))
              .text
              .visitChildren((span) {
                if (span is TextSpan && span.text != null) spans.add(span);
                return true;
              });
          final what = '$role ${widget.runtimeType}';
          expect(
            spans.any((s) => SgScript.hasBengali(s.text!)),
            isTrue,
            reason: what,
          );
          for (final span in spans) {
            expect(
              span.style!.fontVariations!.single.value,
              weight,
              reason: '$what "${span.text}"',
            );
          }
        }
      }
    });

    testWidgets('German renders at its role and Bangla one step above it', (
      tester,
    ) async {
      await pump(
        tester,
        const SgText('die Wohnung · ফ্ল্যাট', role: SgTextRole.body),
      );

      final span = tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;
      final children = span.children!.cast<TextSpan>();
      expect(children, hasLength(2));

      const type = SgTypeTokens.defaults;
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
      await pump(tester, const SgText('die Wohnung', role: SgTextRole.body));
      final text = tester.widget<Text>(find.byType(Text));

      expect(text.textSpan, isNull, reason: 'no need to split a single script');
      expect(text.style!.fontSize, SgTypeTokens.defaults.body.size);
    });

    testWidgets('each run carries its own locale for the screen reader', (
      tester,
    ) async {
      await pump(
        tester,
        const SgText(
          'die Wohnung · ফ্ল্যাট',
          role: SgTextRole.body,
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
        const SgText(
          'Ich wohne in Berlin.',
          role: SgTextRole.body,
          german: true,
        ),
      );
      expect(label.string, 'Ich wohne in Berlin.');
      expect(voices(label), <(String, Locale)>[
        ('Ich wohne in Berlin.', SgScript.deDE),
      ]);
      semantics.dispose();
    });

    testWidgets("#162 Y01 the app's copy is untagged, so it is read in the "
        "app's language, not in German", (tester) async {
      final semantics = tester.ensureSemantics();
      final copy = await said(
        tester,
        const SgText('Continue', role: SgTextRole.body),
      );
      expect(copy.string, 'Continue');
      expect(voices(copy), isEmpty);

      final mixed = await said(
        tester,
        const SgText('Meaning · অর্থ', role: SgTextRole.body),
      );
      expect(voices(mixed), <(String, Locale)>[('অর্থ', SgScript.bnBD)]);
      semantics.dispose();
    });

    testWidgets('#162 Y01 German with its Bangla: each in its own voice', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final label = await said(
        tester,
        const SgText(
          'die Wohnung · ফ্ল্যাট',
          role: SgTextRole.body,
          german: true,
        ),
      );
      expect(voices(label), <(String, Locale)>[
        ('die Wohnung · ', SgScript.deDE),
        ('ফ্ল্যাট', SgScript.bnBD),
      ]);
      semantics.dispose();
    });

    testWidgets('#162 Y01 a soft hyphen offered for a break is not read', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final label = await said(
        tester,
        const SgText(
          'Haftpflichtversicherung',
          role: SgTextRole.body,
          allowBreaks: true,
          german: true,
        ),
      );
      expect(label.string, 'Haftpflichtversicherung');
      expect(voices(label).single.$2, SgScript.deDE);
      semantics.dispose();
    });

    testWidgets('#162 Y01 the headword: article and gender, the German in a '
        'German voice ("die Wohnung, feminine")', (tester) async {
      final semantics = tester.ensureSemantics();
      final die = await said(
        tester,
        const SgHeadword('Wohnung', article: 'die', plural: 'Wohnungen'),
      );
      expect(die.string, 'die Wohnung, feminine');
      expect(voices(die), <(String, Locale)>[('die Wohnung', SgScript.deDE)]);

      final der = await said(tester, const SgHeadword('Tisch', article: 'der'));
      expect(der.string, 'der Tisch, masculine');

      final das = await said(tester, const SgHeadword('Haus', article: 'das'));
      expect(das.string, 'das Haus, neuter');
      semantics.dispose();
    });

    testWidgets('#162 Y01 die without a plural says no gender: a plural-only '
        'noun takes die too', (tester) async {
      final semantics = tester.ensureSemantics();
      final label = await said(
        tester,
        const SgHeadword('Leute', article: 'die'),
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
        const SgHeadword('Tisch', article: 'der'),
        locale: const Locale('bn'),
      );
      expect(label.string, 'der Tisch, পুংলিঙ্গ');
      expect(voices(label), <(String, Locale)>[('der Tisch', SgScript.deDE)]);
      semantics.dispose();
    });

    testWidgets('#162 Y01 no article, no gender: a verb is only itself', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final label = await said(tester, const SgHeadword('schnell'));
      expect(label.string, 'schnell');
      expect(voices(label), <(String, Locale)>[('schnell', SgScript.deDE)]);
      semantics.dispose();
    });
  });

  group('#419 a hyphen where a headword breaks at a syllable', () {
    // The text the headword's paragraph draws.
    String drawn(WidgetTester tester) => tester
        .renderObject<RenderParagraph>(find.byType(RichText))
        .text
        .toPlainText(includeSemanticsLabels: false)
        .replaceAll(SgScript.softHyphen, '');

    testWidgets('#419 a line that ends at a syllable ends in "-", and the '
        'word is read whole', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        const SizedBox(
          width: 220,
          child: SgHeadword(
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
        tester.getSemantics(find.byType(SgHeadword)).label,
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
          child: SgHeadword('Wohnung', article: 'die'),
        ),
      );
      expect(drawn(tester), 'die Wohnung');

      await pump(
        tester,
        const SizedBox(
          width: 160,
          child: SgHeadword('Haftpflichtversicherung', role: SgTextRole.title),
        ),
      );
      expect(drawn(tester), contains('-'));
      // Each line it drew is one line: none ran past the box and wrapped
      // again, at a syllable or anywhere else.
      expectNoWordBroken(tester, syllables: false);
      expect(tester.getSize(find.byType(SgHeadword)).width, 160);
    });
  });

  group("#419 the lines are the headword's own", () {
    // A line break between two Bangla letters: the word broken, not shrunk
    // whole (#522). A break after the opening "/" doesn't count.
    final insideBangla = RegExp('[ঀ-৿‌]\n[ঀ-৿]');

    // Where each drawn line ends: after the headword's own newline, or the
    // paragraph broke it by itself, at a syllable with no "-" or anywhere.
    List<String> lineEnds(WidgetTester tester) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText),
      );
      final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
      final painter = TextPainter(
        text: paragraph.text,
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
      )..layout(maxWidth: paragraph.size.width);
      addTearDown(painter.dispose);
      final ends = <String>[];
      var at = 0;
      while (at < text.length) {
        final line = painter.getLineBoundary(TextPosition(offset: at));
        if (line.end <= at) break;
        final end = line.end < text.length && text[line.end] == '\n'
            ? line.end + 1
            : line.end;
        if (end < text.length) ends.add(text.substring(at, end));
        at = end;
      }
      return ends;
    }

    testWidgets('#419 at every width, each line ends where the headword '
        'ended it, never at a bare soft hyphen', (tester) async {
      // From the width the widest syllable, "nungs-", fits: narrower, one
      // syllable is wider than the box, and only a letter break is left.
      for (var width = 170.0; width <= 420; width += 7) {
        await pump(
          tester,
          SizedBox(
            width: width,
            child: const SgHeadword(
              'Wohnungsgeberbestaetigung',
              article: 'die',
            ),
          ),
        );
        for (final line in lineEnds(tester)) {
          expect(line, endsWith('\n'), reason: 'at $width: "$line"');
        }
      }
    });

    testWidgets('#502 German among Bangla hyphenates too: each line ends '
        'where the text ended it, each run keeps its style, and a screen '
        'reader hears each whole, in its own voice', (tester) async {
      final semantics = tester.ensureSemantics();
      const caption =
          'die Geschwindigkeitsbegrenzung · /গেশভিন্ডিশকাইটসবেগ্রেনৎসুং/';
      Future<void> at(double width) => pump(
        tester,
        SizedBox(
          width: width,
          child: SgText(
            SgScript.allowBreaks(caption, threshold: 4),
            role: SgTextRole.body,
            german: true,
          ),
        ),
      );
      // From the width the Bangla fits: it has no syllables to break at,
      // and narrower only a letter break is left.
      for (var width = 210.0; width <= 390; width += 1) {
        await at(width);
        for (final line in lineEnds(tester)) {
          expect(line, endsWith('\n'), reason: 'at $width: "$line"');
        }
      }
      await at(210);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText),
      );
      expect(
        paragraph.text.toPlainText(includeSemanticsLabels: false),
        contains('-\n'),
      );
      final sizes = <String, double?>{};
      paragraph.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) {
          sizes[SgScript.hasBengali(span.text!) ? 'bn' : 'de'] =
              span.style?.fontSize;
        }
        return true;
      });
      expect(sizes['bn']!, greaterThan(sizes['de']!), reason: 'one role up');

      final label = tester.getSemantics(find.byType(RichText)).attributedLabel;
      expect(label.string, caption);
      expect(
        label.attributes.whereType<LocaleStringAttribute>().map(
          (a) => (label.string.substring(a.range.start, a.range.end), a.locale),
        ),
        containsAll(<(String, Locale)>[
          ('die Geschwindigkeitsbegrenzung · /', SgScript.deDE),
          ('গেশভিন্ডিশকাইটসবেগ্রেনৎসুং/', SgScript.bnBD),
        ]),
      );
      semantics.dispose();
    });

    testWidgets('#502 German after Bangla: a break in a later run is drawn '
        'there, in that run, which keeps its style and voice', (tester) async {
      final semantics = tester.ensureSemantics();
      const text = 'গেশভিন্ডিশকাইট · die Geschwindigkeitsbegrenzung';
      Future<void> at(double width) => pump(
        tester,
        SizedBox(
          width: width,
          child: SgText(
            SgScript.allowBreaks(text, threshold: 4),
            role: SgTextRole.body,
            german: true,
          ),
        ),
      );
      for (var width = 150.0; width <= 330; width += 1) {
        await at(width);
        for (final line in lineEnds(tester)) {
          expect(line, endsWith('\n'), reason: 'at $width: "$line"');
        }
      }
      await at(150);
      final spans = <TextSpan>[];
      tester
          .renderObject<RenderParagraph>(find.byType(RichText))
          .text
          .visitChildren((span) {
            if (span is TextSpan && span.text != null) spans.add(span);
            return true;
          });
      final bangla = spans.singleWhere((s) => SgScript.hasBengali(s.text!));
      // Found by what it says: its drawn text has the lines' "-\n".
      final german = spans.singleWhere(
        (s) => s.semanticsLabel!.contains('Geschwindigkeitsbegrenzung'),
      );
      expect(spans.indexOf(german), greaterThan(spans.indexOf(bangla)));
      expect(german.text, contains('-\n'));
      expect(german.locale, SgScript.deDE);
      expect(german.style!.fontSize, lessThan(bangla.style!.fontSize!));
      expect(tester.getSemantics(find.byType(RichText)).label, text);
      semantics.dispose();
    });

    testWidgets('#504 a caption with only a pronunciation, no long German to '
        'offer a soft hyphen, breaks it between aksharas too: its caller '
        'asks (breakTooWide)', (tester) async {
      // Vergangenheitsbewältigung has no forms: "Nomen · /…/".
      const caption = 'Nomen · /ফেয়াগাঙেনহাইট্‌সবেভেল্টিগুং/';
      Future<String> drawnAt(double width, {required bool asked}) async {
        await pump(
          tester,
          SizedBox(
            width: width,
            child: SgText(
              SgScript.allowBreaks(caption),
              role: SgTextRole.body,
              breakTooWide: asked,
            ),
          ),
        );
        return tester
            .renderObject<RenderParagraph>(find.byType(RichText))
            .text
            .toPlainText(includeSemanticsLabels: false);
      }

      expect(SgScript.allowBreaks(caption), caption, reason: 'no hyphen');
      for (var width = 110.0; width <= 300; width += 1) {
        await drawnAt(width, asked: true);
        for (final line in lineEnds(tester)) {
          expect(line, endsWith('\n'), reason: 'at $width: "$line"');
        }
      }
      // Too wide even at 80 %: it breaks between aksharas, with no "-"
      // (#522).
      final pron = (await drawnAt(120, asked: true)).split('/')[1];
      expect(pron, contains(insideBangla), reason: 'broken, not shrunk');
      expect(pron, isNot(contains('-')));
      expect(
        await drawnAt(120, asked: false),
        isNot(contains('\n')),
        reason: 'not asked, the paragraph breaks it at a letter, as before',
      );
    });

    testWidgets('#522 a Bangla word a little too wide for its line shrinks '
        'to fit it, whole; German beside it keeps its "-"', (tester) async {
      const caption = 'Nomen · /ফেয়াগাঙেনহাইট্‌সবেভেল্টিগুং/';
      final style = SgText.styleFor(SgTokens.light(), SgTextRole.body);
      // Its width at its own (Bangla, one role up) size, then a line 90 %
      // of it: too narrow for the word, wide enough for it at 90 %.
      final painter = TextPainter(
        text: TextSpan(
          text: 'ফেয়াগাঙেনহাইট্‌সবেভেল্টিগুং/',
          style: SgText.styleFor(
            SgTokens.light(),
            SgTextRole.body.oneStepLarger,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final width = painter.width * 0.9;
      painter.dispose();
      expect(style.fontSize, isNotNull);

      await pump(
        tester,
        SizedBox(
          width: width,
          child: const SgText(
            caption,
            role: SgTextRole.body,
            breakTooWide: true,
          ),
        ),
      );
      final spans = <TextSpan>[];
      tester
          .renderObject<RenderParagraph>(find.byType(RichText))
          .text
          .visitChildren((span) {
            if (span is TextSpan && span.text != null) spans.add(span);
            return true;
          });
      final bangla = spans.singleWhere((s) => SgScript.hasBengali(s.text!));
      expect(bangla.text, isNot(contains('\n')), reason: 'whole');
      expect(
        bangla.style!.fontSize,
        lessThan(
          SgText.styleFor(
            SgTokens.light(),
            SgTextRole.body.oneStepLarger,
          ).fontSize!,
        ),
        reason: 'shrunk',
      );
      expect(
        bangla.style!.fontSize,
        greaterThanOrEqualTo(
          SgText.styleFor(
                SgTokens.light(),
                SgTextRole.body.oneStepLarger,
              ).fontSize! *
              SgScript.banglaShrink,
        ),
      );
    });

    testWidgets('#504 #522 a Bangla pronunciation too wide for its line, even '
        'shrunk, breaks between aksharas with no "-", and is read whole', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      const caption =
          'die Geschwindigkeitsbegrenzung · '
          '/গেশ্ভিন্ডিশকাইট্‌সবেগ্রেন্‌ৎসুং/';
      Future<void> at(double width) => pump(
        tester,
        SizedBox(
          width: width,
          child: SgText(
            SgScript.allowBreaks(caption, threshold: 4),
            role: SgTextRole.body,
            german: true,
          ),
        ),
      );
      // From the width the widest akshara line fits, "গ্রেন্‌ৎ-".
      for (var width = 90.0; width <= 390; width += 1) {
        await at(width);
        for (final line in lineEnds(tester)) {
          expect(line, endsWith('\n'), reason: 'at $width: "$line"');
        }
      }
      await at(150);
      final drawn = tester
          .renderObject<RenderParagraph>(find.byType(RichText))
          .text
          .toPlainText(includeSemanticsLabels: false);
      final pron = drawn.split('/')[1];
      expect(pron, contains(insideBangla), reason: 'broken, not shrunk');
      expect(pron, isNot(contains('-')), reason: 'no "-" in Bangla (#522)');
      // Broken at the reduced size, the owner's order: shrink, then break.
      final spans = <TextSpan>[];
      tester
          .renderObject<RenderParagraph>(find.byType(RichText))
          .text
          .visitChildren((span) {
            if (span is TextSpan && span.text != null) spans.add(span);
            return true;
          });
      final own = SgText.styleFor(
        SgTokens.light(),
        SgTextRole.body.oneStepLarger,
      ).fontSize!;
      expect(
        spans.singleWhere((s) => SgScript.hasBengali(s.text!)).style!.fontSize,
        moreOrLessEquals(own * SgScript.banglaShrink),
      );
      expectNoWordBroken(tester);
      expect(
        tester.getSemantics(find.byType(RichText)).label,
        caption,
        reason: 'read whole',
      );
      semantics.dispose();
    });

    testWidgets('#419 lines that all end at spaces are given too: where '
        '"Wohnungsamt Ab" fits but not its "-", the paragraph left to itself '
        'would end the line at a bare syllable', (tester) async {
      for (var width = 80.0; width <= 200; width += 1) {
        await pump(
          tester,
          SizedBox(
            width: width,
            child: SgText(
              'Wohnungsamt Ab${SgScript.softHyphen}fahrt',
              role: SgTextRole.body,
              german: true,
            ),
          ),
        );
        for (final line in lineEnds(tester)) {
          expect(line, endsWith('\n'), reason: 'at $width: "$line"');
        }
      }
    });

    testWidgets('#419 a word too wide for its line breaks at a syllable, '
        'whatever its length: "selbstbewusst" (13) at display size', (
      tester,
    ) async {
      await pump(
        tester,
        const SizedBox(width: 220, child: SgHeadword('selbstbewusst')),
      );
      final lines = lineEnds(tester);
      expect(lines, isNotEmpty, reason: 'too wide for one line');
      for (final line in lines) {
        expect(line, endsWith('-\n'));
      }
    });

    testWidgets("#419 its intrinsic width is the word's on one line, not the "
        "last layout's lines", (tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 150,
          child: SgHeadword('Geschwindigkeitsbegrenzung', article: 'die'),
        ),
      );
      final box =
          tester.renderObject<RenderParagraph>(find.byType(RichText)).parent!
              as RenderBox;
      expect(box.getMaxIntrinsicWidth(double.infinity), greaterThan(300));
    });

    testWidgets('#419 under an ambient maxLines its height is the '
        "paragraph's own: one line, not the lines it would break", (
      tester,
    ) async {
      await pump(
        tester,
        SizedBox(
          width: 150,
          child: DefaultTextStyle.merge(
            maxLines: 1,
            child: SgText(
              SgScript.allowBreaks('die Haftpflichtversicherung zahlt'),
              role: SgTextRole.body,
              german: true,
            ),
          ),
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText),
      );
      final box = paragraph.parent! as RenderBox;
      expect(box.getMinIntrinsicHeight(150), paragraph.size.height);
    });
  });

  group('#419 a hyphen in running text too', () {
    testWidgets('#419 SgText: a line that ends at a syllable shows "-", and '
        'a screen reader hears the words as they are, in their voice', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        const SizedBox(
          width: 150,
          child: SgText(
            'die Haftpflichtversicherung zahlt',
            role: SgTextRole.body,
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
        SgScript.deDE,
      );
      semantics.dispose();
    });
  });

  group('#504 a Bangla word too wide for its line', () {
    // Real pronunciations from content.db, and where each may break.
    const table = <String, List<String>>{
      // Joints (hasanta + ZWNJ) break; the last akshara stays with one more.
      'Geschwindigkeitsbegrenzung': <String>[
        'গেশ্ভি', 'ন্ডি', 'শ', 'কাইট্‌', 'স', 'বে', 'গ্রেন্‌ৎসুং', //
      ],
      // A closed conjunct (ন্ট্‌) starts no line: never "লা|ন্ট্‌".
      'Bruttoinlandsprodukt': <String>[
        'ব্রুটোই', 'ন', 'লান্ট্‌', 'স', 'প্রো', 'ডুক্ট', //
      ],
      // Nor "রে|শ্ট্‌".
      'Rechtsschutzversicherung': <String>[
        'রেশ্ট্‌', 'স', 'শুৎ', 'স', 'ফে', 'য়া', 'জি', 'শারুং', //
      ],
      // A reph and too few aksharas: whole.
      'Morgen': <String>['মর্গেন'],
      // A ya-phala written with a zero-width joiner: whole.
      'Brücke': <String>['ব্র‍্যুকে'],
      // No lone coda on the last line: "…বা|র|শুস", not "…শু|স".
      'Handelsbilanzüberschuss': <String>[
        'হান্ডে', 'ল্স', 'বি', 'লান্‌ৎ', 'স', 'য়্যু', 'বা', 'র', 'শুস', //
      ],
      // An independent vowel after a joint begins a line: ein|und.
      'einundzwanzig': <String>['আইন্‌', 'উন্ট্‌ৎ', 'স', 'ভান্‌ৎ', 'সিশ'],
      'Fahrkartenautomat': <String>[
        'ফার', 'কা', 'র্টেন্‌', 'আউ', 'টো', 'মাট', //
      ],
      // A cluster khanda-ta closes starts no line: never "শ্মে|র্ৎ".
      'Kopfschmerzen': <String>['কপ্ফ', 'শ্মের্ৎ', 'সেন'],
    };
    const prons = <String, String>{
      'Geschwindigkeitsbegrenzung': 'গেশ্ভিন্ডিশকাইট্‌সবেগ্রেন্‌ৎসুং',
      'Bruttoinlandsprodukt': 'ব্রুটোইনলান্ট্‌সপ্রোডুক্ট',
      'Rechtsschutzversicherung': 'রেশ্ট্‌সশুৎসফেয়াজিশারুং',
      'Morgen': 'মর্গেন',
      'Brücke': 'ব্র‍্যুকে',
      'Handelsbilanzüberschuss': 'হান্ডেল্সবিলান্‌ৎসয়্যুবারশুস',
      'einundzwanzig': 'আইন্‌উন্ট্‌ৎসভান্‌ৎসিশ',
      'Fahrkartenautomat': 'ফারকার্টেন্‌আউটোমাট',
      'Kopfschmerzen': 'কপ্ফশ্মের্ৎসেন',
    };

    test("#504 each breaks between its aksharas, and at the content's own "
        'joints, as the table says', () {
      for (final MapEntry(key: german, value: pron) in prons.entries) {
        final broken = SgScript.banglaBreaks(pron);
        expect(broken.replaceAll(SgScript.softHyphen, ''), pron);
        expect(
          broken.split(SgScript.softHyphen),
          table[german],
          reason: german,
        );
      }
    });

    test('#504 no line starts with a vowel sign, a mark, khanda-ta, or a '
        'consonant a joint closes, and none follows a hasanta', () {
      const shy = 0xAD, hasanta = 0x9CD, joint = 0x200C;
      for (final pron in prons.values) {
        final units = SgScript.banglaBreaks(pron).codeUnits;
        int at(int i) => i < units.length ? units[i] : 0;
        for (var i = 0; i < units.length; i++) {
          if (units[i] != shy) continue;
          expect(units[i - 1], isNot(hasanta), reason: 'a conjunct split');
          final next = units[i + 1];
          expect(
            (next >= 0x995 && next <= 0x9B9) ||
                (next >= 0x9DC && next <= 0x9DF) ||
                (next >= 0x985 && next <= 0x994 && units[i - 1] == joint),
            isTrue,
            reason: 'a line starts with an akshara: $pron',
          );
          var last = i + 1;
          while (at(last + 1) == hasanta &&
              at(last + 2) >= 0x995 &&
              at(last + 2) <= 0x9DF) {
            last += 2;
          }
          expect(
            at(last + 1) == hasanta &&
                (at(last + 2) == joint ||
                    at(last + 2) == 0 ||
                    at(last + 2) == 0x9CE),
            isFalse,
            reason: 'a closed consonant starts a line: $pron',
          );
        }
      }
    });

    test('#504 nothing breaks before the first Bangla letter: an opening "/" '
        'stays with it', () {
      final broken = SgScript.banglaBreaks('/${prons['Morgen']}/');
      expect(broken, isNot(contains(SgScript.softHyphen)));
      final long = SgScript.banglaBreaks(
        '/${prons['Geschwindigkeitsbegrenzung']}/',
      );
      expect(long.indexOf(SgScript.softHyphen), greaterThan(3));
    });
  });

  group('#539 the course German', () {
    testWidgets('SgText(german: true) breaks a long compound too wide for '
        'its line at a syllable, with its "-", though the text offers no '
        'soft hyphen', (tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 150,
          child: SgText(
            'Die Haftpflichtversicherung zahlt.',
            role: SgTextRole.body,
            german: true,
          ),
        ),
      );
      final drawn = tester
          .renderObject<RenderParagraph>(find.byType(RichText))
          .text
          .toPlainText(includeSemanticsLabels: false);
      expect(drawn, contains('-\n'));
      expectNoWordBroken(tester);
    });
  });

  group('#535 SgGermanRuns', () {
    testWidgets('a marked long compound breaks at a syllable with its "-", '
        'and the sentence is read whole, in a German voice', (tester) async {
      final semantics = tester.ensureSemantics();
      const marked = TextStyle(backgroundColor: Color(0xFFFFC61A));
      await pump(
        tester,
        const SizedBox(
          width: 150,
          child: SgGermanRuns(<TextSpan>[
            TextSpan(text: 'Es gilt eine '),
            TextSpan(text: 'Geschwindigkeitsbegrenzung', style: marked),
            TextSpan(text: '.'),
          ]),
        ),
      );
      final spans = <TextSpan>[];
      tester
          .renderObject<RenderParagraph>(find.byType(RichText))
          .text
          .visitChildren((span) {
            if (span is TextSpan && span.text != null) spans.add(span);
            return true;
          });
      final word = spans.singleWhere((s) => s.style == marked);
      expect(word.text, contains('-\n'), reason: 'the "-" in the mark');
      final label = tester.getSemantics(find.byType(RichText)).attributedLabel;
      expect(label.string, 'Es gilt eine Geschwindigkeitsbegrenzung.');
      expect(
        label.attributes.whereType<LocaleStringAttribute>().map(
          (a) => a.locale,
        ),
        everyElement(SgScript.deDE),
      );
      semantics.dispose();
    });
  });

  group('long German compounds', () {
    test('a short word is left alone', () {
      expect(SgScript.allowBreaks('Wohnung'), 'Wohnung');
    });

    test("#1079 the app's Russian and Polish copy breaks between syllables "
        'too, and never starts a line with ь, ъ or й', () {
      String shown(String word) => SgScript.allowBreaks(
        word,
        threshold: 4,
      ).replaceAll(SgScript.softHyphen, '|');
      // The rating bar's labels at 200 %: whole letters were cut before.
      expect(shown('Хорошо'), 'Хо|ро|шо');
      expect(shown('Трудно'), 'Труд|но');
      expect(shown('воскресенье'), 'воск|ре|се|нье');
      expect(shown('Выходной'), 'Вы|ход|ной');
      expect(shown('Łatwe'), 'Łat|we');
    });

    test('#405 a long compound breaks where a syllable begins', () {
      String shown(String word) =>
          SgScript.allowBreaks(word).replaceAll(SgScript.softHyphen, '|');
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
          SgScript.allowBreaks(word).replaceAll(SgScript.softHyphen, ''),
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
        final broken = SgScript.allowBreaks(word);
        for (final match in SgScript.softHyphen.allMatches(broken)) {
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
      expect(SgScript.allowBreaks(authored), authored);
    });

    testWidgets('breaks are off by default, so a headword is never broken up', (
      tester,
    ) async {
      await pump(
        tester,
        const SgText('Wohnungsgeberbestaetigung', role: SgTextRole.body),
      );
      expect(
        tester.widget<Text>(find.byType(Text)).data,
        isNot(contains(SgScript.softHyphen)),
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
            child: SgHeadword('Wohnungsgeberbestaetigung', article: 'die'),
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
            SgTypeTokens.defaults.display.size,
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
          child: SgHeadword('Wohnungsgeberbestaetigung', article: 'die'),
        ),
        textScale: 2,
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byType(RichText),
      );
      expect(
        paragraph.size.height,
        greaterThan(SgTypeTokens.defaults.display.height),
        reason: 'a compound too wide for the card must run onto more lines',
      );
    });

    testWidgets('the article is printed, not only coloured', (tester) async {
      await pump(tester, const SgHeadword('Wohnung', article: 'die'));
      final span = tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;

      expect(span.toPlainText(), 'die Wohnung');
      expect(
        (span.children!.first as TextSpan).style!.color,
        SgPalette.light.dieText,
        reason:
            'gender is carried by colour AND by the printed article — '
            'accessibility-performance.md forbids colour alone',
      );
    });

    testWidgets('a word with no article renders without one', (tester) async {
      await pump(tester, const SgHeadword('schnell'));
      final span = tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;
      expect(span.toPlainText(), 'schnell');
    });
  });

  testWidgets('every role reads its size from the tokens, in every mode', (
    tester,
  ) async {
    for (final (theme, tokens) in <(ThemeData, SgTokens)>[
      (AppTheme.light(), SgTokens.light()),
      (AppTheme.dark(), SgTokens.dark()),
      (AppTheme.glass(), SgTokens.glass()),
    ]) {
      for (final role in SgTextRole.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(body: SgText('Revise', role: role)),
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

  testWidgets('#746 a first word too long for the line is cut inside, not '
      'shown as a bare "…": after a hyphen, else a syllable, else a letter', (
    tester,
  ) async {
    for (final (title, width, shown) in <(String, double, String?)>[
      ('Nomen-Verb-Verbindungen', 200, 'Nomen-Verb-…'),
      ('Kommunikationsmöglichkeiten', 150, null),
      ('Communication & meeting people', 60, null),
      // Bangla only between aksharas: no conjunct or vowel sign is split.
      ('প্রতিষ্ঠানগুলোর মধ্যে', 110, null),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: SgOneLine(title, role: SgTextRole.title),
              ),
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(find.byType(Text));
      final drawn = text.data ?? text.textSpan!.toPlainText();
      expect(drawn, isNot(SgOneLine.ellipsis), reason: title);
      expect(drawn, endsWith(SgOneLine.ellipsis), reason: title);
      expect(
        title.startsWith(drawn.substring(0, drawn.length - 1)),
        isTrue,
        reason: '$title → $drawn',
      );
      if (shown != null) expect(drawn, shown, reason: title);
      expect(
        tester.getSize(find.byType(Text)).width,
        lessThanOrEqualTo(width),
        reason: '$title overflows its $width',
      );
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
                child: SgOneLine(title, role: SgTextRole.title),
              ),
            ),
          ),
        ),
      );
      expect(tester.widget<Text>(find.byType(Text)).data, shown, reason: title);
    }
  });
}
