import 'package:deutschplan/core/components/dp_feedback.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart' show supportedLocales;
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
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
      for (final key in DpUmlautBar.keys) {
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

      for (final key in <String>['ä', 'ö', 'ü', 'ß']) {
        expect(find.text(key), findsOneWidget);
      }
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

    testWidgets('only ß has a long-press', (tester) async {
      final controller = TextEditingController();
      await pump(tester, DpUmlautBar(controller: controller));

      await tester.longPress(find.text('ä'));
      await tester.pumpAndSettle();
      expect(
        controller.text,
        'ä',
        reason: 'a long-press on a key with no capital form is just a tap',
      );
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
        expect(find.byType(Icon), findsOneWidget, reason: 'the icon');
      }
    });

    testWidgets('the colours are the artboard verdict colours', (tester) async {
      const palette = DpPalette.light;
      for (final (verdict, colour) in <(DpVerdict, Color)>[
        (DpVerdict.correct, palette.correctText),
        (DpVerdict.almost, palette.almostText),
        (DpVerdict.wrong, palette.wrongText),
      ]) {
        await pump(tester, DpVerdictRow(verdict: verdict, message: 'x'));
        expect(tester.widget<Icon>(find.byType(Icon)).color, colour);
      }
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
          home: Scaffold(
            body: Builder(
              builder: (context) => GestureDetector(
                onTap: () => DpUndo.show(
                  context,
                  message: 'Moved die Kaution to the backlog',
                  undoLabel: 'Undo',
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
          home: Scaffold(
            body: Builder(
              builder: (context) => GestureDetector(
                onTap: () => DpUndo.show(
                  context,
                  message: 'Rated ${DateTime.now().microsecondsSinceEpoch}',
                  undoLabel: 'Undo',
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

    test('the duration is the 4 s FR-T2-02 asks for', () {
      expect(DpUndo.duration, const Duration(seconds: 4));
    });
  });
}
