import 'package:cupertino_ui/cupertino_ui.dart' as cupertino;
import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/typography/dp_text.dart';

import '../text_clipping.dart';

import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// theming.md: "Chrome follows the platform through `Adaptive*` wrappers...
/// Material 3 on Android, Cupertino on iOS. Content components (word card,
/// rating bar, ring, charts) are identical on both."
///
/// Each wrapper is driven through both chromes from the same call site, because
/// a wrapper that only ever renders one of them is not a wrapper.
void main() {
  Future<void> pump(
    WidgetTester tester,
    AdaptiveChrome chrome,
    Widget child,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AdaptiveChromeScope(
          chrome: chrome,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('chrome resolution', () {
    test('iOS and macOS get Cupertino, everything else gets Material', () {
      expect(
        AdaptiveChrome.forPlatform(TargetPlatform.iOS),
        AdaptiveChrome.cupertino,
      );
      expect(
        AdaptiveChrome.forPlatform(TargetPlatform.macOS),
        AdaptiveChrome.cupertino,
      );
      for (final platform in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.fuchsia,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        expect(AdaptiveChrome.forPlatform(platform), AdaptiveChrome.material);
      }
    });

    testWidgets('falls back to the theme platform with no scope', (
      tester,
    ) async {
      late AdaptiveChrome seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
          home: Builder(
            builder: (context) {
              seen = context.chrome;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, AdaptiveChrome.cupertino);
    });

    testWidgets('a scope overrides the platform, so goldens need no device', (
      tester,
    ) async {
      late AdaptiveChrome seen;
      await pump(
        tester,
        AdaptiveChrome.cupertino,
        Builder(
          builder: (context) {
            seen = context.chrome;
            return const SizedBox();
          },
        ),
      );
      expect(seen, AdaptiveChrome.cupertino);
    });
  });

  group('AdaptiveScaffold', () {
    testWidgets('with a tab bar, each inset is taken once', (tester) async {
      // An edge-to-edge phone: a status bar on top, a gesture bar below. The
      // bar takes the bottom inset; the body must not take it again, and the
      // bar must not see the status bar at all — Material's NavigationBar
      // pads its top by whatever top inset reaches it, and it did, leaving a
      // status bar's height of empty bar above the tabs.
      late EdgeInsets body;
      late EdgeInsets bar;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
              padding: EdgeInsets.only(top: 50, bottom: 24),
            ),
            child: AdaptiveScaffold(
              body: Builder(
                builder: (context) {
                  body = MediaQuery.paddingOf(context);
                  return const SizedBox.expand();
                },
              ),
              bottomBar: Builder(
                builder: (context) {
                  bar = MediaQuery.paddingOf(context);
                  return const SizedBox(height: 80);
                },
              ),
            ),
          ),
        ),
      );

      expect(body.bottom, 0, reason: 'the bar already took it');
      expect(body.top, 50, reason: 'the body runs under the status bar');
      expect(bar, EdgeInsets.zero);
    });

    Future<double> barHeight(WidgetTester tester, AdaptiveChrome chrome) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AdaptiveChromeScope(
            chrome: chrome,
            child: const AdaptiveScaffold(
              title: 'Backlog',
              body: SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.text('Backlog')).height > 0
          ? tester
                .getSize(
                  find
                      .ancestor(
                        of: find.text('Backlog'),
                        matching: find.byType(SizedBox),
                      )
                      .last,
                )
                .height
          : 0;
    }

    testWidgets('the bar is 56 dp on Android and 44 pt on iOS', (tester) async {
      expect(
        await barHeight(tester, AdaptiveChrome.material),
        AdaptiveScaffold.materialBarHeight,
      );
      expect(
        await barHeight(tester, AdaptiveChrome.cupertino),
        AdaptiveScaffold.cupertinoBarHeight,
      );
    });

    testWidgets('iOS centres the title; Android leaves it left-aligned', (
      tester,
    ) async {
      Future<Rect> titleRect(AdaptiveChrome chrome) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: AdaptiveChromeScope(
              chrome: chrome,
              child: const AdaptiveScaffold(
                title: 'Backlog',
                body: SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester.getRect(find.text('Backlog'));
      }

      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;

      final ios = await titleRect(AdaptiveChrome.cupertino);
      expect(
        ios.center.dx,
        closeTo(screenWidth / 2, 1),
        reason: 'an iOS title sits centred regardless of the back button width',
      );
      expect(
        ios.width,
        lessThan(screenWidth),
        reason: 'the iOS title is sized to its text, not stretched',
      );

      final android = await titleRect(AdaptiveChrome.material);
      expect(
        android.left,
        lessThan(ios.left),
        reason: 'a Material title starts at the leading slot, not the centre',
      );
      expect(
        android.left,
        lessThanOrEqualTo(16),
        reason: 'it sits just after the 8 + 4 dp leading gap',
      );
    });

    /// The bar's title as drawn: DpOneLine's one line of spans.
    // The bar's title: its DpOneLine outside the back button, whose iOS
    // label is one too (#588).
    Finder titleLine() => find.byElementPredicate(
      (element) =>
          element.widget is DpOneLine &&
          element.findAncestorWidgetOfExactType<AdaptiveBackButton>() == null,
    );

    RichText barTitle(WidgetTester tester) => tester.widget<RichText>(
      find.descendant(of: titleLine(), matching: find.byType(RichText)),
    );

    Future<void> bar(
      WidgetTester tester,
      AdaptiveChrome chrome,
      String title,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AdaptiveChromeScope(
            chrome: chrome,
            child: AdaptiveScaffold(
              title: title,
              leading: AdaptiveBackButton(
                label: 'Categories',
                onPressed: () {},
              ),
              actions: const <Widget>[SizedBox(width: 60, child: Text('Q'))],
              body: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('#280 a long title is one line ending in "…", clear of the '
        'back button and the actions, in both chromes', (tester) async {
      // L6's bar, on the artboard's phone.
      tester.view
        ..physicalSize = const Size(390, 844) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      const long = 'Psychology, emotions and relationships at work';
      final semantics = tester.ensureSemantics();
      for (final chrome in AdaptiveChrome.values) {
        await bar(tester, chrome, long);
        final text = barTitle(tester);
        final shown = text.text.toPlainText();
        expect(shown, endsWith(DpOneLine.ellipsis), reason: '$chrome');
        final kept = shown.substring(0, shown.length - 1);
        expect(long.startsWith(kept), isTrue, reason: '$chrome');
        expect(
          ' ,;:'.contains(long[kept.length]),
          isTrue,
          reason:
              '$chrome: cut between words, not in "${long.substring(0, kept.length + 1)}"',
        );
        expect(text.maxLines, 1, reason: '$chrome');
        final title = tester.getRect(titleLine());
        expect(
          title.left,
          greaterThanOrEqualTo(
            tester.getRect(find.byType(AdaptiveBackButton)).right,
          ),
          reason: '$chrome',
        );
        expect(
          title.right,
          lessThanOrEqualTo(tester.getRect(find.text('Q')).left),
          reason: '$chrome',
        );
        expect(
          find.bySemanticsLabel(long),
          findsOneWidget,
          reason: '$chrome: read whole',
        );
      }
      semantics.dispose();
    });

    testWidgets('#280 the title is 22/600 on Android and 17/600 on iOS, as the '
        'artboards draw it, and Bangla reads one size larger', (tester) async {
      for (final (chrome, size, bangla) in <(AdaptiveChrome, double, double)>[
        (AdaptiveChrome.material, 22, 28),
        (AdaptiveChrome.cupertino, 17, 20),
      ]) {
        // The spans that carry text, past Text.rich's default-style root.
        List<TextStyle?> runs() {
          final styles = <TextStyle?>[];
          barTitle(tester).text.visitChildren((span) {
            if (span is TextSpan && (span.text?.isNotEmpty ?? false)) {
              styles.add(span.style);
            }
            return true;
          });
          return styles;
        }

        await bar(tester, chrome, 'Settings');
        final style = runs().single!;
        expect(style.fontSize, size, reason: '$chrome');
        expect(
          style.fontVariations,
          contains(const FontVariation('wght', 600)),
          reason: '$chrome',
        );

        await bar(tester, chrome, 'সেটিংস');
        expect(
          <double?>[for (final run in runs()) run?.fontSize],
          <double>[bangla],
          reason: '$chrome',
        );
      }
    });

    testWidgets('#280 #314 at 200 % text the bar grows: its title is not cut, '
        'Latin or Bangla, in either chrome', (tester) async {
      textAt(tester, 2);
      for (final chrome in AdaptiveChrome.values) {
        for (final title in <String>['Settings', 'সেটিংস']) {
          await bar(tester, chrome, title);
          expectNothingClipped(tester, within: titleLine());
        }
      }
    });

    testWidgets('a pushed route gets a back button without asking', (
      tester,
    ) async {
      // navigation.md has around twenty pushed routes. If each had to supply
      // its own, the two platform treatments would be re-implemented twenty
      // times and chrome would be back inside the screens.
      for (final chrome in AdaptiveChrome.values) {
        await tester.pumpWidget(
          MaterialApp(
            // A fresh Navigator each iteration: otherwise the route pushed on
            // the first pass is still on top and 'Open' is no longer findable.
            key: ValueKey(chrome),
            theme: AppTheme.light(),
            home: AdaptiveChromeScope(
              chrome: chrome,
              child: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AdaptiveScaffold(
                          title: 'Backlog',
                          body: SizedBox.shrink(),
                        ),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(
          find.byType(AdaptiveBackButton),
          findsOneWidget,
          reason: 'no back affordance in $chrome',
        );
        expect(
          tester.getSize(find.byType(AdaptiveBackButton)).height,
          greaterThanOrEqualTo(44),
          reason: 'the back button must clear the minimum tap target',
        );
      }
    });

    testWidgets('#315 the back button is one node, named and pressable: '
        '"Back" on Android, the title it shows on iOS', (tester) async {
      final semantics = tester.ensureSemantics();
      for (final (chrome, title, name) in <(AdaptiveChrome, String?, String)>[
        (AdaptiveChrome.material, 'Learn', 'Back'),
        (AdaptiveChrome.cupertino, 'Learn', 'Learn'),
        // No title: every default back button on a pushed route, T4 and W1.
        (AdaptiveChrome.cupertino, null, 'Back'),
      ]) {
        final at = '$chrome, title $title';
        var pressed = 0;
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(at),
            theme: AppTheme.light(),
            home: AdaptiveChromeScope(
              chrome: chrome,
              child: AdaptiveScaffold(
                title: 'A1.1',
                leading: AdaptiveBackButton(
                  label: title,
                  onPressed: () => pressed++,
                ),
                body: const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final node = tester.getSemantics(find.byType(AdaptiveBackButton));
        final data = node.getSemanticsData();
        expect(data.label, name, reason: at);
        expect(data.flagsCollection.isButton, isTrue, reason: at);
        // The TextButton's node is merged into this one: the platform sees
        // one node, not a nameless button beside a name.
        var apart = 0;
        node.visitChildren((child) {
          if (!child.isMergedIntoParent) apart++;
          return true;
        });
        expect(apart, 0, reason: '$at: a second node beside it');
        tester.semantics.tap(find.semantics.byLabel(name));
        expect(pressed, 1, reason: at);
      }
      semantics.dispose();
    });

    testWidgets('#317 scrolled, a tab keeps a strip of its colour behind the '
        'status bar; at rest the header bleeds to the top', (tester) async {
      const lagoon = Color(0xFF00BFB3);
      final list = ScrollController();
      addTearDown(list.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(top: 40)),
            child: AdaptiveScaffold(
              statusBarColour: lagoon,
              body: ListView(
                controller: list,
                children: <Widget>[
                  for (var i = 0; i < 40; i++)
                    SizedBox(height: 60, child: Text('row $i')),
                ],
              ),
            ),
          ),
        ),
      );
      Finder strip() =>
          find.byWidgetPredicate((w) => w is ColoredBox && w.color == lagoon);
      expect(strip(), findsNothing, reason: 'at rest');

      list.jumpTo(200);
      await tester.pump();
      expect(
        tester.getRect(strip()),
        const Rect.fromLTWH(0, 0, 800, 40),
        reason: 'over the status bar, its height',
      );

      list.jumpTo(0);
      await tester.pump();
      expect(strip(), findsNothing, reason: 'back at the top');
    });

    testWidgets('a root route gets no back button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AdaptiveScaffold(title: 'Today', body: SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AdaptiveBackButton), findsNothing);
    });

    testWidgets('the background is paper, never a raw colour', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const AdaptiveScaffold(body: SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, DpSurfaceTokens.dark.paper);
    });
  });

  group('#478 AdaptiveTapTarget', () {
    // A 32 dp control, as a chip is: its label and tap on a plain Semantics.
    var taps = 0;
    Widget chip() => AdaptiveTapTarget(
      child: Semantics(
        button: true,
        label: 'A1.1',
        onTap: () => taps++,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const SizedBox.square(dimension: 32),
        ),
      ),
    );

    for (final (chrome, side) in <(AdaptiveChrome, double)>[
      (AdaptiveChrome.material, 48),
      (AdaptiveChrome.cupertino, 44),
    ]) {
      testWidgets('#478 ${chrome.name}: the node is $side, the layout still '
          '32, and the label and tap are on it', (tester) async {
        final semantics = tester.ensureSemantics();
        await pump(tester, chrome, chip());
        expect(
          tester.getSize(find.byType(AdaptiveTapTarget)),
          const Size(32, 32),
        );
        final node = tester.getSemantics(find.byType(AdaptiveTapTarget));
        expect(node.rect.size, Size(side, side));
        expect(node.label, 'A1.1');
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        semantics.dispose();
      });
    }

    testWidgets('#478 a tap just outside the drawn control lands on it; one '
        'past the target does not', (tester) async {
      taps = 0;
      await pump(tester, AdaptiveChrome.material, chip());
      final box = tester.getRect(find.byType(AdaptiveTapTarget));
      await tester.tapAt(box.topLeft - const Offset(6, 6));
      expect(taps, 1);
      await tester.tapAt(box.topLeft - const Offset(12, 12));
      expect(taps, 1);
    });
  });

  group('#162 AdaptiveTooltip', () {
    // An icon-only control: a name to show, and the same words as its label.
    // Not excluding its children's semantics, as WordPlayButton doesn't, so
    // a tooltip that were read would show here.
    Widget gear({bool longPress = true, String? message = 'Settings'}) =>
        Semantics(
          button: true,
          label: 'Settings',
          child: AdaptiveTooltip(
            message: message,
            longPress: longPress,
            child: GestureDetector(
              onTap: () {},
              child: const SizedBox.square(
                dimension: 48,
                child: Icon(Icons.settings_outlined),
              ),
            ),
          ),
        );

    testWidgets('#162 Y01 Material: a long press shows the name, which a '
        'screen reader does not hear twice', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, AdaptiveChrome.material, gear());
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'Settings');

      await tester.longPress(find.byType(GestureDetector));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);

      final node = tester.getSemantics(find.byType(AdaptiveTooltip));
      expect(node.label, 'Settings');
      expect(node.tooltip, isEmpty);
      semantics.dispose();
    });

    testWidgets('#162 Y01 iOS has no tooltips', (tester) async {
      await pump(tester, AdaptiveChrome.cupertino, gear());
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets("#162 Y01 where a long press has its own job, it doesn't show "
        'the name', (tester) async {
      await pump(tester, AdaptiveChrome.material, gear(longPress: false));
      await tester.longPress(find.byType(GestureDetector));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('#162 Y01 no name, no tooltip', (tester) async {
      await pump(tester, AdaptiveChrome.material, gear(message: null));
      expect(find.byType(Tooltip), findsNothing);
    });
  });

  group('AdaptiveSwitch', () {
    testWidgets(
      'renders the Cupertino control on iOS and Material on Android',
      (tester) async {
        await pump(
          tester,
          AdaptiveChrome.cupertino,
          AdaptiveSwitch(
            value: true,
            onChanged: (_) {},
            semanticLabel: 'Daily reminder',
          ),
        );
        expect(find.byType(cupertino.CupertinoSwitch), findsOneWidget);
        expect(find.byType(Switch), findsNothing);

        await pump(
          tester,
          AdaptiveChrome.material,
          AdaptiveSwitch(
            value: true,
            onChanged: (_) {},
            semanticLabel: 'Daily reminder',
          ),
        );
        expect(find.byType(Switch), findsOneWidget);
        expect(find.byType(cupertino.CupertinoSwitch), findsNothing);
      },
    );

    testWidgets('is Lagoon when on in both chromes', (tester) async {
      await pump(
        tester,
        AdaptiveChrome.material,
        AdaptiveSwitch(
          value: true,
          onChanged: (_) {},
          semanticLabel: 'Daily reminder',
        ),
      );
      expect(
        tester.widget<Switch>(find.byType(Switch)).activeTrackColor,
        DpPalette.light.primary,
      );

      await pump(
        tester,
        AdaptiveChrome.cupertino,
        AdaptiveSwitch(
          value: true,
          onChanged: (_) {},
          semanticLabel: 'Daily reminder',
        ),
      );
      expect(
        tester
            .widget<cupertino.CupertinoSwitch>(
              find.byType(cupertino.CupertinoSwitch),
            )
            .activeTrackColor,
        DpPalette.light.primary,
      );
    });

    testWidgets('the Android track carries a 2 px border: ink with a ticked '
        'ink thumb when on, Slate when off', (tester) async {
      // Paper & Ink, not stock Material: the artboards draw
      // `border:2px solid #15121F` around a 52x32 Lagoon track and an ink
      // thumb with a Lagoon tick; off, a Slate border and thumb on Oat.
      await pump(
        tester,
        AdaptiveChrome.material,
        AdaptiveSwitch(
          value: true,
          onChanged: (_) {},
          semanticLabel: 'Daily reminder',
        ),
      );
      final control = tester.widget<Switch>(find.byType(Switch));
      const on = <WidgetState>{WidgetState.selected};
      expect(control.trackOutlineWidth!.resolve(on), 2);
      expect(control.trackOutlineColor!.resolve(on), DpPalette.light.ink);
      expect(
        control.trackOutlineColor!.resolve(<WidgetState>{}),
        DpPalette.light.textSecondary,
      );
      expect(control.activeThumbColor, DpPalette.light.ink);
      expect(control.inactiveThumbColor, DpPalette.light.textSecondary);
      expect(control.thumbIcon!.resolve(on)!.icon, Icons.check);
      expect(control.thumbIcon!.resolve(<WidgetState>{}), isNull);
    });

    testWidgets('the tap target clears 48 dp even though the track is smaller', (
      tester,
    ) async {
      // The artboard track is 52x32 / 51x31; the widget is padded out to a tap
      // target, which is what accessibility-performance.md actually requires.
      for (final chrome in AdaptiveChrome.values) {
        await pump(
          tester,
          chrome,
          AdaptiveSwitch(
            value: true,
            onChanged: (_) {},
            semanticLabel: 'Daily reminder',
          ),
        );
        final size = tester.getSize(find.byType(AdaptiveSwitch));
        expect(
          size.height,
          greaterThanOrEqualTo(
            chrome == AdaptiveChrome.cupertino
                ? 39
                : AdaptiveSwitch.minimumTapTarget,
          ),
          reason: 'tap target too small in $chrome',
        );
        expect(
          size.height,
          greaterThan(
            chrome == AdaptiveChrome.cupertino
                ? AdaptiveSwitch.cupertinoTrack.height
                : AdaptiveSwitch.materialTrack.height,
          ),
          reason: 'the widget must be larger than the track it draws',
        );
      }
    });

    testWidgets('the semantic label reaches the tree', (tester) async {
      await pump(
        tester,
        AdaptiveChrome.material,
        AdaptiveSwitch(
          value: true,
          onChanged: (_) {},
          semanticLabel: 'Daily reminder',
        ),
      );
      expect(find.bySemanticsLabel('Daily reminder'), findsOneWidget);
    });

    testWidgets('a null onChanged disables it in both chromes', (tester) async {
      for (final chrome in AdaptiveChrome.values) {
        await pump(
          tester,
          chrome,
          const AdaptiveSwitch(
            value: false,
            onChanged: null,
            semanticLabel: 'Daily reminder',
          ),
        );
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('AdaptiveSegmented', () {
    testWidgets('renders the platform control and reports the chosen value', (
      tester,
    ) async {
      for (final chrome in AdaptiveChrome.values) {
        var chosen = 'week';
        await pump(
          tester,
          chrome,
          AdaptiveSegmented<String>(
            segments: const <String, String>{
              'week': 'Week',
              'month': 'Month',
              'all': 'All',
            },
            value: 'week',
            onChanged: (value) => chosen = value,
          ),
        );

        if (chrome == AdaptiveChrome.cupertino) {
          expect(
            find.byType(cupertino.CupertinoSlidingSegmentedControl<String>),
            findsOneWidget,
          );
        } else {
          expect(find.byType(SegmentedButton<String>), findsOneWidget);
        }

        await tester.tap(find.text('Month'));
        await tester.pumpAndSettle();
        expect(chosen, 'month', reason: 'tapping a segment in $chrome');
      }
    });
  });

  group('modals', () {
    testWidgets('the sheet opens in both chromes and returns its result', (
      tester,
    ) async {
      for (final chrome in AdaptiveChrome.values) {
        String? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: AdaptiveChromeScope(
              chrome: chrome,
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      result = await Adaptive.showSheet<String>(
                        context: context,
                        builder: (sheetContext) => TextButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop('picked'),
                          child: const Text('Choose'),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Choose'), findsOneWidget, reason: '$chrome sheet');

        await tester.tap(find.text('Choose'));
        await tester.pumpAndSettle();
        expect(result, 'picked');
      }
    });

    testWidgets('an iOS sheet keeps its chrome and gives its content a '
        'Material, wherever the chrome scope sits', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          // The scope inside the app's home, as in the golden harness: the
          // sheet's route is above it, so the sheet must carry the chrome.
          home: AdaptiveChromeScope(
            chrome: AdaptiveChrome.cupertino,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Adaptive.showSheet<void>(
                    context: context,
                    builder: (_) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text('Timer'),
                        AdaptiveSwitch(
                          value: false,
                          onChanged: (_) {},
                          semanticLabel: 'Timer',
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(cupertino.CupertinoSwitch), findsOneWidget);
      expect(
        find.ancestor(of: find.text('Timer'), matching: find.byType(Material)),
        findsWidgets,
        reason: 'text in a Cupertino popup needs a Material for its style',
      );
    });

    for (final chrome in AdaptiveChrome.values) {
      testWidgets('a ${chrome.name} sheet rises above the keyboard, and '
          'covers the tab bar', (tester) async {
        tester.view
          ..physicalSize = const Size(390, 844) * 3
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: AdaptiveChromeScope(
              chrome: chrome,
              // A tab's navigator under a bar, as the shell has it.
              child: Scaffold(
                bottomNavigationBar: const SizedBox(
                  height: 80,
                  child: Text('tabs'),
                ),
                body: Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (context) => TextButton(
                      onPressed: () => Adaptive.showSheet<void>(
                        context: context,
                        builder: (_) => const SizedBox(
                          height: 200,
                          child: TextField(key: Key('name')),
                        ),
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final sheet = find.ancestor(
          of: find.byKey(const Key('name')),
          matching: find.byType(DpSurface),
        );
        expect(tester.getRect(sheet).bottom, 844, reason: 'over the tab bar');

        tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet).bottom, 844 - 300);
      });
    }

    testWidgets('#390 the keyboard covers the tab bar, and a tab under the '
        'shell rises above the keyboard once, not twice', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844) * 3
        ..devicePixelRatio = 3
        ..viewInsets = const FakeViewPadding(bottom: 300 * 3);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AdaptiveScaffold(
            bottomBar: const SizedBox(height: 80, child: Text('tabs')),
            // A tab root, with its own scaffold, as R1 has.
            body: AdaptiveScaffold(body: Container(key: const Key('tab'))),
          ),
        ),
      );
      // 844, less the keyboard's 300, once: the bar is under the keyboard,
      // and the room it had is the form's (#390).
      expect(tester.getSize(find.byKey(const Key('tab'))).height, 844 - 300);
      expect(find.text('tabs'), findsNothing);

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump();
      expect(find.text('tabs'), findsOneWidget, reason: 'back with the keys');
      expect(tester.getSize(find.byKey(const Key('tab'))).height, 844 - 80);
    });

    testWidgets('the confirm dialog uses the platform dialog and returns', (
      tester,
    ) async {
      for (final chrome in AdaptiveChrome.values) {
        bool? answer;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: AdaptiveChromeScope(
              chrome: chrome,
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      answer = await Adaptive.showConfirm(
                        context: context,
                        title: 'Leave the exam?',
                        message: 'Your answers so far are saved.',
                        confirmLabel: 'Leave',
                        cancelLabel: 'Keep going',
                        destructive: true,
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        if (chrome == AdaptiveChrome.cupertino) {
          expect(find.byType(cupertino.CupertinoAlertDialog), findsOneWidget);
        } else {
          expect(find.byType(AlertDialog), findsOneWidget);
        }

        await tester.tap(find.text('Leave'));
        await tester.pumpAndSettle();
        expect(answer, isTrue);
      }
    });

    testWidgets('#432 the typed confirm scrolls above the keyboard at 200 %: '
        'the field in view, the actions clear of it', (tester) async {
      // agent-3's phone: 411 × 731 dp, the keyboard up as the field opens.
      tester.view
        ..physicalSize = const Size(411, 731) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      const keyboard = 300.0;
      const above = 731 - keyboard;
      for (final chrome in AdaptiveChrome.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            // Over the navigator, so the dialog's route has it too.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: keyboard),
              ),
              child: child!,
            ),
            home: AdaptiveChromeScope(
              chrome: chrome,
              child: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Adaptive.showTypedConfirm(
                      context: context,
                      title: 'Reset everything?',
                      message:
                          'Your progress, your words, your exams and your '
                          'settings are deleted. The downloaded models stay. '
                          'Type RESET to confirm.',
                      word: 'RESET',
                      confirmLabel: 'Reset',
                      cancelLabel: 'Cancel',
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final field = tester.getRect(find.byType(EditableText));
        expect(field.top, greaterThanOrEqualTo(0), reason: '$chrome');
        expect(
          field.bottom,
          lessThanOrEqualTo(above),
          reason: '$chrome: the field is under the keyboard',
        );
        for (final action in <String>['Cancel', 'Reset']) {
          final rect = tester.getRect(find.text(action));
          expect(
            rect.overlaps(field),
            isFalse,
            reason: '$chrome: $action is over the field',
          );
          expect(rect.bottom, lessThanOrEqualTo(above), reason: '$chrome');
        }
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });

    // accessibility-performance.md: text 4.5:1 in all three modes. The
    // colours are read off what is drawn, not off the theme, so a style that
    // overrides the theme is caught too.
    group('#318 dialog and picker buttons read at 4.5:1', () {
      double contrast(Color a, Color b) {
        final x = a.computeLuminance() + 0.05;
        final y = b.computeLuminance() + 0.05;
        return x > y ? x / y : y / x;
      }

      // What the dialog is drawn on: its own Material, not a token. Opaque,
      // or the ratio would depend on whatever shows through it.
      Color behind(WidgetTester tester, Finder dialog) {
        final colour = tester
            .widget<Material>(
              find
                  .descendant(of: dialog, matching: find.byType(Material))
                  .first,
            )
            .color!;
        expect(colour.a, 1, reason: 'the dialog is see-through');
        return colour;
      }

      Color drawn(WidgetTester tester, String label) => tester
          .renderObject<RenderParagraph>(find.text(label))
          .text
          .style!
          .color!;

      final themes = <(String, ThemeData)>[
        ('light', AppTheme.light()),
        ('dark', AppTheme.dark()),
        ('glass', AppTheme.glass()),
        ('glass dark', AppTheme.glass(dark: true)),
      ];

      testWidgets("the confirm dialog's cancel, confirm and destructive "
          'confirm', (tester) async {
        for (final (name, theme) in themes) {
          for (final destructive in <bool>[false, true]) {
            await tester.pumpWidget(
              MaterialApp(
                key: ValueKey((name, destructive)),
                theme: theme,
                home: AdaptiveChromeScope(
                  chrome: AdaptiveChrome.material,
                  child: Scaffold(
                    body: Builder(
                      builder: (context) => GestureDetector(
                        onTap: () => Adaptive.showConfirm(
                          context: context,
                          title: 'Start B1.1?',
                          message: 'A1.1 stays where it is.',
                          confirmLabel: 'Start',
                          cancelLabel: 'Not now',
                          destructive: destructive,
                        ),
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Open'));
            await tester.pumpAndSettle();
            final card = behind(tester, find.byType(AlertDialog));
            for (final label in <String>['Not now', 'Start']) {
              expect(
                contrast(drawn(tester, label), card),
                greaterThanOrEqualTo(4.5),
                reason: '$name, destructive $destructive: "$label"',
              );
            }
          }
        }
      });

      testWidgets("the time picker's Cancel and OK", (tester) async {
        for (final (name, theme) in themes) {
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey(name),
              theme: theme,
              home: AdaptiveChromeScope(
                chrome: AdaptiveChrome.material,
                child: Scaffold(
                  body: Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Adaptive.showTimePickerFor(
                        context: context,
                        initial: const TimeOfDay(hour: 19, minute: 0),
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final card = behind(tester, find.byType(TimePickerDialog));
          for (final label in <String>['Cancel', 'OK']) {
            expect(
              contrast(drawn(tester, label), card),
              greaterThanOrEqualTo(4.5),
              reason: '$name: "$label"',
            );
          }
        }
      });
    });
  });
}
