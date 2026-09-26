import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';
import 'package:deutschplan/features/quiz/quiz_item_view.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../core/text_clipping.dart';

/// L8's, L12's and L14's German word (#405): `accessibility-performance.md`'s
/// "long compounds soft-hyphenate", as DpHeadword does on W1 and T2.
void main() {
  Future<void> pump(WidgetTester tester, String word) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: GermanWord(word, role: DpTextRole.display),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> breaksOnlyAtSyllables(WidgetTester tester, String word) async {
    await pump(tester, word);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    // As drawn: the span's label is the word whole (#419).
    final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
    expect(text, contains(DpScript.softHyphen));

    // The same span at the same width, where the line boundaries can be read.
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout(maxWidth: paragraph.size.width);
    addTearDown(painter.dispose);
    final lines = <int>[];
    var at = 0;
    while (at < text.length) {
      final line = painter.getLineBoundary(TextPosition(offset: at));
      if (line.end <= at) break;
      // A line the headword ended itself stops before its newline (#419).
      final end = line.end < text.length && text[line.end] == '\n'
          ? line.end + 1
          : line.end;
      lines.add(end);
      at = end;
    }
    expect(lines.length, greaterThan(1), reason: 'too long for one line');
    for (final end in lines.take(lines.length - 1)) {
      final before = text[end - 1];
      // A space, a soft hyphen, or the line the headword drew itself: at a
      // space, or after its "-" (#419).
      expect(
        before == ' ' || before == DpScript.softHyphen || before == '\n',
        isTrue,
        reason: 'a line ends in "${text.substring(0, end)}"',
      );
    }
  }

  testWidgets('#405 a long compound at display size breaks only at a space or '
      'a soft hyphen, never mid-syllable', (tester) async {
    await breaksOnlyAtSyllables(tester, 'die Reiseversicherung');
  });

  testWidgets('#405 and at 200 % text, the longest too', (tester) async {
    textAt(tester, 2);
    await breaksOnlyAtSyllables(tester, 'die Geschwindigkeitsbegrenzung');
  });

  testWidgets('#405 the article keeps its gender colour, and the word is read '
      'out without the soft hyphen', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, 'die Reiseversicherung');
    final tokens = tester.element(find.byType(GermanWord)).tokens;
    final spans = <TextSpan>[];
    tester.widget<RichText>(find.byType(RichText)).text.visitChildren((span) {
      if (span is TextSpan && span.text != null) spans.add(span);
      return true;
    });
    expect(spans.first.text, 'die ');
    expect(spans.first.style?.color, tokens.color.dieText);
    expect(find.bySemanticsLabel('die Reiseversicherung'), findsOneWidget);
    semantics.dispose();
  });
}
