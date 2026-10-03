import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/adaptive/adaptive.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/theme/sg_focusable.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/core/typography/sg_text.dart';
import 'package:sogda/features/search/search_header.dart';
import 'package:sogda/main.dart'
    show appLocalizationsDelegates, supportedLocales;

/// The band over R2, D1 and D2 (#1412): its text on the Raspberry fill.
void main() {
  double contrast(Color a, Color b) {
    final x = a.computeLuminance() + 0.05;
    final y = b.computeLuminance() + 0.05;
    return x > y ? x / y : y / x;
  }

  Finder sg(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(SgText));

  Future<void> pump(WidgetTester tester, ThemeData theme) => tester.pumpWidget(
    MaterialApp(
      theme: theme,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: supportedLocales,
      home: const Column(
        children: <Widget>[
          SearchHeader(title: 'My word', intro: 'Words you meet'),
        ],
      ),
    ),
  );

  for (final (name, theme, tokens) in <(String, ThemeData, SgTokens)>[
    ('light', AppTheme.light(), SgTokens.light()),
    ('dark', AppTheme.dark(), SgTokens.dark()),
  ]) {
    testWidgets('#1412 WCAG 1.4.3 in $name, the header reads on its '
        'Raspberry: the title at 3:1, the line under it and back at 4.5:1, '
        'and the focus ring the same ink', (tester) async {
      await pump(tester, theme);
      final fill = tokens.color.die;
      final title = tester.widget<SgText>(sg('My word')).color!;
      final line = tester.widget<SgText>(sg('Words you meet')).color!;
      final back = tester
          .widget<AdaptiveBackButton>(find.byType(AdaptiveBackButton))
          .colour!;
      expect(contrast(title, fill), greaterThanOrEqualTo(3));
      expect(contrast(line, fill), greaterThanOrEqualTo(4.5));
      expect(contrast(back, fill), greaterThanOrEqualTo(4.5));
      final ring = SgFocusRingColour.of(
        tester.element(find.byType(AdaptiveBackButton)),
      );
      expect(contrast(ring, fill), greaterThanOrEqualTo(3));
    });
  }

  testWidgets('#1412 under glass, with no fill, the header keeps the page '
      'ink', (tester) async {
    await pump(tester, AppTheme.glass(dark: true));
    expect(
      tester.widget<SgText>(sg('My word')).color,
      SgTokens.glassDark().color.ink,
    );
  });
}
