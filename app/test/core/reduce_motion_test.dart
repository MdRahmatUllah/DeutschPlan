import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' as cupertino;
import 'package:deutschplan/core/adaptive/adaptive.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/glass_capability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// #164: under the OS's reduce motion, pages, panes, sheets and tabs
/// cross-fade or cut rather than move; under reduce transparency the iOS
/// tab bar stops blurring.
void main() {
  void still(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  Future<BuildContext> host(
    WidgetTester tester, {
    AdaptiveChrome chrome = AdaptiveChrome.material,
  }) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AdaptiveChromeScope(
          chrome: chrome,
          child: Scaffold(
            body: Builder(
              builder: (inner) {
                context = inner;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    return context;
  }

  testWidgets('#164 under iOS Reduce Motion a pushed page cross-fades; it '
      'moves when motion is on', (tester) async {
    // Reduce Motion, not disableAnimations: the framework runs a route's
    // animation instantly under the latter anyway, and it is under the
    // former (folded into MediaQuery at the root) that the fade matters.
    Future<bool> atRest() async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => stillOnReduceMotion(context, child!),
          home: Builder(
            builder: (inner) {
              context = inner;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      unawaited(
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const Text('page'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final moving = tester
          .widgetList<SlideTransition>(find.byType(SlideTransition))
          .any((slide) => slide.position.value != Offset.zero);
      await tester.pumpAndSettle();
      return !moving;
    }

    expect(await atRest(), isFalse, reason: 'the platform moves it');
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    expect(await atRest(), isTrue);
  });

  testWidgets("#164 iOS's Reduce Motion is the app's disableAnimations", (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    late bool disabled;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => stillOnReduceMotion(context, child!),
        home: Builder(
          builder: (context) {
            disabled = MediaQuery.disableAnimationsOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(disabled, isTrue);
  });

  testWidgets('#164 under reduce motion the iOS edge swipe still goes back', (
    tester,
  ) async {
    still(tester);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (inner) {
            context = inner;
            return const Scaffold(body: Text('home'));
          },
        ),
      ),
    );
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('page'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('page'), findsOneWidget);
    final gesture = await tester.startGesture(const Offset(5, 300));
    await gesture.moveBy(const Offset(400, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('page'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('#164 the tablet pane fades in rather than sliding', (
    tester,
  ) async {
    still(tester);
    final context = await host(tester);
    unawaited(
      Adaptive.showPane<void>(
        context: context,
        builder: (_) => const Text('pane'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.ancestor(
        of: find.text('pane'),
        matching: find.byType(SlideTransition),
      ),
      findsNothing,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('#164 a sheet is up at once', (tester) async {
    still(tester);
    final context = await host(tester);
    unawaited(
      Adaptive.showSheet<void>(
        context: context,
        builder: (_) => const Text('sheet'),
      ),
    );
    await tester.pump();
    final first = tester.getTopLeft(find.text('sheet'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('sheet')), first);
  });

  testWidgets('#164 a tab bar moves its indicator without sliding it', (
    tester,
  ) async {
    still(tester);
    Future<void> bar(String value) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AdaptiveChromeScope(
          chrome: AdaptiveChrome.material,
          child: Scaffold(
            body: AdaptiveTabBar<String>(
              tabs: const <String, String>{'a': 'A', 'b': 'B'},
              value: value,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await bar('a');
    await bar('b');
    final controller = tester.widget<TabBar>(find.byType(TabBar)).controller!;
    expect(controller.index, 1);
    expect(controller.indexIsChanging, isFalse, reason: 'no slide under way');

    // A tap, which TabBar animates itself before telling anyone.
    await tester.tap(find.text('A'));
    await tester.pump();
    expect(controller.index, 0);
    expect(controller.indexIsChanging, isFalse, reason: 'no slide on a tap');
  });

  testWidgets('#164 under reduce transparency the iOS tab bar is opaque', (
    tester,
  ) async {
    Future<Color> background(GlassCapability capability) async {
      await tester.pumpWidget(
        GlassCapabilityScope(
          notifier: capability,
          child: MaterialApp(
            theme: AppTheme.glass(),
            home: AdaptiveChromeScope(
              chrome: AdaptiveChrome.cupertino,
              child: Scaffold(
                bottomNavigationBar: AdaptiveNavBar(
                  destinations: const <AdaptiveNavDestination>[
                    AdaptiveNavDestination(
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home,
                      label: 'Today',
                    ),
                    AdaptiveNavDestination(
                      icon: Icons.person_outline,
                      selectedIcon: Icons.person,
                      label: 'Me',
                    ),
                  ],
                  currentIndex: 0,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      return tester
          .widget<cupertino.CupertinoTabBar>(
            find.byType(cupertino.CupertinoTabBar),
          )
          .backgroundColor!;
    }

    expect(
      (await background(GlassCapability.always())).a,
      lessThan(1),
      reason: 'glass: see-through',
    );
    expect((await background(GlassCapability(reduceTransparency: true))).a, 1);
  });
}
