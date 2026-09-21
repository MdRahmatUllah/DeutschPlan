import 'package:cupertino_ui/cupertino_ui.dart' as cupertino;
import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
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

  group('AdaptiveSwitch', () {
    testWidgets(
      'renders the Cupertino control on iOS and Material on Android',
      (tester) async {
        await pump(
          tester,
          AdaptiveChrome.cupertino,
          AdaptiveSwitch(value: true, onChanged: (_) {}),
        );
        expect(find.byType(cupertino.CupertinoSwitch), findsOneWidget);
        expect(find.byType(Switch), findsNothing);

        await pump(
          tester,
          AdaptiveChrome.material,
          AdaptiveSwitch(value: true, onChanged: (_) {}),
        );
        expect(find.byType(Switch), findsOneWidget);
        expect(find.byType(cupertino.CupertinoSwitch), findsNothing);
      },
    );

    testWidgets('is Lagoon when on in both chromes', (tester) async {
      await pump(
        tester,
        AdaptiveChrome.material,
        AdaptiveSwitch(value: true, onChanged: (_) {}),
      );
      expect(
        tester.widget<Switch>(find.byType(Switch)).activeTrackColor,
        DpPalette.light.primary,
      );

      await pump(
        tester,
        AdaptiveChrome.cupertino,
        AdaptiveSwitch(value: true, onChanged: (_) {}),
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

    testWidgets('the Android track carries the 2 px ink border', (
      tester,
    ) async {
      // Paper & Ink, not stock Material: the artboard draws
      // `border:2px solid #15121F` around a 52x32 track.
      await pump(
        tester,
        AdaptiveChrome.material,
        AdaptiveSwitch(value: true, onChanged: (_) {}),
      );
      final control = tester.widget<Switch>(find.byType(Switch));
      expect(control.trackOutlineWidth!.resolve(<WidgetState>{}), 2);
      expect(
        control.trackOutlineColor!.resolve(<WidgetState>{}),
        DpPalette.light.ink,
      );
    });

    testWidgets('a null onChanged disables it in both chromes', (tester) async {
      for (final chrome in AdaptiveChrome.values) {
        await pump(
          tester,
          chrome,
          const AdaptiveSwitch(value: false, onChanged: null),
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
  });
}
