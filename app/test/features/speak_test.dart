import 'dart:async';

import 'package:deutschplan/core/components/dp_speaker_button.dart';
import 'package:deutschplan/core/providers/app_providers.dart';
import 'package:deutschplan/core/theme/app_theme.dart';
import 'package:deutschplan/data/db/app_database.dart';
import 'package:deutschplan/data/repositories/setting_keys.dart';
import 'package:deutschplan/data/repositories/settings_repository.dart';
import 'package:deutschplan/features/words/speak.dart';
import 'package:deutschplan/l10n/generated/app_localizations.dart';
import 'package:deutschplan/main.dart'
    show appLocalizationsDelegates, supportedLocales;
import 'package:deutschplan/services/tts/tts_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../services/fake_tts.dart';

/// #151's seam and #153's service: every speaker speaks through `ttsProvider`;
/// one with no German voice behind it is slashed and says how to install one
/// (accessibility-performance.md); the phone voice standing in for Supertonic
/// says so once, with a link to Settings; and a speaker draws what the one
/// player is doing with its own text.
void main() {
  late AppLocalizations l10n;
  late SettingsRepository settings;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  /// Speakers for [texts], over [overrides] — [fakeVoice] by default.
  Future<void> pump(
    WidgetTester tester,
    List<Override> overrides, {
    List<String> texts = const <String>['Hallo'],
  }) async {
    await tester.runAsync(() async {
      final db = AppDatabase.memory();
      settings = SettingsRepository(db);
      await settings.load();
      await settings.write(SettingKeys.ttsSpeed, 1.25);
      addTearDown(
        () => tester.runAsync(() async {
          await settings.dispose();
          await db.close();
        }),
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWithValue(settings), ...overrides],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          routerConfig: GoRouter(
            routes: <RouteBase>[
              GoRoute(
                path: '/',
                builder: (_, _) => Scaffold(
                  body: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (final text in texts)
                          Consumer(
                            builder: (context, ref, _) => DpSpeakerButton(
                              key: ValueKey<String>(text),
                              semanticLabel: text,
                              state: speakerState(ref, text),
                              onPressed: () => say(ref, context, text),
                              onLongPress: () =>
                                  say(ref, context, text, pace: 0.75),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              GoRoute(
                path: '/me/settings',
                builder: (_, _) => const Scaffold(body: Text('M3')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  DpSpeakerState state(WidgetTester tester, [String text = 'Hallo']) =>
      tester.widget<DpSpeakerButton>(find.byKey(ValueKey<String>(text))).state;

  testWidgets('V01 a speaker says its text at tts_speed, and at 0.75× of it '
      'on a long-press (FR-T2-09)', (tester) async {
    final tts = FakeTts();
    await pump(tester, [fakeVoice(tts)]);
    expect(state(tester), DpSpeakerState.idle);

    await tester.tap(find.byType(DpSpeakerButton));
    await tester.longPress(find.byType(DpSpeakerButton));
    await tester.pump();

    expect(tts.said, <(String, double)>[('Hallo', 1.25), ('Hallo', 0.9375)]);
    expect(find.text(l10n.speakerNoVoice), findsNothing);
  });

  testWidgets('V01 no German voice: slashed before any tap, and each tap says '
      'how to install one', (tester) async {
    await pump(tester, [fakeVoice(FakeTts(voice: false))]);
    expect(state(tester), DpSpeakerState.unavailable);

    await tester.tap(find.byType(DpSpeakerButton));
    await tester.pump();
    expect(find.text(l10n.speakerNoVoice), findsOneWidget);
  });

  testWidgets('V01 a voice that goes away: the tap that failed slashes the '
      'speaker', (tester) async {
    final tts = FakeTts();
    await pump(tester, [fakeVoice(tts)]);
    expect(state(tester), DpSpeakerState.idle);

    tts.voice = false;
    await tester.tap(find.byType(DpSpeakerButton));
    await tester.pumpAndSettle();

    expect(find.text(l10n.speakerNoVoice), findsOneWidget);
    expect(state(tester), DpSpeakerState.unavailable);
  });

  group('V03 Supertonic missing: the phone voice speaks', () {
    late FakeTts phone;
    late List<Override> missing;

    setUp(() {
      phone = FakeTts();
      // No `supertonicVoiceProvider` override: null, as it is until #152.
      missing = [systemTtsProvider.overrideWithValue(phone)];
    });

    testWidgets('and the first time says so, once a session', (tester) async {
      await pump(tester, missing);
      await tester.tap(find.byType(DpSpeakerButton));
      await tester.pump();
      expect(phone.spoken, <String>['Hallo']);
      expect(find.text(l10n.speakerFallback), findsOneWidget);
      expect(find.text(l10n.speakerNoVoice), findsNothing);

      // In, then DpUndo's 4 s, as a toast with a link has.
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text(l10n.speakerFallback), findsNothing);
      await tester.tap(find.byType(DpSpeakerButton));
      await tester.pumpAndSettle();
      expect(phone.spoken, <String>['Hallo', 'Hallo']);
      expect(find.text(l10n.speakerFallback), findsNothing);
    });

    testWidgets('with a link that opens Settings', (tester) async {
      await pump(tester, missing);
      await tester.tap(find.byType(DpSpeakerButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.speakerFallbackSettings));
      await tester.pumpAndSettle();
      expect(find.text('M3'), findsOneWidget);
    });
  });

  testWidgets('V03 the speaker that is playing shows the bars, and no '
      'other', (tester) async {
    final tts = FakeTts(holds: true);
    await pump(tester, [fakeVoice(tts)], texts: <String>['Hallo', 'Tschüss']);

    await tester.tap(find.byKey(const ValueKey<String>('Hallo')));
    await tester.pump();
    expect(state(tester), DpSpeakerState.playing);
    expect(state(tester, 'Tschüss'), DpSpeakerState.idle);

    await tester.tap(find.byKey(const ValueKey<String>('Tschüss')));
    await tester.pump();
    expect(state(tester), DpSpeakerState.idle, reason: 'stopped');
    expect(state(tester, 'Tschüss'), DpSpeakerState.playing);

    tts.finish();
    await tester.pump();
    expect(state(tester, 'Tschüss'), DpSpeakerState.idle);
  });

  testWidgets('V03 the spinner only once synthesis passes 150 ms', (
    tester,
  ) async {
    final tts = FakeTts(holds: true)..synthesis = Completer<void>();
    await pump(tester, [fakeVoice(tts)]);

    await tester.tap(find.byType(DpSpeakerButton));
    await tester.pump(const Duration(milliseconds: 140));
    expect(state(tester), DpSpeakerState.idle);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
    expect(state(tester), DpSpeakerState.loading);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    tts.synthesis!.complete();
    await tester.pump();
    await tester.pump();
    expect(state(tester), DpSpeakerState.playing);
    tts.finish();
    await tester.pumpAndSettle();
  });

  test('V03 ttsProvider is the service over the phone voice and the '
      'Supertonic slot, null until #152', () async {
    final phone = FakeTts();
    final db = AppDatabase.memory();
    final settings = SettingsRepository(db);
    await settings.load();
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWithValue(settings),
        systemTtsProvider.overrideWithValue(phone),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await settings.dispose();
      await db.close();
    });

    expect(container.read(supertonicVoiceProvider), isNull);
    expect(container.read(ttsProvider), isA<TtsService>());
    expect(await container.read(ttsAvailableProvider.future), isTrue);
    phone.voice = false;
    container.invalidate(ttsAvailableProvider);
    expect(await container.read(ttsAvailableProvider.future), isFalse);
  });
}
