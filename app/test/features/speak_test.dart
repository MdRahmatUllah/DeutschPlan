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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../services/fake_tts.dart';

/// #151's seam: every speaker speaks through `ttsProvider`, and one with no
/// German voice behind it is slashed and says how to install one
/// (accessibility-performance.md).
void main() {
  late AppLocalizations l10n;
  late SettingsRepository settings;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(supportedLocales.first);
  });

  Future<void> pump(WidgetTester tester, FakeTts tts) async {
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
        overrides: [
          settingsProvider.overrideWithValue(settings),
          ttsProvider.overrideWithValue(tts),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: supportedLocales,
          home: Scaffold(
            body: Center(
              child: Consumer(
                builder: (context, ref, _) => DpSpeakerButton(
                  semanticLabel: 'Hallo',
                  state: speakerState(ref),
                  onPressed: () => say(ref, context, 'Hallo'),
                  onLongPress: () => say(ref, context, 'Hallo', pace: 0.75),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  DpSpeakerState state(WidgetTester tester) =>
      tester.widget<DpSpeakerButton>(find.byType(DpSpeakerButton)).state;

  testWidgets('V01 a speaker says its text at tts_speed, and at 0.75× of it '
      'on a long-press (FR-T2-09)', (tester) async {
    final tts = FakeTts();
    await pump(tester, tts);
    expect(state(tester), DpSpeakerState.idle);

    await tester.tap(find.byType(DpSpeakerButton));
    await tester.longPress(find.byType(DpSpeakerButton));
    await tester.pump();

    expect(tts.said, <(String, double)>[('Hallo', 1.25), ('Hallo', 0.9375)]);
    expect(find.text(l10n.speakerNoVoice), findsNothing);
  });

  testWidgets('V01 no German voice: slashed before any tap, and each tap says '
      'how to install one', (tester) async {
    await pump(tester, FakeTts(voice: false));
    expect(state(tester), DpSpeakerState.unavailable);

    await tester.tap(find.byType(DpSpeakerButton));
    await tester.pump();
    expect(find.text(l10n.speakerNoVoice), findsOneWidget);
  });

  testWidgets('V01 a voice that goes away: the tap that failed slashes the '
      'speaker', (tester) async {
    final tts = FakeTts();
    await pump(tester, tts);
    expect(state(tester), DpSpeakerState.idle);

    tts.voice = false;
    await tester.tap(find.byType(DpSpeakerButton));
    await tester.pumpAndSettle();

    expect(find.text(l10n.speakerNoVoice), findsOneWidget);
    expect(state(tester), DpSpeakerState.unavailable);
  });

  test('V01 the tts seam is the phone voice until #153 chooses', () async {
    final phone = FakeTts();
    final container = ProviderContainer(
      overrides: [systemTtsProvider.overrideWithValue(phone)],
    );
    addTearDown(container.dispose);

    expect(container.read(ttsProvider), same(phone));
    expect(await container.read(ttsAvailableProvider.future), isTrue);
    phone.voice = false;
    container.invalidate(ttsAvailableProvider);
    expect(await container.read(ttsAvailableProvider.future), isFalse);
  });
}
