import 'dart:ui' show FrameTiming;

import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/core/theme/dp_surface.dart';
import 'package:deutschplan/core/theme/dp_tokens.dart';
import 'package:deutschplan/core/theme/glass_capability.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// theming.md: "`GlassPanel` degrades to a 92 %-opaque tinted surface when:
/// Android API < 31, the device missed the frame budget for 2 s, or the OS
/// 'reduce transparency' setting is on."
///
/// Each trigger is tested on its own, because in production they never fire
/// together and a test that sets all three proves only that one of them works.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A frame that took [micros] end to end, finishing at [atMicros].
  FrameTiming frame(int micros, {required int atMicros}) => FrameTiming(
    vsyncStart: atMicros - micros,
    buildStart: atMicros - micros,
    buildFinish: atMicros - micros ~/ 2,
    rasterStart: atMicros - micros ~/ 2,
    rasterFinish: atMicros,
    rasterFinishWallTime: atMicros,
  );

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
      for (var t = 0; t < 1900; t += 100) {
        capability.reportFrames([frame(40000, atMicros: t * 1000)]);
      }
      expect(
        capability.blurAllowed,
        isTrue,
        reason: 'giving up before 2 s would punish a brief stall',
      );

      capability.reportFrames([frame(40000, atMicros: 2100 * 1000)]);
      expect(capability.blurAllowed, isFalse);
      expect(capability.reasons, {GlassFallbackReason.frameBudget});
      expect(notified, 1);
    });

    test('one good frame resets the streak', () {
      final capability = GlassCapability();

      for (var t = 0; t < 1900; t += 100) {
        capability.reportFrames([frame(40000, atMicros: t * 1000)]);
      }
      // A frame inside budget: the device recovered.
      capability.reportFrames([frame(8000, atMicros: 1950 * 1000)]);
      // More slow frames, but the clock restarted.
      capability.reportFrames([frame(40000, atMicros: 2100 * 1000)]);

      expect(
        capability.blurAllowed,
        isTrue,
        reason: 'the two seconds must be continuous, not cumulative',
      );
    });

    test('once tripped, the frame trigger stays tripped', () {
      final capability = GlassCapability();
      capability
        ..reportFrames([frame(40000, atMicros: 0)])
        ..reportFrames([frame(40000, atMicros: 3000 * 1000)]);
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

    test('reasons accumulate when more than one applies', () {
      final capability = GlassCapability(
        platformSupportsBlur: false,
        reduceTransparency: true,
      );
      expect(capability.reasons, hasLength(2));
    });
  });

  group('the platform channel', () {
    const channel = MethodChannel('deutschplan/glass');
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

  group('DpSurface honours the capability', () {
    Future<BoxDecoration> pump(
      WidgetTester tester,
      GlassCapability capability, {
      DpSurfaceKind kind = DpSurfaceKind.card,
    }) async {
      await tester.pumpWidget(
        GlassCapabilityScope(
          notifier: capability,
          child: MaterialApp(
            theme: AppTheme.glass(),
            home: Scaffold(
              body: Center(
                child: DpSurface(kind: kind, child: const Text('Revise')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
              .widgetList<DecoratedBox>(
                find.descendant(
                  of: find.byType(DpSurface),
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
          of: find.byType(DpSurface),
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
            of: find.byType(DpSurface),
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
          (DpSurfaceTokens.glass.card.r * 255).round(),
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
          of: find.byType(DpSurface),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );

      capability
        ..reportFrames([frame(40000, atMicros: 0)])
        ..reportFrames([frame(40000, atMicros: 3000 * 1000)]);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(DpSurface),
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
        kind: DpSurfaceKind.tint(DpPalette.light.die),
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
              body: Center(child: DpSurface(child: Text('Revise'))),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final decoration =
          tester
                  .widgetList<DecoratedBox>(
                    find.descendant(
                      of: find.byType(DpSurface),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .first
                  .decoration
              as BoxDecoration;
      expect(decoration.color, DpSurfaceTokens.light.card);
    });
  });
}
