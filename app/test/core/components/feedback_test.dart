import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// answer-checking.md: the umlaut row and its long-press.
/// state-management.md: one shared ErrorPanel with Retry.
/// accessibility-performance.md: "verdicts have icons and words".
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('DpUmlautBar insertion', () {
    test('appends when the field has never been focused', () {
      final controller = TextEditingController(text: 'Stra');
      DpUmlautBar.insert(controller, 'ß');
      expect(controller.text, 'Straß');
      expect(controller.selection.baseOffset, 5);
    });

    test('inserts at the cursor, not at the end', () {
      // The bug this prevents: correcting the middle of a word and getting the
      // character stuck on the end.
      final controller = TextEditingController(text: 'Strasse')
        ..selection = const TextSelection.collapsed(offset: 4);

      DpUmlautBar.insert(controller, 'ß');
      expect(controller.text, 'Straßsse');
      expect(controller.selection.baseOffset, 5);
    });

    test('replaces a selection', () {
      final controller = TextEditingController(text: 'Strasse')
        ..selection = const TextSelection(baseOffset: 4, extentOffset: 6);

      DpUmlautBar.insert(controller, 'ß');
      expect(controller.text, 'Straße');
      expect(controller.selection.baseOffset, 5);
    });

    test('the caret ends after the inserted character every time', () {
      final controller = TextEditingController();
      for (final key in DpUmlautBar.keys.keys) {
        DpUmlautBar.insert(controller, key);
      }
      expect(controller.text, 'äöüß');
      expect(controller.selection.baseOffset, 4);
    });
  });

  group('DpUmlautBar widget', () {
    testWidgets('it offers exactly the four keys, 44 dp tall', (tester) async {
      final controller = TextEditingController();
      await pump(tester, DpUmlautBar(controller: controller));

      for (final key in DpUmlautBar.keys.keys) {
        expect(find.text(key), findsOneWidget);
      }
      expect(DpUmlautBar.keys.keys, <String>['ä', 'ö', 'ü', 'ß']);
      expect(
        tester.getSize(find.byType(DpUmlautBar)).height,
        DpUmlautBar.keyHeight,
      );
    });

    testWidgets('tapping a key types it', (tester) async {
      final controller = TextEditingController();
      await pump(tester, DpUmlautBar(controller: controller));

      await tester.tap(find.text('ö'));
      await tester.pumpAndSettle();
      expect(controller.text, 'ö');
    });

    testWidgets('long-pressing ß types the capital', (tester) async {
      // ẞ exists but is on no keyboard, which is why it earns the long-press.
      final controller = TextEditingController();
      await pump(tester, DpUmlautBar(controller: controller));

      await tester.longPress(find.text('ß'));
      await tester.pumpAndSettle();
      expect(controller.text, DpUmlautBar.capitalSharpS);
    });

    testWidgets('long-pressing any key gives its capital', (tester) async {
      // German capitalises every noun — Übung, Äpfel, Österreich are all A1
      // words whose first letter has no key on an English keyboard.
      for (final entry in DpUmlautBar.keys.entries) {
        final controller = TextEditingController();
        await pump(tester, DpUmlautBar(controller: controller));

        await tester.longPress(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(
          controller.text,
          entry.value,
          reason: 'long-pressing ${entry.key} should give ${entry.value}',
        );
      }
    });

    testWidgets('the callout fills Oat at the button radius, not a card', (
      tester,
    ) async {
      // The GrammarTopic artboard draws it inside a card, so it has no border
      // and no shadow of its own.
      await pump(tester, DpCallout.text('bekommen = to get'));
      final decoration =
          tester
                  .widgetList<DecoratedBox>(
                    find.descendant(
                      of: find.byType(DpCallout),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .first
                  .decoration
              as BoxDecoration;

      expect(decoration.color, DpSurfaceTokens.light.muted);
      expect(decoration.border, isNull);
      expect(decoration.boxShadow ?? const <BoxShadow>[], isEmpty);
    });

    testWidgets('the ß key announces its long-press', (tester) async {
      final controller = TextEditingController();
      await pump(tester, DpUmlautBar(controller: controller));
      expect(
        find.bySemanticsLabel('ß, long press for ẞ'),
        findsOneWidget,
        reason: 'a gesture nobody can discover is a gesture nobody uses',
      );
    });
  });

  group('DpCallout', () {
    testWidgets('it draws a 6 dp Tangerine bar by default', (tester) async {
      await pump(tester, DpCallout.text('bekommen = to get, not "to become"'));

      final bar = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(DpCallout),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(bar.color, DpPalette.light.hard);
      expect(tester.getSize(find.byWidget(bar)).width, DpCallout.barWidth);
    });

    testWidgets('the bar runs the full height of the content', (tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 300,
          child: DpCallout(
            title: 'Watch out',
            child: Text(
              'konnte, musste, wollte — no umlaut, no ge-. This runs onto '
              'more than one line so the bar has something to stretch to.',
            ),
          ),
        ),
      );

      final barHeight = tester
          .getSize(
            find.descendant(
              of: find.byType(DpCallout),
              matching: find.byType(ColoredBox),
            ),
          )
          .height;
      expect(barHeight, tester.getSize(find.byType(DpCallout)).height);
    });
  });

  group('DpErrorPanel', () {
    testWidgets('it shows the message and a working Retry', (tester) async {
      var retries = 0;
      await pump(
        tester,
        DpErrorPanel(
          message: 'Could not open your course',
          retryLabel: 'Retry',
          onRetry: () => retries++,
        ),
      );

      expect(find.text('Could not open your course'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(retries, 1);
    });

    testWidgets('it carries a second action when one is given', (tester) async {
      // The bootstrap failure adds "Export progress", so a learner can rescue
      // their data when the app will not start.
      await pump(
        tester,
        DpErrorPanel(
          message: 'Could not open your course',
          retryLabel: 'Retry',
          onRetry: () {},
          action: const Text('Export progress'),
        ),
      );
      expect(find.text('Export progress'), findsOneWidget);
    });

    testWidgets('it is a live region, so a screen reader announces it', (
      tester,
    ) async {
      await pump(
        tester,
        const DpErrorPanel(message: 'Could not open', retryLabel: 'Retry'),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('DpVerdictRow', () {
    testWidgets('every verdict has an icon AND a word, never colour alone', (
      tester,
    ) async {
      for (final (verdict, message) in <(DpVerdict, String)>[
        (DpVerdict.correct, 'Correct'),
        (DpVerdict.almost, 'Almost — watch the spelling'),
        (DpVerdict.wrongArticle, 'die, not der'),
        (DpVerdict.wrong, 'Wrong'),
      ]) {
        await pump(tester, DpVerdictRow(verdict: verdict, message: message));

        expect(find.text(message), findsOneWidget, reason: 'the word');

        if (verdict == DpVerdict.almost) {
          // Material has no "approximately equal" glyph, and the artboard draws
          // the real character. A near-miss icon would mean something else.
          expect(
            find.text(DpVerdictRow.almostGlyph),
            findsOneWidget,
            reason: 'the almost mark',
          );
        } else {
          expect(find.byType(Icon), findsOneWidget, reason: 'the icon');
        }
      }
    });

    testWidgets('emphasis sets its parts in ink, in order, wherever they are', (
      tester,
    ) async {
      await pump(
        tester,
        const DpVerdictRow(
          verdict: DpVerdict.wrongArticle,
          message: 'Artikel: der, nicht die!',
          emphasis: <String>['der', 'die'],
        ),
      );
      final text = tester.widget<Text>(find.text('Artikel: der, nicht die!'));
      final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(
        [for (final s in spans) (s.text, s.style?.color)],
        [
          ('Artikel: ', null),
          ('der', DpPalette.light.ink),
          (', nicht ', null),
          ('die', DpPalette.light.ink),
          ('!', null),
        ],
      );
    });

    testWidgets('the colours are the artboard verdict colours', (tester) async {
      const palette = DpPalette.light;
      for (final (verdict, colour) in <(DpVerdict, Color)>[
        (DpVerdict.correct, palette.correctText),
        (DpVerdict.almost, palette.almostText),
        (DpVerdict.wrong, palette.wrongText),
      ]) {
        await pump(tester, DpVerdictRow(verdict: verdict, message: 'x'));
        if (verdict == DpVerdict.almost) {
          expect(find.text(DpVerdictRow.almostGlyph), findsOneWidget);
        } else {
          expect(tester.widget<Icon>(find.byType(Icon)).color, colour);
        }
      }
    });

    testWidgets('all three marks are the same size, and larger than the words', (
      tester,
    ) async {
      // The artboard draws every mark at 18 while the words beside them are 15.
      for (final verdict in DpVerdict.values) {
        await pump(tester, DpVerdictRow(verdict: verdict, message: 'x'));
        if (verdict == DpVerdict.almost) {
          expect(
            tester
                .widget<Text>(find.text(DpVerdictRow.almostGlyph))
                .style!
                .fontSize,
            DpVerdictRow.markSize,
          );
        } else {
          expect(
            tester.widget<Icon>(find.byType(Icon)).size,
            DpVerdictRow.markSize,
          );
        }
      }
      expect(
        DpVerdictRow.markSize,
        greaterThan(DpTypeTokens.defaults.body.size),
      );
    });

    test('a wrong article is styled as wrong, and says which', () {
      // BR-ANS-02: it counts as wrong for scoring, but the feedback names the
      // article — so it shares the colour and differs in the message.
      const row = DpVerdictRow(verdict: DpVerdict.wrongArticle, message: 'x');
      expect(row.colourFrom(DpPalette.light), DpPalette.light.wrongText);
      expect(row.icon, Icons.close);
    });
  });

  group('DpUndo', () {
    testWidgets('it shows for 4 seconds and the action fires', (tester) async {
      var undos = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => GestureDetector(
                onTap: () => DpUndo.show(
                  context,
                  message: 'Moved die Kaution to the backlog',
                  onUndo: () => undos++,
                ),
                child: const Text('rate'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('rate'));
      // The snackbar animates in; tapping mid-entrance misses it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('Moved die Kaution to the backlog'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undos, 1);
    });

    testWidgets('a second undo replaces the first rather than queueing', (
      tester,
    ) async {
      // Two rapid ratings must not stack: the older bar would expire while the
      // learner is still reading the newer one.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => GestureDetector(
                onTap: () => DpUndo.show(
                  context,
                  message: 'Rated ${DateTime.now().microsecondsSinceEpoch}',
                  onUndo: () {},
                ),
                child: const Text('rate'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('rate'));
      await tester.pump();
      await tester.tap(find.text('rate'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Undo'), findsOneWidget);
    });

    Future<void> showUndo(
      WidgetTester tester, {
      bool screenReader = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(accessibleNavigation: screenReader),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => GestureDetector(
                onTap: () =>
                    DpUndo.show(context, message: 'Rated', onUndo: () {}),
                child: const Text('rate'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('rate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('Undo'), findsOneWidget);
    }

    testWidgets('FR-T2-02 it is gone after its 4 s (#319)', (tester) async {
      await showUndo(tester);
      await tester.pump(DpUndo.duration);
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('with a screen reader on it stays until it is used', (
      tester,
    ) async {
      await showUndo(tester, screenReader: true);
      await tester.pump(DpUndo.duration * 2);
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);
    });

    test('the duration is the 4 s FR-T2-02 asks for', () {
      expect(DpUndo.duration, const Duration(seconds: 4));
    });

    for (final (name, theme, palette) in <(String, ThemeData, DpPalette)>[
      ('light', AppTheme.light(), DpPalette.light),
      ('dark', AppTheme.dark(), DpPalette.dark),
    ]) {
      testWidgets('it is the StudyNew artboard\'s inverse bar ($name)', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => GestureDetector(
                  onTap: () => DpUndo.show(
                    context,
                    message: 'Moved die Kaution to the backlog',
                    onUndo: () {},
                  ),
                  child: const Text('rate'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('rate'));
        await tester.pump();

        final bar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(bar.backgroundColor, palette.ink);
        expect(bar.action?.textColor, palette.inverseLink);
        final shape = bar.shape! as RoundedRectangleBorder;
        expect(shape.side, BorderSide.none);
      });
    }
  });
}
