import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sogda/core/providers/app_providers.dart';
import 'package:sogda/core/theme/app_theme.dart';
import 'package:sogda/core/theme/glass_capability.dart';
import 'package:sogda/core/theme/sg_surface.dart';
import 'package:sogda/core/theme/sg_tokens.dart';
import 'package:sogda/data/db/app_database.dart';
import 'package:sogda/data/repositories/setting_keys.dart';
import 'package:sogda/data/repositories/settings_repository.dart';
import 'package:sogda/main.dart' show watchGlassTheme;

/// theming.md: "`GlassPanel` degrades to a 92 %-opaque tinted surface when:
/// Android API < 31, the device missed the frame budget for 2 s, or the OS
/// 'reduce transparency' setting is on."
///
/// Each trigger is tested on its own, because in production they never fire
/// together and a test that sets all three proves only that one of them works.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A frame that took [micros] end to end, half building and half
  /// rasterising, finishing at [atMicros].
  FrameTiming frame(int micros, {required int atMicros}) => FrameTiming(
    vsyncStart: atMicros - micros,
    buildStart: atMicros - micros,
    buildFinish: atMicros - micros ~/ 2,
    rasterStart: atMicros - micros ~/ 2,
    rasterFinish: atMicros,
    rasterFinishWallTime: atMicros,
  );

  /// Slow frames of 40 ms each, back to back, the last ending at [toMs].
  void slowRun(
    GlassCapability capability, {
    int fromMs = 0,
    required int toMs,
  }) {
    for (var t = fromMs + 40; t <= toMs; t += 40) {
      capability.reportFrames([frame(40000, atMicros: t * 1000)]);
    }
  }

  group('triggers, one at a time', () {
    test('blur is allowed by default — an unknown device still gets glass', () {
      final capability = GlassCapability();
      expect(capability.blurAllowed, isTrue);
      expect(capability.reasons, isEmpty);
    });

    test('Android below API 31: the platform reports no blur', () {
      final capability = GlassCapability(platformSupportsBlur: false);
      expect(capability.blurAllowed, isFalse);
      expect(capability.reasons, {GlassFallbackReason.platformBlurUnavailable});
    });

    test('reduce transparency alone turns blur off', () {
      final capability = GlassCapability(reduceTransparency: true);
      expect(capability.blurAllowed, isFalse);
      expect(capability.reasons, {GlassFallbackReason.reduceTransparency});
    });

    test('a two-second run of slow frames turns blur off', () {
      final capability = GlassCapability();
      var notified = 0;
      capability.addListener(() => notified++);

      // Just under the window: still frosted.
      slowRun(capability, toMs: 1960);
      expect(
        capability.blurAllowed,
        isTrue,
        reason: 'giving up before 2 s would punish a brief stall',
      );

      capability.reportFrames([frame(40000, atMicros: 2000 * 1000)]);
      expect(capability.blurAllowed, isFalse);
      expect(capability.reasons, {GlassFallbackReason.frameBudget});
      expect(notified, 1);
    });

    test('one good frame resets the streak', () {
      final capability = GlassCapability();

      slowRun(capability, toMs: 1960);
      // A frame inside budget: the device recovered.
      capability.reportFrames([frame(8000, atMicros: 1968 * 1000)]);
      // More slow frames, but the clock restarted.
      slowRun(capability, fromMs: 1968, toMs: 2128);

      expect(
        capability.blurAllowed,
        isTrue,
        reason: 'the two seconds must be continuous, not cumulative',
      );
    });

    test('once tripped, the frame trigger stays tripped', () {
      final capability = GlassCapability();
      slowRun(capability, toMs: 2040);
      expect(capability.blurAllowed, isFalse);

      // Even a long run of perfect frames does not bring glass back: flickering
      // between frosted and opaque is worse than committing to one.
      for (var t = 0; t < 60; t++) {
        capability.reportFrames([
          frame(8000, atMicros: (4000 + t * 16) * 1000),
        ]);
      }
      expect(capability.blurAllowed, isFalse);
    });

    test('#650: two slow frames with the app idle between them are not a '
        'streak', () {
      // A cold frame, then the learner reads for three seconds, then another.
      final capability = GlassCapability()
        ..reportFrames([frame(40000, atMicros: 40 * 1000)])
        ..reportFrames([frame(40000, atMicros: 3000 * 1000)]);
      // And a slow frame every half second, as a clock that ticks would draw.
      for (var t = 3500; t <= 8000; t += 500) {
        capability.reportFrames([frame(40000, atMicros: t * 1000)]);
      }
      expect(
        capability.blurAllowed,
        isTrue,
        reason: 'the idle time between them is no frame missed',
      );
    });

    test('#650: a frame on time in each phase is no miss, however long its '
        'span', () {
      // Pipelined at 60 fps: 10 ms of build, a wait, 12 ms of raster. Vsync
      // to raster end is 30 ms, over the 16 ms budget, and nothing is late.
      FrameTiming pipelined(int atMs) => FrameTiming(
        vsyncStart: (atMs - 30) * 1000,
        buildStart: (atMs - 30) * 1000,
        buildFinish: (atMs - 20) * 1000,
        rasterStart: (atMs - 12) * 1000,
        rasterFinish: atMs * 1000,
        rasterFinishWallTime: atMs * 1000,
      );
      final capability = GlassCapability();
      for (var t = 30; t <= 3000; t += 16) {
        capability.reportFrames([pipelined(t)]);
      }
      expect(capability.blurAllowed, isTrue);
    });

    test('#650: a raster alone over budget is a miss', () {
      FrameTiming slowRaster(int atMs) => FrameTiming(
        vsyncStart: (atMs - 32) * 1000,
        buildStart: (atMs - 32) * 1000,
        buildFinish: (atMs - 30) * 1000,
        rasterStart: (atMs - 30) * 1000,
        rasterFinish: atMs * 1000,
        rasterFinishWallTime: atMs * 1000,
      );
      final capability = GlassCapability();
      for (var t = 32; t <= 2100; t += 32) {
        capability.reportFrames([slowRaster(t)]);
      }
      expect(capability.blurAllowed, isFalse);
    });

    test('reasons accumulate when more than one applies', () {
      final capability = GlassCapability(
        platformSupportsBlur: false,
        reduceTransparency: true,
      );
      expect(capability.reasons, hasLength(2));
    });
  });

  group('#650: the watchdog watches only while glass is on screen', () {
    test('armed and on screen, and nothing less', () {
      final capability = GlassCapability();
      addTearDown(capability.dispose);

      capability.startFrameWatchdog();
      expect(capability.watchingFrames, isFalse, reason: 'light or dark');

      capability.glassOnScreen = true;
      expect(capability.watchingFrames, isTrue);

      capability.glassOnScreen = false;
      expect(capability.watchingFrames, isFalse);

      // perf_test.dart holds blur on: stopped, glass does not start it again.
      capability
        ..glassOnScreen = true
        ..stopFrameWatchdog();
      expect(capability.watchingFrames, isFalse);
      capability.glassOnScreen = true;
      expect(capability.watchingFrames, isFalse);
    });

    test('a streak does not carry over a time it was not watching', () {
      final capability = GlassCapability()
        ..startFrameWatchdog()
        ..glassOnScreen = true;
      addTearDown(capability.dispose);

      slowRun(capability, toMs: 1960);
      capability
        ..glassOnScreen = false
        ..glassOnScreen = true;
      capability.reportFrames([frame(40000, atMicros: 2000 * 1000)]);
      expect(capability.blurAllowed, isTrue);
    });

    test('tripped, it stops watching', () {
      final capability = GlassCapability()
        ..startFrameWatchdog()
        ..glassOnScreen = true;
      addTearDown(capability.dispose);

      slowRun(capability, toMs: 2040);
      expect(capability.blurAllowed, isFalse);
      expect(capability.watchingFrames, isFalse);
    });

    test('the app tells it from the theme', () async {
      final db = AppDatabase.memory();
      final settings = SettingsRepository(db);
      await settings.load();
      // A learner who left the app in glass: it starts in glass.
      await settings.write(SettingKeys.themeMode, ThemeModeSetting.glass);
      final container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          settingsProvider.overrideWithValue(settings),
        ],
      );
      final capability = GlassCapability()..startFrameWatchdog();
      addTearDown(() async {
        capability.dispose();
        container.dispose();
        await settings.dispose();
        await db.close();
      });

      watchGlassTheme(container, capability);
      expect(capability.watchingFrames, isTrue, reason: 'glass from the start');

      final theme = container.read(themeProvider.notifier);
      await theme.choose(ThemeModeSetting.dark);
      container.read(themeProvider);
      expect(capability.watchingFrames, isFalse);

      await theme.choose(ThemeModeSetting.glass);
      container.read(themeProvider);
      expect(capability.watchingFrames, isTrue);
    });

    test('the app is wired to it', () {
      // wireApp needs the plugins' platform side, which tests have not got.
      final main = File('lib/main.dart').readAsStringSync();
      expect(
        main.substring(main.indexOf('void wireApp(')),
        contains('watchGlassTheme(container, bootstrap.glass);'),
      );
    });
  });

  group('the platform channel', () {
    const channel = MethodChannel('sogda/glass');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('reads both flags from the native side', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'capabilities');
        return <String, dynamic>{
          'supportsBlur': false,
          'reduceTransparency': true,
        };
      });

      final capability = GlassCapability();
      await capability.queryPlatform();

      expect(capability.reasons, {
        GlassFallbackReason.platformBlurUnavailable,
        GlassFallbackReason.reduceTransparency,
      });
    });

    test('a missing native side leaves glass on, not off', () async {
      // No handler registered: MissingPluginException.
      final capability = GlassCapability();
      await capability.queryPlatform();
      expect(
        capability.blurAllowed,
        isTrue,
        reason:
            'an app that is wrongly opaque everywhere is a worse failure '
            'than a blur that costs a little on an odd device',
      );
    });

    test('a live push from the platform flips the capability', () async {
      // Battery saver engaging, or Reduce Transparency switched on from
      // Settings, must take effect without a relaunch.
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => <String, dynamic>{
          'supportsBlur': true,
          'reduceTransparency': false,
        },
      );

      final capability = GlassCapability();
      var notified = 0;
      capability.addListener(() => notified++);
      await capability.queryPlatform();
      expect(capability.blurAllowed, isTrue);

      Future<void> push(Map<String, dynamic> arguments) =>
          messenger.handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(
              MethodCall('capabilitiesChanged', arguments),
            ),
            (_) {},
          );

      await push({'supportsBlur': false});
      expect(capability.reasons, {GlassFallbackReason.platformBlurUnavailable});

      await push({'reduceTransparency': true});
      expect(capability.reasons, hasLength(2));

      // Battery saver disengaging brings blur back — unlike the frame watchdog,
      // the platform flags are not one-way.
      await push({'supportsBlur': true, 'reduceTransparency': false});
      expect(capability.blurAllowed, isTrue);
      expect(notified, greaterThanOrEqualTo(3));
    });

    test('an unchanged push notifies nobody', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => <String, dynamic>{
          'supportsBlur': true,
          'reduceTransparency': false,
        },
      );
      final capability = GlassCapability();
      await capability.queryPlatform();

      var notified = 0;
      capability.addListener(() => notified++);
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          const MethodCall('capabilitiesChanged', {'supportsBlur': true}),
        ),
        (_) {},
      );
      expect(
        notified,
        0,
        reason: 'a redundant push would rebuild every SgSurface in the tree',
      );
    });

    test('#698: a reply that is not a bool keeps the defaults', () async {
      // A cast error here failed bootstrap at step "settings".
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => <String, dynamic>{
          'supportsBlur': 1,
          'reduceTransparency': 'yes',
        },
      );
      final capability = GlassCapability();
      await capability.queryPlatform();
      expect(capability.blurAllowed, isTrue);
    });

    test('a native error leaves glass on', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'boom'),
      );
      final capability = GlassCapability();
      await capability.queryPlatform();
      expect(capability.blurAllowed, isTrue);
    });
  });

  group('SgSurface honours the capability', () {
    Future<BoxDecoration> pump(
      WidgetTester tester,
      GlassCapability capability, {
      SgSurfaceKind kind = SgSurfaceKind.card,
    }) async {
      await tester.pumpWidget(
        GlassCapabilityScope(
          notifier: capability,
          child: MaterialApp(
            theme: AppTheme.glass(),
            home: Scaffold(
              body: Center(
                child: SgSurface(kind: kind, child: const Text('Revise')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
              .widgetList<DecoratedBox>(
                find.descendant(
                  of: find.byType(SgSurface),
                  matching: find.byType(DecoratedBox),
                ),
              )
              .first
              .decoration
          as BoxDecoration;
    }

    testWidgets('blur allowed: a BackdropFilter is present', (tester) async {
      await pump(tester, GlassCapability.always());
      expect(
        find.descendant(
          of: find.byType(SgSurface),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
    });

    for (final (name, capability) in <(String, GlassCapability Function())>[
      ('no platform blur', GlassCapability.never),
      ('reduce transparency', () => GlassCapability(reduceTransparency: true)),
    ]) {
      testWidgets('$name: no BackdropFilter is built at all', (tester) async {
        await pump(tester, capability());
        expect(
          find.descendant(
            of: find.byType(SgSurface),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
          reason: 'a BackdropFilter that cannot blur still costs a saveLayer',
        );
      });

      testWidgets('$name: the fallback is 92 % opaque, not transparent', (
        tester,
      ) async {
        final decoration = await pump(tester, capability());
        expect(decoration.color!.a, closeTo(0.92, 0.005));
        // Same hue as the glass fill — it is the same surface, just solid.
        expect(
          (decoration.color!.r * 255).round(),
          (SgSurfaceTokens.glass.card.r * 255).round(),
        );
      });
    }

    testWidgets('the frame-budget trigger degrades a live tree', (
      tester,
    ) async {
      final capability = GlassCapability();
      await pump(tester, capability);
      expect(
        find.descendant(
          of: find.byType(SgSurface),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );

      slowRun(capability, toMs: 2040);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(SgSurface),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
        reason: 'the scope must rebuild its subtree when capability changes',
      );
    });

    testWidgets('a tint keeps its own weight when glass degrades', (
      tester,
    ) async {
      // A tint is a colour wash, not a panel: forcing it to 92 % would turn the
      // Lagoon Today header into a solid block.
      final decoration = await pump(
        tester,
        GlassCapability.never(),
        kind: SgSurfaceKind.tint(SgPalette.light.die),
      );
      expect(decoration.color!.a, closeTo(0.22, 0.01));
    });

    testWidgets('the solid modes are untouched by the capability', (
      tester,
    ) async {
      await tester.pumpWidget(
        GlassCapabilityScope(
          notifier: GlassCapability.never(),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: Center(child: SgSurface(child: Text('Revise'))),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final decoration =
          tester
                  .widgetList<DecoratedBox>(
                    find.descendant(
                      of: find.byType(SgSurface),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .first
                  .decoration
              as BoxDecoration;
      expect(decoration.color, SgSurfaceTokens.light.card);
    });
  });
}
